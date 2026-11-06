# Oracle 19c 설치 자동화 기술서 — v2.1

> Vagrant + Ansible로 빈 PC에서 Oracle 19c 운영 상태까지 29분 — 설계 · 코드 · 왜 · 검증 · 질문 대비
> v2.1 · 2026-10-28 실행 검증 완료

- **한 줄 요약**: **명령 한 줄(`vagrant up`)로** 빈 Windows PC에 Oracle Linux 8 VM을 만들고, Oracle 19c 설치 · DB 생성 · 운영 설정 · 점검까지 **사람 손 없이 29분**에 끝낸다
- **결과물**: `D:\vagrant\oracle19c` — Vagrantfile 1개 · Ansible 플레이북(10단계, 50개 작업) · 점검 스크립트 `check.sh` · README
- **검증**: 2026-10-28 강영수 PC 한 대(Windows · VirtualBox 7.2.14 · Vagrant 2.4.9)에서 실측 — 설치 직후 · 재부팅 후 · 삭제 후 재생성 모두 `FAIL 0`, PC의 DBeaver에서 PDB 접속. **다른 PC**는 사전 점검 스크립트(`check-host.ps1`)로 조건을 확인한 뒤 실행 — 다른 PC 실행 기록은 아직 없음(C4)
- **이 문서의 쓰임**: 면접 · 멘토 앞에서 **무엇을, 왜 그렇게 만들었는지** 설명하는 기술서. 실행 순서만 필요하면 README, 손으로 설치하려면 수동 설치 가이드(dbts93)
- **범위 밖**: RAC · Data Guard · RMAN 백업 자동화 · 운영 모니터링. 설치 파일은 Oracle 계정이 필요해 자동으로 받지 않는다(직접 받아 `media`에 둔다)

## O. 한눈에

*결과 숫자 · 전체 구조 · v1 → v2 · 파일 구성*

### O1. 결과부터

| 28분 55초 | 50 / 0 | FAIL 0 | Enforcing |
|---|---|---|---|
| vagrant up 한 번 · VM 삭제 후 재생성 실측 | 작업 수 / 실패 · ok=50 changed=22 failed=0 | 점검 3회 · 설치 직후 · 재부팅 후 · 재생성 후 | SELinux · 끄지 않고 운영 |

만들어지는 것은 **연습용 빈 DB가 아니라 운영 습관을 갖춘 DB 서버**다. 아카이브 로그, HugePages, 재부팅 자동 기동, 방화벽 유지, SELinux 유지까지 들어 있고, 마지막에 같은 점검 스크립트로 스스로 검사한다.

| 항목 | 값 |
|---|---|
| VM | `dbts94` · 192.168.10.94 · RAM 4GB · CPU 2 · Oracle Linux 8.10(UEK 5.15) |
| 디스크 | OS + `/u01` 50GB · `/oradata` 60GB · `/backup` 70GB (각각 LVM + xfs) |
| DB | Oracle 19c(19.3) EE · CDB `orcl` + PDB `pdb` · AL32UTF8 · ASMM(SGA 1152MB · PGA 384MB) |
| 운영 설정 | ARCHIVELOG(`/backup/arch`) · HugePages 592장 · THP 끔 · oratab + systemd 자동 기동 · PDB SAVE STATE |
| 접속 | PC의 DBeaver → `192.168.10.94:1521` · Service Name `pdb` |

---

### O2. 전체 구조

> [이미지 자리: 그림 — PC의 D 드라이브 두 폴더가 VM 안의 /vagrant · /stage로 연결되고, Ansible은 VM 안에서 자기 자신을 설치한다]

| 선택 | 왜 · 다르게 하면 |
|---|---|
| `media`와 프로젝트 분리 | 3GB 설치 파일은 저장소에 넣지 않는다. 코드(프로젝트)는 공유 · 버전 관리하고, 라이선스가 걸린 파일은 각자 받아 둔다 |
| `/stage`는 읽기 전용 | VM 안의 실수(삭제 · 덮어쓰기)가 PC의 원본 설치 파일에 닿지 않게 한다 |
| Ansible이 VM 안에서 실행 | Windows에는 Ansible이 없다. WSL을 깔지 않고 VM 안에서 돌리면 어느 PC든 VirtualBox + Vagrant만 있으면 된다 |

---

### O3. v1 → v2 — 무엇을 왜 바꿨나

v1(2026-09, Rocky Linux 9)은 '내 PC에서 그때는 됐던' 자동화였다. 검증 보고서(10/27)가 찾은 문제를 하나씩 없앤 것이 v2다.

| v1의 문제 | 결과 | v2의 선택 |
|---|---|---|
| Rocky 9 + 19.3 (Oracle 비인증) | 링크 에러 → glibc 라이브러리를 바꿔 넣는 우회 | **Oracle Linux 8 공식 박스** — 우회 자체가 필요 없음 |
| `-memoryMgmtType ASMM` (없는 값) | AMM으로 생성 → HugePages 첫 실행 항상 실패 | `AUTO_SGA` + `-totalMemory 1536` + 생성 직후 검사 |
| WSL에서 원격 실행 | WSL 네트워크 설정 · 인벤토리가 PC마다 다름 | **ansible_local** — VM 안에서 실행 |
| `/dev/sdb` 이름에 의존 | 디스크 순서가 바뀌면 엉뚱한 디스크를 포맷 | 디스크 **크기**(50/60/70GB)로 찾기 |
| 재부팅하면 DB가 안 뜸 | ORA-12541 · ORA-01109 | oratab + systemd + SAVE STATE |
| 방화벽 끄기 · 체크섬 없음 | 운영 습관과 다름 · 손상된 파일로 설치 | 1521만 허용 · 설치 zip SHA256 자동 확인 |
| generic/rocky9 박스 | 공개 Vagrant 저장소 2026-12 종료 예정 | Oracle이 직접 배포하는 박스 주소 |

---

### O4. 파일 구성

