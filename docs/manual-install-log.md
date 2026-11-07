# Oracle 19c 수동 설치 실행 기록: dbts93 (2026-10-29 ~ 30)

> 「Oracle19c_수동설치_가이드_dbts93」를 처음부터 끝까지 직접 실행한 기록입니다.
> 가이드에 적힌 기대값과 실제 결과를 나란히 적었습니다. 가이드와 달랐던 곳, 막혔던 곳, 해결한 방법이 함께 들어 있습니다.
> 시각은 대화 중 캡처와 로그에 남은 값입니다. 추정은 **(추정)**으로 표시했습니다.

---

## 1. 결과 요약

| 항목 | 값 |
|---|---|
| 최종 판정 | ✅ **재부팅 후 check.sh PASS 17 / FAIL 0** (2026-10-30 21:19 · 21:21) |
| 설치 직후 점검 | PASS 16 / FAIL 1 (21:11) → 수정 후 **PASS 17 / FAIL 0** (21:1x) |
| VM | `dbts93` · 4096MB · 2 CPU · `D:\VirtualBoxVMs\dbts93` |
| 디스크 | OS 50G (sda) · u01 50G (sdb) · oradata 100G (sdc) · backup 100G (sdd) |
| 네트워크 | 어댑터 1 Host-Only #2 → `enp0s3 192.168.10.93/24` · 어댑터 2 NAT → `enp0s8 10.0.3.15/24` |
| OS | **Oracle Linux 8.10** (`D:\ISO\OEL8_10.iso`) · UEK7 `5.15.0-206.153.7.1.el8uek` · 가이드 기준은 8.8 |
| Oracle | 19c EE **19.3 base** (RU 19.25 zip 없음 → E 파트 생략) |
| DB | CDB `orcl` + PDB `pdb` · KO16MSWIN949 / AL16UTF16 · ASMM SGA 1152M / PGA 384M |
| 운영 설정 | ARCHIVELOG → `/backup/arch` · HugePages 579 (`use_large_pages=ONLY`) · systemd `oracle-db` 자동 기동 |
| 외부 접속 | PC DBeaver → `192.168.10.93:1521` Service Name `pdb` · system ✅ |
| 걸린 시간 | 2026-10-29 21:00경 시작 → 2026-10-30 21:21 완료(중간에 여러 번 쉼). 실제 작업은 대략 **6~7시간 (추정)** |

---

## 2. 단계별 기록 (가이드 기대값 ↔ 실제)