📄 `D:\vagrant\`
```text
media\                          설치 파일 (VM: /stage, 읽기 전용)
└─ LINUX.X64_193000_db_home.zip
oracle19c\                      프로젝트 (VM: /vagrant)
├─ Vagrantfile                   VM 사양 · 디스크 · 네트워크 · 프로비저닝 2단계
├─ ansible\
│  ├─ site.yml                   10단계 순서 · 태그
│  ├─ vars.yml                   SID · 경로 · 메모리 · 설치 파일 SHA256
│  ├─ ansible.cfg                로그 /vagrant/logs/ansible.log
│  ├─ tasks\  00_media ~ 90_verify (10개)
│  ├─ templates\  listener.ora · sqlnet.ora · tnsnames.ora · oracle-db.service
│  └─ files\setup_disk.sh        크기로 디스크 찾기 → LVM → xfs → 마운트
├─ scripts\check.sh              점검 17항목 (설치 직후 · 재부팅 후 공용)
├─ scripts\check-host.ps1        사전 점검 (vagrant up 전, Windows PC 조건)
├─ disks\                        추가 디스크 vdi (자동 생성)
└─ logs\                         ansible.log · verify_*.txt
```

---

## A. 실행 환경 — Vagrantfile

*박스 · 네트워크 · 디스크 · 공유 폴더 · 프로비저닝 2단계*

### 1. 박스와 VM 사양

**목표**: 누가 만들어도 같은 OS · 같은 사양의 VM이 나오게 한다.

📄 `Vagrantfile`
```ruby
VM_NAME   = "dbts94"
VM_IP     = "192.168.10.94"
VM_MEMORY = 4096
VM_CPUS   = 2
DISKS = { "u01" => 50, "oradata" => 60, "backup" => 70 }   # 크기가 서로 달라야 함

config.vm.box      = "oraclelinux/8"
config.vm.box_version = "8.10.700"           # 검증한 박스로 고정
config.vm.box_url  = "https://oracle.github.io/vagrant-projects/boxes/oraclelinux/8.json"
config.vm.hostname = "#{VM_NAME}.localdomain"
```

| 선택 | 왜 · 다르게 하면 |
|---|---|
| Oracle Linux 8 공식 박스 | Oracle DB가 인증한 OS를 Oracle이 직접 배포. preinstall RPM이 기본 저장소에 있다. 2026-10-28 받은 버전은 8.10(v8.10.700) |
| `box_version` 고정 | 지정하지 않으면 그날의 최신 박스를 받는다. 몇 달 뒤 Oracle이 새 박스를 내면 검증하지 않은 OS로 설치된다. 검증한 8.10.700으로 고정하고, 바꿀 때는 다시 검증 |
| `box_url`을 직접 지정 | HashiCorp 공개 저장소(Vagrant Cloud)가 2026년 말 종료 예정. Oracle의 주소를 쓰면 영향이 없다 |
| 맨 위 상수 5개 | IP · 메모리 · 디스크를 바꾸고 싶으면 이 다섯 줄만 고친다. 아래 코드와 Ansible이 이 값을 받아 쓴다(`extra_vars`) |

---

### 2. 네트워크 · 공유 폴더

**목표**: PC에서 DB로 들어오는 길과, VM이 설치 파일을 읽는 길을 만든다.

📄 `Vagrantfile`
```ruby
config.vm.network "private_network", ip: VM_IP          # Host-Only: PC ↔ VM
config.vm.synced_folder "../media", "/stage", mount_options: ["ro"]
```

| 선택 | 왜 · 다르게 하면 |
|---|---|
| NAT(자동) + Host-Only | NAT는 Vagrant가 기본으로 붙이는 인터넷 출구(dnf · 박스 업데이트), Host-Only는 고정 IP로 SSH · 1521 접속 |
| 상대 경로 `../media` | 드라이브 문자 · 사용자 이름을 코드에 넣지 않는다. 프로젝트를 다른 PC의 다른 경로로 옮겨도 그대로 동작 |
| Linux/Mac 호스트 | VirtualBox가 Host-Only 대역을 `192.168.56.0/21`로 제한한다. `/etc/vbox/networks.conf`에 `* 192.168.10.0/24`를 넣어야 한다(README 표시) |

---

### 3. 데이터 디스크 3개

**목표**: OS와 Oracle 파일을 다른 디스크에 둔다. 디스크는 프로젝트 폴더 안에 만들어 함께 관리한다.

📄 `Vagrantfile`
```ruby
DISKS.each_with_index do |(name, gb), i|
  disk = File.join(__dir__, "disks", "#{name}.vdi")
  unless File.exist?(disk)
    vb.customize ["createmedium", "disk", "--filename", disk, "--size", gb * 1024, "--format", "VDI"]
  end
  # Oracle 공식 박스의 컨트롤러 이름은 "SATA Controller", 0번 포트는 OS 디스크
  vb.customize ["storageattach", :id, "--storagectl", "SATA Controller",
                "--port", i + 1, "--device", 0, "--type", "hdd", "--medium", disk]
end
```

| 선택 | 왜 · 다르게 하면 |
|---|---|
| `unless File.exist?` | `vagrant reload` 때마다 디스크를 새로 만들면 데이터가 사라진다. 있으면 붙이기만 한다 |
| 크기를 50 · 60 · 70으로 | Ansible이 장치 이름이 아니라 **크기**로 디스크를 찾게 하려는 장치(B-20 단계) |
| Oracle 공식 프로젝트와 같은 방식 | Oracle의 vagrant-projects 저장소(OracleDG 19.3.0 · OracleTC 구성)도 같은 `storageattach` 방식을 쓴다. Vagrant의 실험 기능(`disks`)에 의존하지 않는다 |

> **⚠️ 주의** — 다시 만들 때는 `vagrant destroy` 뒤에 `disks\*.vdi`가 남았는지 확인한다. 남아 있으면 새 VM에 **옛 디스크(옛 DB 파일)**가 붙는다.

---

### 4. 프로비저닝 2단계 — bootstrap과 ansible_local

**목표**: VM이 뜨면 ① VM 안에 Ansible을 깔고 ② 그 Ansible로 Oracle을 설치한다.

📄 `Vagrantfile`
```ruby
config.vm.provision "bootstrap", type: "shell", inline: <<-SHELL
  set -e
  mkdir -p /vagrant/logs
  rpm -q ansible-core acl >/dev/null 2>&1 || dnf -y -q install ansible-core acl
SHELL

config.vm.provision "oracle", type: "ansible_local" do |a|
  a.install            = false
  a.compatibility_mode = "2.0"
  a.provisioning_path  = "/vagrant/ansible"
  a.config_file        = "/vagrant/ansible/ansible.cfg"
  a.playbook           = "site.yml"
  a.extra_vars         = { db_hostname: VM_NAME, db_ip: VM_IP, disk_sizes_gb: DISKS }
  a.tags               = ENV["ORA_TAGS"] if ENV["ORA_TAGS"]
end
```

| 선택 | 왜 · 다르게 하면 |
|---|---|
| ansible-core는 OL8 AppStream에서 | pip · EPEL 없이 OS 저장소 패키지(2.16.3)를 쓴다. 버전이 OS와 함께 관리된다 |
| `acl` | Ansible이 root → oracle 사용자로 바꿔 명령을 실행할 때 임시 파일 권한에 필요 |
| `config_file`을 직접 지정 | `/vagrant`는 Windows 공유 폴더라 권한이 777로 보인다. Ansible은 이런 폴더의 `ansible.cfg`를 보안상 무시하므로 경로를 명시한다 |
| `ORA_TAGS` | PowerShell에서 `$env:ORA_TAGS="hugepages,verify"`처럼 일부 단계만 다시 실행 — 실제로 SELinux 수정 뒤 이 방법으로 3단계만 재실행했다 |

---

## B. 플레이북 10단계

*site.yml — 단계마다 무엇 · 핵심 코드 · 왜 · 다르게 하면*

### B0. 전체 흐름과 설계 원칙

**목표**: 10단계가 어떤 순서로, 어떤 원칙으로 짜였는지 먼저 본다.

> [이미지 자리: 그림 — 10단계 · 각 단계 끝의 검사(✔)를 통과해야 다음 단계로 간다]

| 원칙 | 코드에서 | 왜 |
|---|---|---|
| **다시 실행해도 안전** | `creates:` · 상태 확인 후 실행 | 실패한 곳을 고치고 그대로 다시 돌리면 끝난 단계는 건너뛴다(멱등성) |
| **조용히 실패하지 않기** | 단계 끝마다 `assert` | SHA256 · `bin/oracle` 크기 · `memory_target=0` · HugePages 사용 여부를 확인하고 아니면 멈춘다 |
| **태그로 일부만** | `tags: [os]` … `[verify]` | 고친 단계만 다시 — 실제로 `autostart,hugepages,verify`만 재실행 |
| **값은 한 곳에** | `vars.yml` · Vagrantfile 상수 | SID · 경로 · 메모리를 바꿀 때 코드를 뒤지지 않는다 |
| **이유를 코드 옆에** | 주석에 v1 문제 번호(M1 · M7 …) | 6개월 뒤의 나 · 면접관이 '왜 이렇게?'를 코드에서 바로 본다 |

---

### 00. 설치 파일 확인

**목표**: 3GB 설치 zip이 있고, 받은 그대로인지(SHA256) 먼저 확인한다.

📄 `tasks/00_media.yml`
```yaml
- name: 설치 파일 확인 · SHA256 계산
  ansible.builtin.stat:
    path: "{{ stage_dir }}/{{ db_zip }}"
    get_checksum: true
    checksum_algorithm: sha256
  register: db_zip_stat

- name: 설치 파일이 있고 손상되지 않았는지 확인
  ansible.builtin.assert:
    that:
      - db_zip_stat.stat.exists
      - db_zip_stat.stat.checksum == db_zip_sha256      # oracle.com 다운로드 페이지 값
# … RU zip + OPatch zip이 둘 다 있으면 apply_ru = true
```

| 선택 | 왜 · 다르게 하면 |
|---|---|
| 맨 처음에 검사 | 손상된 zip은 압축 해제 · 링크 같은 엉뚱한 단계에서 실패해 원인을 찾기 어렵다. 20분 뒤가 아니라 1분 만에 멈춘다 |
| RU 자동 판단 | `p36912597`(19.25 RU)와 `p6880880`(OPatch) zip이 `media`에 있으면 설치하면서 적용(`-applyRU`), 없으면 19.3. 코드는 같다 |

---

### 10. OS 준비

**목표**: preinstall RPM · /etc/hosts · THP · 방화벽을 Oracle 권장 상태로 맞춘다.

📄 `tasks/10_os.yml`
```yaml
- ansible.builtin.dnf:
    name: [oracle-database-preinstall-19c, unzip, bc, lsof]

# Vagrant가 hostname을 127.0.x.1에 붙여 두면 리스너 · DBCA가 루프백으로 잡힌다
- ansible.builtin.lineinfile:
    path: /etc/hosts
    regexp: '^127\.\S+\s.*\b{{ db_hostname }}\b'
    state: absent
- ansible.builtin.lineinfile:
    path: /etc/hosts
    line: "{{ db_ip }}  {{ db_hostname }}.localdomain {{ db_hostname }}"

- ansible.builtin.command: grubby --update-kernel=ALL --args="transparent_hugepage=never"
  when: "'transparent_hugepage=never' not in grubby_info.stdout"
```

| 선택 | 왜 · 다르게 하면 |
|---|---|
| preinstall RPM | 커널 파라미터 · oracle 계정과 그룹(oinstall 54321 · dba 54322 …) · limits를 Oracle 권장값으로 한 번에 |
| /etc/hosts 정리 | v1에서 DBCA가 `No valid IP Address returned for the host`로 실패했던 원인. 이름이 서비스 IP로 풀려야 리스너도 밖에서 보인다 |
| THP는 `grubby` | v1에서 grub 파일 방식이 UEFI에서 먹지 않았다. `grubby`는 설치된 모든 커널의 부팅 옵션을 직접 고친다 |
| 방화벽은 끄지 않음 | 켜져 있으면 1521만 연다. 이 박스는 firewalld가 꺼진 채 배포되어 '해당 없음'이었다 |

---

### 20. 디스크 — 크기로 찾기

**목표**: 50 · 60 · 70GB 디스크를 크기로 찾아 VG → LV → xfs → 마운트. SELinux 라벨까지.

📄 `files/setup_disk.sh`
```bash
BYTES=$(( GB * 1024 * 1024 * 1024 ))
mapfile -t DEVS < <(lsblk -b -dn -o NAME,SIZE,TYPE | awk -v s="$BYTES" '$2==s && $3=="disk"{print "/dev/"$1}')
if [ "${#DEVS[@]}" -ne 1 ]; then
  echo "${GB}GB 디스크를 정확히 1개 찾지 못했습니다" >&2; exit 1