| 단계 | 가이드 기대값 | 실제 결과 | 판정 | 시각 |
|---|---|---|---|---|
| 1~4 VirtualBox | Host-Only #2 192.168.10.1/24 DHCP 끔 · VM · 디스크 4개 · ISO | 기대값과 같음 (OEL8_10.iso 13.18GB) | ✅ | 10-29 |
| 5 부팅 | Install Oracle Linux **8.8.0** | **8.10.0** 메뉴 | ✅ (ISO 차이) | 10-29 21:00 |
| 6 설치 요약 | Asia/Seoul · Server · sda만 · KDUMP 끔 · root 비밀번호 | 처음 화면에서 KDUMP가 켜져 있었음 → 끔 | ✅ | 10-30 01:21 |
| 7 네트워크 | enp0s3 .93/24 게이트웨이 없음 · enp0s8 DHCP · 둘 다 ON | 설치 화면에서는 둘 다 Connected | ⚠️ 문제 ① | — |
| 9 첫 로그인 | `dbts93` · 10.0.**2**.15 · default via 10.0.**2**.2 | **enp0s8에 IP 없음, default 경로 없음** → 고친 뒤 10.0.**3**.15 / 10.0.**3**.2 | ⚠️ 문제 ①② | 01:34 → 08:55 |
| 9 MobaXterm | root 접속 | 접속 OK · X11 ✘ (xauth 설치 전이라 정상) | ✅ | 09:10 |
| 10 저장소 | repolist | (확인 생략) → 11단계 dnf 성공으로 대체 | ✅ | — |
| 11 preinstall | `uid=54321(oracle)…` · `fs.file-max = 6815744` | 같음 · `kernel.shmmax = 4398046511104`(OL8 기본값) | ✅ | 09:23 |
| 12 /etc/hosts | `192.168.10.93 dbts93.localdomain dbts93` | 같음 | ✅ | 09:25경 |
| 13~14 THP · SELinux · 방화벽 · 재부팅 | `disabled` · `[never]` · `1521/tcp` | 같음 · 재접속 후 **X11 ✔** | ✅ | 09:27 |
| 15 LVM | 50G · 100G · 100G 마운트 | 같음 · `mount -a` 후 `daemon-reload` 안내 메시지 | ✅ | 09:28 |
| 16 계정 · 디렉터리 · 프로필 | oracle 비밀번호 · 디렉터리 소유권 · oracle 프로필 | **mkdir/chown 줄이 실행 안 됨 · 프로필이 root에 들어감** → 되돌리고 다시 함 | ⚠️ 문제 ③④ | 09:29 → 09:55 |
| 17 업로드 · 압축 해제 | 크기 3059705302 · SHA256 일치 · runInstaller | 같음 (업로드 완료 전에 명령을 쳐서 한 번 `No such file`, unzip 두 번 실행) | ✅ 문제 ⑤ | 09:56 → 13:20 |
| 18 X11 | `DISPLAY` · xterm 창 | `localhost:11.0` · xterm 뜸 | ✅ | 16:20경 |
| 19 runInstaller | Software Only · EE · 화면 10개 | Summary 값 모두 맞음 · root 스크립트 자동 실행 OK | ✅ | 16:22 |
| 20 엔진 확인 | bin/oracle 수백 MB · 0바이트 파일 없음 · 19.3 RU · oraInst.loc | 420MB · **0바이트 4개** (`oklist0` 등) · 19.3 · OK | ✅ 문제 ⑥ | 16:23 |
| 23 DBCA | orcl / pdb · `/oradata/{DB_UNIQUE_NAME}` · ASMM 1152/384 · KO16MSWIN949 | Memory 기본값이 **AMM**이었음 → ASMM으로 바꿈. Summary에서 **저장 위치가 기본값**, **이름이 `orcl.localdomain`** → Back으로 고침 | ⚠️ 문제 ⑦ | 16:30 → 17:14 |
| 23 DBCA 진행 | 20~40분 후 완료 | 실제 생성은 17:23~17:41에 끝남. **화면은 8%에서 멈춤** → 로그로 완료 확인 후 창 닫음 | ⚠️ 문제 ⑧ | 17:14 → 19:07 |
| 24 DB 확인 | spfileorcl · OPEN · CDB YES · PDB RW · memory_target 0 · sga 1152M | 같음 · `save state` 완료 | ✅ | 19:09 |
| 25 리스너 · tnsnames · 접속 | VM 안 `CON_NAME = PDB` · DBeaver 연결 | **ORA-01017** (system 비밀번호 다름) → 재설정 후 `PDB` · DBeaver OK | ⚠️ 문제 ⑨ | 19:10 → 19:26 |
| 26 ARCHIVELOG | Archive Mode · `/backup/arch` · 아카이브 파일 | 같음 · `1_7_1248024313.dbf` | ✅ | 19:34 |
| (사고) PC 종료 | — | 20:3x PC가 갑자기 꺼짐 → VM을 다시 켜고 DB를 직접 기동, 손실 없음 | ⚠️ 문제 ⑩ | 20:38 → 20:45 |
| 27 HugePages | nr_hugepages 58x · Free < Total | **579** · 기동 후 Free **7** | ✅ | 21:00 |
| 28 자동 기동 | oratab `:Y` · `active (exited)` · HugePages 유지 | 같음 (`systemctl start`를 oracle 탭에서 실행해 root 비밀번호를 물음) | ✅ | 21:07 |
| 29 check.sh | PASS 17 / FAIL 0 | **PASS 16 / FAIL 1** `리스너에 pdb 서비스 없음` → 고친 뒤 PASS 17 | ⚠️ 문제 ⑪ | 21:11 → 21:16 |
| 30 재부팅 테스트 | 같은 PASS 수 · FAIL 0 | **PASS 17 / FAIL 0** | ✅ | 21:19 · 21:21 |

---

## 3. 문제와 해결 (증상 → 원인 → 해결 → 이유)

### ① enp0s8(NAT)에 IP가 없음 · default 경로 없음 (9단계)
- **증상**
  - `ip -4 addr`에 enp0s3(192.168.10.93)만 있었습니다.
  - `ip route`에 `default` 줄이 없었습니다.
  - `nmcli con show`의 enp0s8 DEVICE가 `--`였습니다.