fi
if blkid "$DEV" >/dev/null 2>&1; then echo "$DEV 에 이미 다른 데이터가 있습니다. 중단합니다." >&2; exit 1; fi
pvcreate -q "$DEV"; vgcreate -q "$VG" "$DEV"
lvs "$VG/$LV" >/dev/null 2>&1 || lvcreate -q -y -l 100%FREE -n "$LV" "$VG"
mkfs.xfs -q "/dev/$VG/$LV"
echo "/dev/mapper/$VG-$LV  $MNT  xfs  defaults  0 0" >> /etc/fstab
mount "$MNT"
selinuxenabled && restorecon -R "$MNT"      # 새 파일 시스템은 라벨이 없다 (D 파트)
```

| 선택 | 왜 · 다르게 하면 |
|---|---|
| 크기로 찾기 | `/dev/sdb`는 고정이 아니다. 디스크 순서가 바뀌면 이름만 믿는 스크립트는 **엉뚱한 디스크를 포맷**한다. 크기가 정확히 맞는 빈 디스크가 하나일 때만 진행 |
| `blkid`로 한 번 더 | 이미 파일 시스템이 있는 디스크면 멈춘다 — 자동화가 데이터를 지우는 사고를 막는 마지막 안전장치 |
| `-l 100%FREE` | `-L 50G`처럼 정확히 요청하면 PV 메타데이터 몫 때문에 `Insufficient free space`(v1 실측) |
| `restorecon` | D 파트의 SELinux 문제를 근본에서 막는 한 줄. 2차 실행에서는 60단계의 라벨 정리가 '바꿀 것 없음'으로 지나갔다 |

---

### 30. 소프트웨어 설치 — runInstaller

**목표**: 엔진만 설치(Software Only)하고, 링크가 제대로 됐는지 크기로 확인한다.

📄 `tasks/30_software.yml`
```yaml
- name: runInstaller — 소프트웨어만 설치
  ansible.builtin.shell: |
    cd {{ oracle_home }}
    ./runInstaller -silent -ignorePrereqFailure -waitforcompletion \
      {{ ('-applyRU ' + patch_dir + '/' + ru_patch_id) if (apply_ru | bool) else '' }} \
      oracle.install.option=INSTALL_DB_SWONLY \
      oracle.install.db.InstallEdition=EE \
      # … 경로 · OS 그룹 6개 …
    rc=$?
    if [ $rc -eq 0 ] || [ $rc -eq 6 ]; then exit 0; fi     # 6 = 경고와 함께 성공
    exit $rc
  args:
    creates: "{{ oracle_inventory }}/ContentsXML/inventory.xml"
  environment: "{{ ora_env }}"          # CV_ASSUME_DISTID=OEL7.8 포함
  become_user: oracle

- name: oracle 실행 파일 크기 검사
  ansible.builtin.assert:
    that: ora_bin.stat.exists and ora_bin.stat.size > 100000000
```

🖥 **실행 결과 (2026-10-28, 1차 · 2차 동일)** (실제 출력)
```text
TASK [oracle 실행 파일 크기 검사] ****
ok: [dbts94] =>
    msg: bin/oracle 421MB — 링크 정상
```

| 선택 | 왜 · 다르게 하면 |
|---|---|
| 종료 코드 6을 성공으로 | `-ignorePrereqFailure`로 사전 점검 경고를 넘기면 runInstaller가 6을 돌려준다. 0만 성공으로 보면 정상 설치를 실패로 판정한다(Oracle 공식 vagrant-projects도 같은 처리) |
| `CV_ASSUME_DISTID=OEL7.8` | 19.3 설치 프로그램이 OL8을 몰라 멈추는 것을 막는다. 실제 OS는 바뀌지 않는다 |
| `bin/oracle` > 100MB 검사 | v1(Rocky 9)에서 링크가 조용히 실패해 0바이트였던 파일. 설치 '성공' 메시지만 믿지 않는다 |
| root 스크립트를 Ansible이 | VM에는 root 비밀번호가 없어 설치 프로그램의 자동 실행이 실패(`INS-32128`, v1). root 권한인 Ansible이 직접 실행 |

---

### 40. 리스너

**목표**: 리스너 설정 파일 3개를 템플릿으로 만들고 리스너를 띄운다.

📄 `templates/listener.ora.j2`
```text
LISTENER =
  (DESCRIPTION_LIST =
    (DESCRIPTION =
      (ADDRESS = (PROTOCOL = TCP)(HOST = 0.0.0.0)(PORT = 1521))
      (ADDRESS = (PROTOCOL = IPC)(KEY = EXTPROC1521))))
```

| 선택 | 왜 · 다르게 하면 |
|---|---|
| `HOST = 0.0.0.0` | 모든 인터페이스에서 받는다 — PC(Host-Only) · VM 내부(localhost) 둘 다 |
| DBCA 전에 리스너 | DB가 만들어지자마자 LREG가 서비스(`orcl` · `pdb`)를 등록할 수 있다 |

---

### 50. DB 생성 — DBCA

**목표**: CDB `orcl` + PDB `pdb`를 ASMM으로 만들고, 정말 ASMM인지 확인한다.

📄 `tasks/50_dbca.yml`
```yaml
# v1 문제 M1: "-memoryMgmtType ASMM"은 없는 값이라 AMM으로 만들어졌다
dbca -silent -createDatabase
  -templateName General_Purpose.dbc
  -gdbname {{ oracle_sid }} -sid {{ oracle_sid }}
  -characterSet AL32UTF8 -nationalCharacterSet AL16UTF16
  -createAsContainerDatabase true -numberOfPDBs 1 -pdbName {{ pdb_name }}
  -memoryMgmtType AUTO_SGA -totalMemory {{ total_memory_mb }}     # 1536
  -storageType FS -datafileDestination /oradata
  -emConfiguration NONE -ignorePreReqs
# 생성 직후: PDB SAVE STATE · local_listener · memory_target=0 assert
```

| 선택 | 왜 · 다르게 하면 |
|---|---|
| `AUTO_SGA` | DBCA가 받는 값은 `AUTO`(=AMM) · `AUTO_SGA`(=ASMM) · `CUSTOM_SGA`. v1의 `ASMM`은 없는 값이라 무시되고 4GB 이하 VM에서는 AMM으로 만들어졌다 — HugePages가 첫 실행에서 항상 실패한 진짜 원인 |
| `-totalMemory 1536` | v1은 `-memoryPercentage 25` — VM이 켜진 시간 · 여유 메모리에 따라 SGA가 매번 달라졌다. 고정값이면 HugePages 계산도 매번 같다(1152MB → 592장) |
| 생성 직후 `memory_target=0` 검사 | DBCA 옵션이 의도대로 먹었는지 결과로 확인. 아니면 HugePages 단계에 가기 전에 멈춘다 |
| `SAVE STATE` | CDB를 재시작해도 PDB가 MOUNTED로 남지 않게(ORA-01109, v1) |

---

### 55. ARCHIVELOG

**목표**: 리두 로그를 `/backup/arch`에 보관하는 모드로 바꾼다.

📄 `tasks/55_archivelog.yml`
```sql
alter system set log_archive_dest_1='LOCATION=/backup/arch' scope=spfile;
shutdown immediate
startup mount
alter database archivelog;
alter database open;
alter pluggable database all open;
alter system switch logfile;          -- 아카이브 파일이 실제로 생기는지
```

| 선택 | 왜 · 다르게 하면 |
|---|---|
| 현재 모드를 먼저 조회 | 이미 ARCHIVELOG면 건너뛴다 — DB를 불필요하게 재시작하지 않는다 |
| MOUNT에서 변경 | 로그 모드는 컨트롤 파일에 기록되고 DB가 OPEN이면 바꿀 수 없다 |

---

### 60. 자동 기동 — oratab + systemd

**목표**: VM이 켜지면 리스너 · DB · PDB가 저절로 올라오게 한다.

📄 `templates/oracle-db.service.j2`
```ini
[Service]
Type=oneshot
RemainAfterExit=yes
User=oracle
Group=oinstall
# SELinux(enforcing)에서 systemd(init_t)는 /u01의 파일을 직접 실행하지 못한다 → 셸을 거친다
ExecStart=/bin/bash -c '{{ oracle_home }}/bin/dbstart {{ oracle_home }}'
ExecStop=/bin/bash -c '{{ oracle_home }}/bin/dbshut {{ oracle_home }}'
# systemd 프로세스에는 /etc/security/limits.d가 적용되지 않는다 → HugePages용 memlock
LimitMEMLOCK=infinity
LimitNOFILE=65536
```

| 선택 | 왜 · 다르게 하면 |
|---|---|
| `dbstart $ORACLE_HOME` | `/etc/oratab`에서 `Y`인 DB와 그 홈의 리스너를 함께 올린다 |
| `Type=oneshot` + `RemainAfterExit` | `dbstart`는 띄우고 끝나는 스크립트. 끝난 뒤에도 서비스를 '실행 중'으로 보고 종료 때 `dbshut`을 부른다 |
| `LimitMEMLOCK=infinity` | 빠뜨리면 손으로는 잘 뜨다가 **재부팅 뒤에만** `use_large_pages=ONLY` 기동이 실패한다. 재부팅 테스트가 필요한 이유 |
| `/bin/bash -c` | D 파트 — 1차 실행에서 실제로 막힌 곳 |

---

### 70. HugePages — 순서가 전부

**목표**: SGA를 2MB 고정 페이지에 올린다. v1은 순서가 뒤집혀 있었다.

> [이미지 자리: 그림 — 왼쪽부터 순서대로 — ①에서 AMM이면 50단계에서 이미 멈춘다]

📄 `tasks/70_hugepages.yml`
```yaml
hp_pages: "{{ ((sga_max_size | int) / 2097152) | round(0, 'ceil') | int + 16 }}"
# 1152MB → 576 + 16 = 592
- copy:
    dest: /etc/sysctl.d/99-oracle-hugepages.conf
    content: |
      vm.nr_hugepages = {{ hp_pages }}
      vm.hugetlb_shm_group = 54321        # oinstall — 없으면 ORA-27125
- assert:   # 예약된 수 >= 필요한 수, 아니면 '재부팅 후 다시' 안내
- assert:   # 기동 후 HugePages_Free < Total (실제로 쓰는지)
```

🖥 **실행 결과 (2026-10-28)** (실제 출력)
```text
TASK [HugePages 사용 판정] ****
ok: [dbts94] =>
    msg: HugePages Total/Free = 592 21 — 사용 중
```

| 선택 | 왜 · 다르게 하면 |
|---|---|
| 실제 SGA 값으로 계산 | v1은 `730`을 하드코딩. SGA가 바뀌면 모자라거나 남는다 |
| DB를 멈춘 뒤 예약 | DB가 메모리를 잡고 있으면 연속된 2MB 페이지가 부족하다. 정지 → 캐시 비우기 → 메모리 압축 → 예약 순 |
| `use_large_pages=ONLY` | HugePages를 못 잡으면 기동 자체를 거부 — '조용히 4KB 페이지로 돌아가는' 실패를 없앤다(교재 91p) |

---

### 90. 점검

**목표**: 설치가 끝났다는 것을 스크립트로 증명하고 결과를 PC에 남긴다.

📄 `tasks/90_verify.yml`
```yaml
- ansible.builtin.shell: |
    f=/vagrant/logs/verify_$(date +%Y%m%d_%H%M%S).txt
    bash /vagrant/scripts/check.sh | tee "$f"      # FAIL이 하나라도 있으면 실패로 끝남
```

점검 항목과 실제 결과는 C 파트.

---

## C. 검증 — 무엇을 어떻게 증명했나

*점검 스크립트 · 세 번의 실행 · 외부 접속*

### C1. 검증 설계 — '됐다'의 기준

설치 프로그램의 '성공' 메시지는 증거가 아니다. v1에서는 성공 메시지 뒤에 0바이트 실행 파일, AMM으로 만들어진 DB, 재부팅하면 안 뜨는 리스너가 숨어 있었다. 그래서 **결과 상태를 직접 검사하는 스크립트**(`check.sh`)를 만들고, 같은 스크립트를 세 시점에 돌렸다.

| 시점 | 무엇을 증명하나 |
|---|---|
| ① 설치 직후 | 플레이북이 의도한 상태를 만들었다 |
| ② 재부팅 후 (`vagrant reload`) | 손으로 띄울 때는 안 보이는 설정 — 부팅 때 HugePages 예약, systemd 기동, memlock 한도, PDB 자동 OPEN — 이 실제로 동작한다 |
| ③ VM 삭제 후 재생성 | 수정 없이 **처음부터 한 번에** 된다 = 다른 PC · 다른 사람도 재현할 수 있다 |

| 구역 | 항목 (17개, 방화벽이 꺼진 VM은 16개) |
|---|---|
| 디스크 · OS | `/u01` · `/oradata` · `/backup` 마운트 · THP 꺼짐 · `hugetlb_shm_group` · /etc/hosts |
| 소프트웨어 | `bin/oracle` 크기 · 패치 목록(정보) |
| 서비스 | `oracle-db` 등록 · 실행 · 리스너에 `pdb` 서비스 |
| DB | 인스턴스 OPEN · PDB READ WRITE · ARCHIVELOG · `memory_target=0` |
| HugePages · 접속 | Free < Total · 1521 대기 · 방화벽 1521 허용(firewalld가 켜진 경우) |

---

### C2. 실제 결과 — 재생성 후 점검

🖥 **vagrant up 마지막 단계 출력 (2026-10-28 15:33, VM 삭제 후 재생성)** (실제 출력)
```text
== Oracle 19c 점검 2026-10-28 15:33:12 · dbts94.localdomain ==
-- 환경
  OS     : Oracle Linux Server release 8.10
  커널   : 5.15.0-320.202.8.5.el8uek.x86_64
  가동   : up 28 minutes