- **원인**: 설치 화면에서 스위치를 ON으로 켰는데도, enp0s8 연결이 `autoconnect=no`로 저장됐습니다. 설치 화면의 ON은 설치 중에만 적용된 것으로 보입니다 **(추정)**.
- **해결**
  ```
  nmcli con mod enp0s8 connection.autoconnect yes
  nmcli con mod enp0s8 ipv4.method auto
  nmcli con up enp0s8
  ```
- **이유**: `con up`만 하면 재부팅할 때 다시 꺼집니다. `autoconnect yes`가 있어야 30단계 재부팅 테스트를 통과합니다.
- **곁가지**: 처음에 한 줄 명령이 콘솔 폭 때문에 두 줄로 들어가 `ipv4.method: command not found`가 났습니다. 명령을 둘로 나눠 해결했습니다.

### ② NAT 대역이 10.0.2.x가 아니라 10.0.3.x (9단계)
- **증상**: `10.0.3.15/24` · `default via 10.0.3.2`
- **원인**: VirtualBox NAT는 어댑터 번호에 따라 대역이 정해집니다. 어댑터 1은 10.0.2.0/24, **어댑터 2는 10.0.3.0/24**입니다. 가이드의 기대값이 틀렸습니다.
- **해결**: 정상이므로 그대로 둡니다. 가이드 기대값을 `10.0.3.15` / `10.0.3.2`로 고쳤습니다.

### ③ `passwd oracle` 다음 줄이 실행되지 않음 (16단계)
- **증상**: 붙여넣은 블록 중 `mkdir` · `chown` · `chmod` 결과가 없었습니다.
- **원인**: `passwd`가 비밀번호 입력을 받는 동안, 함께 붙여넣은 줄이 입력값으로 들어갔습니다 **(추정)**.
- **해결**: 세 줄을 root에서 따로 다시 실행하고 `ls -ld`로 `oracle oinstall`을 확인했습니다.
- **다음부터**: `passwd oracle`은 **한 줄만 따로** 실행합니다.

### ④ oracle용 .bash_profile이 root에 들어감 (16단계)
- **증상**: root 탭 프롬프트가 `[orcl]root@dbts93:/root>`로 바뀌었습니다.
- **원인**: oracle 상자를 **root 탭**에 붙여넣었습니다.
- **해결**
  1. root 탭에서 `sed -i '/^export TZ=Asia\/Seoul$/,/^alias t_dbalert=/d' /root/.bash_profile`
  2. `exit` 후 재접속
  3. oracle 세션을 새로 만들어 그 탭에 다시 붙여넣기
- **다음부터**: 붙여넣기 전에 **탭 이름과 `#` / `$`**를 확인합니다.

### ⑤ 업로드 전에 명령 실행 · unzip 두 번 (17단계)
- **증상**
  - `/work/media`에서 `total 0` · `No such file`이 나왔습니다.
  - 나중에 `find`로 찾아보니 파일은 `/work/media`에 정상 크기로 있었습니다.
  - unzip이 `replace …?`를 물었습니다.
- **원인**
  - 업로드(09:56 완료)가 끝나기 전에 명령을 쳤습니다.
  - SFTP 창은 **Follow terminal folder** 때문에 터미널을 따라 움직입니다. 그래서 목록에 보이는 폴더를 다른 곳으로 착각했습니다.
- **해결**: SHA256이 일치하는 것을 확인했습니다. unzip은 `A`(All)로 덮어썼습니다. 결과는 6.5G입니다.

### ⑥ bin 아래 0바이트 파일 4개 (20단계)
- **증상**: `find … -size 0 ! -name tnnfg`에 `oklist0` · `okinit0` · `okdstry0` · `rawutl0`이 나왔습니다.
- **판단 (추정)**
  - 모두 이름이 `0`으로 끝납니다.
  - 재링크할 때 원래 파일을 옮겨 둔 백업으로 보입니다.
  - `0`이 없는 원래 파일(`oklist` 등)의 크기는 확인하지 못했습니다.
  - 이후 DB 생성, 기동, 재부팅 점검이 모두 정상이었습니다.
- **가이드 반영**: 검사 명령에 `! -name '*0'`을 추가했습니다.
- **내일 확인할 것**: `ls -l $ORACLE_HOME/bin/oklist $ORACLE_HOME/bin/okinit $ORACLE_HOME/bin/okdstry $ORACLE_HOME/bin/rawutl`