-- 1. 디스크
  [PASS] /u01 마운트 (50G)
  [PASS] /oradata 마운트 (60G)
  [PASS] /backup 마운트 (70G)
-- 2. OS 설정
  [PASS] THP 꺼짐
  [PASS] vm.hugetlb_shm_group=54321
  [PASS] /etc/hosts 서비스 IP 매핑
-- 3. 소프트웨어
  [PASS] bin/oracle 420MB
  패치   : 29585399;OCW RELEASE UPDATE 19.3.0.0.0 · 29517242;Database Release Update : 19.3.0.0.190416
-- 4. 서비스 · 리스너
  [PASS] oracle-db 서비스 자동 기동 등록
  [PASS] oracle-db 서비스 실행 중
  [PASS] 리스너에 pdb 서비스 등록
-- 5. 데이터베이스
  [PASS] 인스턴스 orcl OPEN
  버전   : 19.3.0.0.0
  [PASS] PDB READ WRITE
  [PASS] ARCHIVELOG 모드 → /backup/arch
  [PASS] memory_target=0 (ASMM)
  SGA    : 1152MB
-- 6. HugePages
  [PASS] HugePages 사용 중 (Total 592 / Free 20, use_large_pages=ONLY)
-- 7. 외부 접속 준비
  [PASS] 1521 포트 대기 중
== 결과: PASS 16 / FAIL 0 ==
```

🖥 **PLAY RECAP** (실제 출력)
```text
dbts94   : ok=50   changed=22   unreachable=0   failed=0   skipped=3
걸린 시간: 00:28:55
```

| # | 실행 | 결과 | 메모 |
|---|---|---|---|
| 1 | 1차 `vagrant up` (v2) | △ | 00~55단계 한 번에 통과(VM 부팅 후 약 25분) · 60단계에서 SELinux로 실패 → D 파트 |
| 2 | v2.1 수정 후 `autostart,hugepages,verify`만 | ✅ | PASS 16 / FAIL 0 · `SELinux Enforcing · oracle-db active` |
| 3 | `vagrant reload` 후 점검 | ✅ | PASS 16 / FAIL 0 · HugePages 592 / 20 · 자동 기동 |
| 4 | PC DBeaver → PDB | ✅ | Connected (1000 ms) — 아래 화면 |
| 5 | `vagrant destroy` → `vagrant up` | ✅ | **28분 55초 · failed=0** · 1차와 같은 값 |

---

### C3. 외부 접속 — DBeaver

> [이미지 자리: 실제 화면 — PC의 DBeaver에서 192.168.10.94:1521, Service Name pdb, system으로 연결 테스트 — 실제 화면(2026-10-28)]

| 선택 | 왜 · 다르게 하면 |
|---|---|
| Service Name `pdb` | CDB 구조에서는 SID(`orcl`)로 접속하면 CDB$ROOT로 들어간다. 업무 데이터가 있는 PDB는 서비스 이름으로 접속 |
| 이 화면이 증명하는 것 | 리스너가 루프백이 아닌 서비스 IP에서 받고(/etc/hosts · `HOST=0.0.0.0`), PDB가 열려 있고, 리스너에 서비스가 등록돼 있다 |

---

### C4. 다른 PC에서 — 사전 점검과 검증 범위

C1~C3은 **한 대의 PC**에서 두 번 새로 만들어 얻은 결과다. 이것은 '이 PC에서는 언제 다시 해도 같다'는 증거이지 '어느 PC에서나 된다'는 증거는 아니다. 그래서 다른 PC가 갖춰야 할 조건을 `vagrant up` **전에** 검사하는 스크립트를 따로 두었다.

📄 `실행 (PowerShell, D:\vagrant\oracle19c)`
```powershell
powershell -ExecutionPolicy Bypass -File scripts\check-host.ps1
```

| 검사 | FAIL이면 | 기준 |
|---|---|---|
| VirtualBox · Vagrant | 설치 · 버전 확인 | 검증 버전 7.2.14 · 2.4.9 (7.0 · 2.4 미만은 WARN) |
| 메모리 | VM 메모리 줄이기 | 12GB 이상 PASS · 8GB 이상 WARN |
| CPU 가상화 · Hyper-V | BIOS에서 VT-x/SVM 켜기 · Hyper-V 켜짐은 WARN | VirtualBox가 느린 방식으로 돌면 VM이 멈출 수 있음 |
| 디스크 여유 | 공간 확보 | 40GB 이상 |
| 설치 zip | 다시 받기 | 크기 3,059,705,302 · SHA256 일치 |
| 192.168.10.x 충돌 | Vagrantfile `VM_IP` 변경 | VirtualBox 어댑터 외의 실제 네트워크가 같은 대역이면 FAIL |
| 인터넷 | 학원 · 회사망 방화벽 · 프록시 확인 | `oracle.github.io` · `yum.oracle.com` |
| 남은 VM · 디스크 | `vagrant destroy` · `disks\*.vdi` 삭제 | 옛 디스크가 새 VM에 붙는 것 방지 |

> **ℹ️ 참고** — 스크립트는 Windows PowerShell 5.1에서 한글이 깨지지 않도록 UTF-8(BOM)으로 저장했다. 이 문서 작성 시점에는 문법 검사와 가짜 환경 실행으로 동작을 확인했고, 실제 PC 실행 결과는 README §9 7번 줄에 남긴다.

---

## D. 트러블슈팅 사례

*실제로 막힌 것 — 증상 · 진단 · 원인 · 해결 · 왜*

### D1. SELinux가 systemd의 dbstart 실행을 막다 (1차 실행, 실측)

**증상** — 플레이북 60단계에서 DB를 정상 종료한 뒤 `systemctl start oracle-db`가 실패. DB를 띄우다 실패한 게 아니라, 로그 파일(`startup.log`)조차 생기지 않았다.

🖥 **systemctl status oracle-db** (실제 출력)
```text
Active: failed (Result: exit-code)
Process: 37749 ExecStart=/u01/app/oracle/product/19.0.0.0/dbhome_1/bin/dbstart … (code=exited, status=203/EXEC)
oracle-db.service: Failed to execute command: Permission denied
oracle-db.service: Failed at step EXEC spawning …/bin/dbstart: Permission denied
```

**진단** — `203/EXEC`는 '프로그램을 실행조차 못 했다'는 뜻이다. 파일 권한은 `oracle:oinstall 750`이고 서비스도 `User=oracle`이라 일반 권한 문제가 아니다. 그러면 남는 것은 SELinux다. 상태 · 라벨 · 거부 기록을 한 번에 본다.

🖥 **getenforce · ls -Z · ausearch -m avc** (실제 출력)
```text
Enforcing
unconfined_u:object_r:unlabeled_t:s0 /u01/app/oracle/product/19.0.0.0/dbhome_1/bin/dbstart
type=AVC msg=audit(1793153862.416:1924): avc:  denied  { execute } for  pid=37749 comm="(dbstart)"
  name="dbstart" dev="dm-2" scontext=system_u:system_r:init_t:s0
  tcontext=unconfined_u:object_r:unlabeled_t:s0 tclass=file permissive=0