### ⑦ DBCA 기본값 함정 세 곳 (23단계)
| 화면 | 기본값 | 바꾼 값 | 이유 |
|---|---|---|---|
| 9 Memory | **AMM** 1563MB (기본 선택) | ASMM · SGA 1152 · PGA 384 | AMM이면 `memory_target`이 생겨 HugePages를 쓸 수 없음 |
| 5 Storage | `{ORACLE_BASE}/oradata/{DB_UNIQUE_NAME}` | `/oradata/{DB_UNIQUE_NAME}` | 기본값이면 데이터 파일이 50G `/u01`로 감 |
| 4 Identification | `orcl.localdomain` (자동으로 붙음) | `orcl` | `db_domain`이 생기면 서비스가 `pdb.localdomain`이 되어 tnsnames · DBeaver가 `ORA-12514` |

- **발견한 방법**: 13번 **Summary 화면**에서 `{ORACLE_BASE}`와 `db_domain: localdomain`을 보고 찾았습니다.
- **Back으로 돌아가는 방법**: 왼쪽 목록에서 Database Identification이 회색이라 클릭할 수 없었습니다. 아래쪽 **< Back** 버튼으로 돌아갔습니다.
- **가이드 반영**: `.localdomain` 경고를 추가했습니다. Summary에 `db_domain` 줄이 없어야 합니다.

### ⑧ DBCA 화면이 "Copying database files 8%"에서 1시간 넘게 멈춤 (23단계)
- **증상**: 진행률 8%, CPU 1%. Retry · Skip은 비활성이었습니다.
- **확인한 것** (창은 그대로 둔 채)
  - `/oradata/ORCL/pdbseed` 17:29 · `pdb` 17:40 생성
  - `ora_pmon_orcl` 17:40부터 실행 중
  - 로그 순서: `postScripts`(17:33) → `utlrp`(17:38) → `postDBCreation` · `plugDatabase1R` · `postPDBCreation`(17:40) → trace `completionPage`(17:41) → `Waiting for completion of background operations`
  - alert log: `Pluggable database PDB opened read write`
  - `show pdbs`: `PDB READ WRITE`
  - 리스너에 `orcl` · `pdb`, `/etc/oratab`에 `orcl:…:N`이 있음
  - 17:23에 시작한 `rman` 프로세스가 `S (sleeping)`, CPU 0초로 남아 있음
- **원인 (추정)**: DB 생성은 17:41에 끝났습니다. 그런데 파일 복사 단계의 RMAN이 종료되지 않아서, DBCA가 백그라운드 작업이 끝나기를 기다리며 화면을 넘기지 못했습니다.
- **해결**: 남은 RMAN을 정리하고 DBCA 창을 닫았습니다. 그 뒤 24단계 확인을 모두 통과했습니다.
- **배운 것**
  - trace의 `setting Ignorable Error: ORA-…` · `setting Fatal Error: ORA-…` 161줄은 **에러가 아닙니다.** "이 번호는 무시 / 치명 처리"라는 **목록 등록**입니다.
  - 실제 에러라면 `ORA-01034: ORACLE not available`처럼 번호 뒤에 메시지가 붙습니다.

### ⑨ `ORA-01017 invalid username/password` (25단계)
- **원인**: DBCA 11번에서 입력한 SYS/SYSTEM 비밀번호가 `<비밀번호>`와 달랐습니다.
- **해결**: OS 인증 `ss`로 들어가 비밀번호를 다시 정했습니다.
  ```
  alter user sys identified by <비밀번호> container=all;
  alter user system identified by <비밀번호> container=all;
  ```
- **이유**: SYS · SYSTEM은 common user라서, `container=all`로 하면 루트와 PDB에 같이 적용됩니다.
- **DBeaver 쪽**: Database 칸이 `ORCL`로 남아 있었고, Service Name을 고르지 않아 헷갈렸습니다. Host `192.168.10.93`, **Service Name** `pdb`, Password를 넣고 연결에 성공했습니다.

### ⑩ PC가 갑자기 꺼짐 (27단계 도중)
- **상황**: 20:3x에 PC가 꺼졌습니다. VM은 `전원 꺼짐` 상태였습니다. 스냅샷 `G-끝(DB생성)`은 남아 있었습니다.
- **판단**: 스냅샷으로 돌아가지 않고 그냥 켜기로 했습니다. 돌아가면 26단계 ARCHIVELOG 작업을 잃습니다.
- **복구**: 28단계 전이라 자동 기동이 없었으므로 직접 올렸습니다.
  - `lsnrctl start` → `startup` → `Database opened.`
  - PDB READ WRITE, Archive Mode 시퀀스 8로 꺼지기 전과 같았습니다.
- **추정**
  - `use_large_pages=ONLY`가 이미 들어가 있었고, `99-oracle-hugepages.conf`(579)도 있었습니다.
  - 그래서 27단계 ②의 `shutdown immediate` **뒤에** 꺼진 것으로 보입니다.
  - 즉 정상 종료된 상태였을 가능성이 큽니다. crash recovery 로그는 확인하지 못했습니다.
- **배운 것**: 부팅 때 sysctl.d 파일이 HugePages를 먼저 잡아 두어, `ONLY`로도 바로 기동됐습니다(Free 7).

### ⑪ check.sh FAIL `리스너에 pdb 서비스 없음` (29단계)
- **증상**: `lsnrctl status`에 정적 등록한 `orcl` 하나만 있었습니다. DB와 PDB는 정상이었습니다.
- **원인**
  1. DBCA는 `local_listener=LISTENER_ORCL`로 설정하고, 그 별칭을 tnsnames.ora에 적어 둡니다.
  2. 25단계 가이드가 `cat > tnsnames.ora`(**덮어쓰기**)라서 별칭이 지워졌습니다.
  3. DB를 재기동(PC 종료 → 직접 startup → systemd)하면서 LREG가 리스너를 찾지 못해 동적 등록에 실패했습니다.
  4. 19:10에는 덮어쓰기 **전에** 이미 등록돼 있어서 문제가 보이지 않았습니다.
- **해결**
  ```
  echo 'LISTENER_ORCL = (ADDRESS = (PROTOCOL = TCP)(HOST = dbts93.localdomain)(PORT = 1521))' >> tnsnames.ora
  ```
  SQL> 에서 실행합니다.
  ```
  alter system set local_listener='LISTENER_ORCL' scope=both;
  alter system register;
  ```
  → `Service "pdb"`가 다시 나오고, check.sh **PASS 17**
- **이유**
  - `alter system register`만으로는 반영되지 않았습니다.
  - DB는 `local_listener`를 **값이 설정될 때(기동 때) 한 번 풀어서** 기억합니다. 그래서 같은 값으로 다시 설정해야 고친 파일을 다시 읽습니다 **(추정, 실제 동작으로 확인)**.
- **가이드 반영**: 25단계를 `cat >>`(덧붙이기)로 바꾸고 경고를 추가했습니다. Z표에도 넣었습니다.

---

## 4. 가이드에 반영한 수정 (가이드 원본 파일 기준)

| 위치 | 바꾼 내용 | 근거 |
|---|---|---|
| 앞부분 · 표지 | 기준일 2026-10-30, 8.8 · 8.10 표기, "이 순서로 실행해 PASS 17 / FAIL 0" 상태 문구 | 이번 실행 |
| 5단계 | 8.10 ISO로도 됨 · 메뉴 이름 · `release 8.10` | 이번 실행 |
| 7 · 9단계 | NAT 기대값 10.0.**3**.15 / 10.0.**3**.2 · ON으로 켜도 autoconnect=no가 될 수 있음과 nmcli 해결 | 문제 ①② |
| 16단계 | `passwd`는 한 줄만 따로 · .bash_profile은 oracle 세션에 | 문제 ③④ |
| 17단계 | 업로드 완료까지 기다리기 · Follow terminal folder 설명 | 문제 ⑤ |
| 20단계 | 0바이트 검사에 `! -name '*0'` 추가와 설명 | 문제 ⑥ |
| 23단계 | `.localdomain` 경고 · Summary에서 `db_domain` 없음 확인 | 문제 ⑦ |
| 25단계 | `cat >` → **`cat >>`** · `LISTENER_ORCL` 경고 | 문제 ⑪ |
| Z 트러블슈팅 | enp0s8 autoconnect · DBCA 8% 멈춤 · LISTENER_ORCL 사라짐(재설정 + register) 3행 추가 | 문제 ① ⑧ ⑪ |

---

## 5. 수동(dbts93) ↔ 자동(dbts94) 비교