```

> [이미지 자리: 그림 — systemd(init_t)는 라벨 없는(unlabeled_t) 파일을 서비스로 실행할 수 없다 → 라벨을 붙이고, 시스템 셸(bin_t)을 거쳐 실행]

|  | 내용 |
|---|---|
| 원인 | Oracle Linux 8 박스는 SELinux가 `Enforcing`. 새로 만든 xfs(`/u01`)에는 SELinux 라벨이 없어(`unlabeled_t`) systemd(`init_t`)가 그 파일을 서비스 명령으로 실행하는 것이 정책상 거부됐다 |
| 해결 ① | 디스크를 마운트한 직후 `restorecon -R`로 정책 기본 라벨을 붙인다(`setup_disk.sh` · 60단계 정리 작업) |
| 해결 ② | `ExecStart=/bin/bash -c '…/dbstart …'` — 시스템 셸(`bin_t`)을 거치면 서비스가 정상 도메인으로 전환되어 실행된다 |
| SELinux는 | **끄지 않았다.** `setenforce 0`이 가장 빠르지만 보안 장치를 끄는 것은 해결이 아니라 회피다 |
| 확인 | 수정 후 `SELinux Enforcing · oracle-db active` → 재부팅 · 재생성에서도 통과 |

**💬 질문 대비**

- **Q. Permission denied인데 왜 chmod를 안 했나?** — `203/EXEC`와 함께 권한(750)과 실행 계정(oracle)이 이미 맞았다. 일반 권한이 맞는데도 거부되면 다음 계층인 SELinux를 본다. `ausearch -m avc`에서 `denied { execute }`와 `scontext=init_t`, `tcontext=unlabeled_t`를 확인해 원인을 확정했다.

---

### D2. HugePages가 처음엔 항상 실패하던 이유 (v1 → 검증 보고서)

|  | 내용 |
|---|---|
| 증상 | v1 자동화에서 HugePages 단계가 첫 실행에 `ORA-27138`으로 실패, 같은 명령을 한 번 더 돌리면 통과. 문서에도 '한 번 더 실행'이라고 적혀 있었다 |
| 진단 | SGA가 `ipcs -m`이 아니라 `/dev/shm`에 있었고 `memory_target`이 설정돼 있었다 — AMM의 특징. DBCA 명령의 `-memoryMgmtType ASMM`을 Oracle 문서와 대조하니 **허용값이 아니었다**(`AUTO` · `AUTO_SGA` · `CUSTOM_SGA`) |
| 원인 | 없는 값이 무시되어 AMM으로 생성 → HugePages와 양립 불가 → 정상 경로가 반드시 실패하고 '복구 경로'에서야 성공 |
| 해결 | `AUTO_SGA` + `-totalMemory` 고정 + 생성 직후 `memory_target=0` 검사 → v2에서 HugePages가 첫 실행에 통과 |
| 교훈 | '두 번 돌리면 된다'는 해결이 아니라 증상이다. 재실행으로 넘어가는 단계는 원인이 숨어 있다는 신호 |

---

### D3. 그 밖에 미리 막아 둔 것 (v1에서 실제로 겪은 것)

| v1 증상 | 원인 | v2에서 |
|---|---|---|
| DBCA `No valid IP Address returned for the host` | /etc/hosts에 호스트 이름 없음 · 루프백에 붙음 | 10단계 hosts 정리 |
| `connected to an idle instance` · `ORA-01078` | `ORACLE_SID` 대문자, 파일은 소문자 | `vars.yml` SID 소문자 고정 |
| 재부팅 후 `ORA-12541` · `ORA-01109` | 자동 기동 없음 · PDB 상태 미저장 | 60단계 · 50단계 SAVE STATE |
| `ORA-27125` | `vm.hugetlb_shm_group` 없음 | 70단계 sysctl 파일에 함께 |
| `lvcreate` 공간 부족 | 정확한 크기 요청 + PV 메타데이터 | `-l 100%FREE` |
| `bin/oracle` 0바이트 | 비인증 OS(Rocky 9) 링크 실패 | OL8 + 크기 assert |

---

## E. 질문 대비

*면접 · 멘토가 물을 만한 것*

### E. 예상 질문과 답

**💬 질문 대비**

- **Q. 왜 자동화했나? 한 번 설치하면 끝 아닌가?** — 설치는 한 번이 아니었다. 실습 VM을 몇 번씩 다시 만들었고, 그때마다 같은 곳에서 막혔다. 자동화하면 설치 절차가 코드로 남아 '어떻게 설치했는지'가 문서가 되고, 같은 결과를 29분 만에 다시 만들 수 있다. 실무에서도 개발 · 검증 · 운영 서버를 같은 구성으로 맞추는 일이 많다.
- **Q. Ansible을 왜 VM 안에서 돌렸나?** — Windows에는 Ansible이 없다. v1은 WSL에서 원격 실행했는데, WSL 네트워크 모드 · 키 경로 · 인벤토리가 PC마다 달라 재현이 안 됐다. VM 안에서 돌리면 필요한 것이 VirtualBox와 Vagrant 두 개로 줄어든다.
- **Q. 멱등성을 어떻게 지켰나?** — `creates:`(그 파일이 있으면 건너뜀), 상태 조회 후 조건 실행(예: ARCHIVELOG면 건너뜀), Ansible 모듈(lineinfile · template) 사용. 그래서 SELinux 문제를 고친 뒤 끝난 단계는 건너뛰고 남은 3단계만 다시 돌릴 수 있었다.
- **Q. AMM과 ASMM 차이, 왜 ASMM인가?** — AMM은 `memory_target` 하나로 SGA와 PGA를 함께 자동 조정하고 `/dev/shm`을 쓴다. ASMM은 `sga_target`으로 SGA 안의 풀만 자동 조정한다. HugePages는 System V 공유 메모리에만 쓸 수 있어 AMM과 같이 못 쓴다. 메모리가 큰 운영 DB는 ASMM + HugePages가 일반적이다.
- **Q. HugePages를 쓰면 무엇이 좋은가?** — 4KB 페이지로 1.1GB SGA를 매핑하면 페이지 표 항목이 수십만 개이고 서버 프로세스마다 따로 가진다. 2MB 페이지면 수백 개로 줄어 메모리와 CPU(TLB 미스)를 아끼고, 스왑되지 않는다. `use_large_pages=ONLY`로 못 잡으면 기동을 거부하게 해 조용한 성능 저하를 막았다.
- **Q. SELinux를 왜 안 껐나?** — 끄면 가장 빠르지만 보안 장치를 끈 서버를 만드는 것이다. `ausearch`로 무엇이 무엇을 막았는지 확인하고, 라벨을 정상화하고 실행 경로를 바꿔 SELinux를 켠 채로 해결했다.
- **Q. 재부팅 테스트를 왜 따로 했나?** — 자동 기동 · HugePages 부팅 예약 · systemd의 memlock 한도 · PDB 자동 OPEN은 손으로 한 번 띄울 때는 드러나지 않는다. 실제로 `LimitMEMLOCK`이 없으면 재부팅 뒤에만 기동이 실패한다.
- **Q. 19.3으로 설치한 것의 한계는?** — OL 8.10의 기본 커널(UEK7)에서 Oracle이 지원하는 것은 19.21 이상이라 19.3 그대로는 '설치는 되지만 비지원' 조합이다. 플레이북은 RU zip(19.25)이 있으면 설치하면서 `-applyRU`로 적용하도록 이미 만들어 두었고, 파일만 있으면 같은 명령으로 지원 조합이 된다.
- **Q. 어느 PC에서나 되나?** — 한 대의 PC에서 두 번 새로 만들어 같은 결과를 얻었다 — 거기까지가 증명된 범위다. 다른 PC에서 필요한 조건(가상화 · 메모리 · 디스크 · 네트워크 대역 · 인터넷 · 설치 파일)은 사전 점검 스크립트로 먼저 확인하게 했고, 박스 버전을 고정해 시간이 지나도 같은 OS로 설치되게 했다. 다른 PC에서 실제로 성공하면 그 기록을 추가한다.
- **Q. 운영에 그대로 쓸 수 있나?** — 아니다. 실습용 비밀번호가 `vars.yml`에 평문으로 있고(운영이면 ansible-vault), 백업(RMAN) · 모니터링 · 보안 패치 정책이 없다. 대신 OS 준비 · 설치 · 운영 기본 설정의 순서와 검증 방식은 그대로 확장할 수 있다.

---

## F. 부록

*명령 모음 · 바꿀 수 있는 값 · 한계와 다음 단계*

### F1. 명령 모음 (PowerShell, D:\vagrant\oracle19c)

| 하고 싶은 것 | 명령 |
|---|---|
| 사전 점검 (다른 PC에서 처음) | `powershell -ExecutionPolicy Bypass -File scripts\check-host.ps1` |
| 처음부터 설치 | `vagrant up` |
| 진행 상황 보기 (다른 창) | `Get-Content logs\ansible.log -Wait -Tail 20` |
| 끝난 단계는 건너뛰고 다시 | `vagrant provision --provision-with oracle` |
| 일부 단계만 | `$env:ORA_TAGS="hugepages,verify"; vagrant provision --provision-with oracle; Remove-Item Env:ORA_TAGS` |
| 점검 | `vagrant ssh -c "sudo bash /vagrant/scripts/check.sh"` |
| 점검 결과를 파일로 | `vagrant ssh -c "sudo bash /vagrant/scripts/check.sh > /vagrant/logs/check.txt"` |
| 재부팅 테스트 | `vagrant reload` → 점검 |
| 끄기 / 켜기 | `vagrant halt` / `vagrant up` |
| 완전히 지우기 | `vagrant destroy -f; Remove-Item disks\*.vdi` |

---

### F2. 바꿀 수 있는 값

| 어디 | 값 | 기본 |
|---|---|---|
| Vagrantfile | `VM_NAME` · `VM_IP` · `VM_MEMORY` · `VM_CPUS` · `DISKS` | dbts94 · 192.168.10.94 · 4096 · 2 · 50/60/70 |
| vars.yml | `oracle_sid` · `pdb_name` · `db_charset` | orcl · pdb · AL32UTF8 |
| vars.yml | `total_memory_mb` (VM 메모리를 줄이면 함께) | 1536 |
| vars.yml | `db_password` (실습용) | <비밀번호> |
| vars.yml | `ru_zip` · `ru_patch_id` · `opatch_zip` | 19.25 RU · 36912597 |

---

### F3. 한계와 다음 단계

| 한계 | 다음 단계 |
|---|---|
| 검증한 PC가 한 대 | 다른 PC(학원 · 팀원)에서 사전 점검 + `vagrant up` → README §9 7번 |
| 19.3 — OL 8.10 + UEK7에서 비지원 조합 | RU 19.25 zip을 `media`에 넣고 재생성 → 지원 조합 검증 |
| 비밀번호 평문 | ansible-vault로 암호화 |
| 백업 없음 | RMAN 백업 · 복구 훈련 단계를 플레이북에 추가 (`/backup/rman` 자리는 만들어 둠) |
| 단일 서버 | Data Guard 스탠바이 VM 추가 |
| Guest Additions 7.1 ↔ VirtualBox 7.2 경고 | 현재 공유 폴더 정상. 문제 생기면 박스 갱신을 기다리거나 vbguest 플러그인 |

관련 문서: README(실행 순서) · 수동 설치 가이드 dbts93(같은 설치를 손으로, 교재 2장 순서) · 검증 보고서 22번(v1 문제 목록) · 05번 트러블슈팅.

---