| 항목 | 수동 dbts93 (오늘) | 자동 dbts94 (10-28) |
|---|---|---|
| 방법 | VirtualBox GUI + ISO 설치 + 명령 직접 입력 | `vagrant up` 한 번 (Ansible) |
| OS | OL 8.10 ISO · UEK7 5.15 | OL 8 공식 박스 8.10.700 · UEK7 |
| IP | 192.168.10.93 | 192.168.10.94 |
| 데이터 디스크 | 50 / 100 / 100 GB · LVM `VGDb` | 50 / 60 / 70 GB (크기로 디스크 구분) |
| SELinux | **disabled** (교재대로) | **Enforcing** (restorecon + `bash -c`로 해결) |
| 방화벽 | firewalld 켬 + 1521 허용 → check 항목 17개 | 방화벽 항목 생략 → 16개 |
| 문자셋 | **KO16MSWIN949** (교재 계획값) | AL32UTF8 |
| 메모리 | ASMM 1152 / 384 · HugePages 579 | ASMM(`AUTO_SGA` 1536) · HugePages |
| 리스너 HOST | `dbts93.localdomain` (DBCA가 만듦) | 템플릿 |
| 패치 | 19.3 base | 19.3 base |
| 걸린 시간 | 약 6~7시간 (실수와 대기 포함, 추정) | **28분 55초** |
| 재부팅 점검 | **PASS 17 / FAIL 0** | **PASS 16 / FAIL 0** |
| 겪은 문제 수 | 11건 (위 3장) | 1건 (SELinux 203/EXEC) |

- **정리**: 두 방법 모두 **같은 점검 스크립트로 FAIL 0**입니다.
- 수동 설치에서 겪은 문제는 대부분 **사람이 입력하는 과정**(붙여넣기 위치, 줄바꿈, 비밀번호)과 **GUI 기본값**(DBCA)에서 생겼습니다.
- 자동화가 왜 필요한지 보여 주는 근거로 쓸 수 있습니다.

---

## 6. 내일 다시 할 때 체크리스트

- 6단계: KDUMP **끄기**, Installation Destination에서 **sda만** 체크
- 7단계: enp0s3 Gateway **비우기**, 두 어댑터 ON, Host Name `dbts93` → **Apply**
- 9단계 첫 로그인: 아이디는 **`root`** · `ip route`에 `default via 10.0.3.2`가 없으면 ①의 nmcli
- 붙여넣기 전: **탭 이름과 `#` / `$`** 확인
- 긴 한 줄 명령은 붙여넣은 뒤 **한 줄로 들어갔는지** 보고 Enter
- 16단계: `passwd oracle`은 **따로**
- 17단계: SFTP 업로드가 **끝난 뒤** 명령 · 경로 칸에 `/work/media` 입력 후 목록 확인
- 20단계: `oklist` 등 원래 파일 크기 확인 (문제 ⑥)
- 23단계 DBCA:
  - 4번 Global name **`orcl`**(`.localdomain` 지우기)
  - 5번 **`/oradata/{DB_UNIQUE_NAME}`**
  - 9번 **ASMM 1152/384** · **KO16MSWIN949**
  - 11번 비밀번호 **`<비밀번호>`** 정확히 입력
  - 13번 Summary에서 `{ORACLE_BASE}`, `db_domain`이 없는지 확인
- DBCA가 오래 멈추면: 창은 두고 `ls -lt $ORACLE_BASE/cfgtoollogs/dbca/orcl` · `show pdbs`로 판단
- 25단계: tnsnames는 **`>>`** · DBeaver는 **Service Name `pdb`**
- 단계별 스냅샷: `A-끝` · `B-끝` · `G-끝` · `I-완료`
- 29 · 30단계 결과 파일 이름 확인: 설치 직후 `check_install.txt`, 재부팅 후 `check_reboot.txt` (오늘은 재부팅 후 실행으로 check_install을 덮어씀)

---

## 7. 남은 확인 · 증거 파일

| 항목 | 상태 |
|---|---|
| `/backup/check_reboot.txt` | ✅ PASS 17 / FAIL 0 (21:19) · PC로 내려받기 권장 |
| `/backup/check_install.txt` | ⚠️ 재부팅 후 중단된 실행으로 덮어써짐 · 설치 직후 PASS 17은 MobaXterm 화면 기록에만 남음 |
| `oklist` 등 원래 파일 크기 | 미확인 |
| crash recovery 로그 | 미확인 (정상 종료 뒤 꺼진 것으로 추정) |
| VirtualBox 스냅샷 `I-완료` | 미확인 |
| RU 19.25 (E 파트) | zip 없음 |
