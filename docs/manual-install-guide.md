# Oracle 19c 수동 설치 가이드: Oracle Linux 8.8, 8.10, dbts93

> Oracle Linux 8.8, 8.10 위에 VM 한 대부터 DB 자동 기동까지: 화면, 명령, 왜, 질문 대비
> 교재 「초보자를 위한 Oracle 19c」 2장 순서, 기준 2026-10-30

## 이 가이드에 대하여

- **대상**: 새 Windows PC에서 VirtualBox VM 한 대에 Oracle 19c를 **손으로 처음부터** 설치하는 사람(나)
- **만드는 것**: VM `dbts93`, Oracle Linux 8.8, Oracle 19c EE, CDB `orcl` + PDB `pdb`, ARCHIVELOG, HugePages, 재부팅해도 자동 기동
- **기준**: 교재 2장(18~93p) 순서와 용어. 이전 dbts93 실습(2026-10 초)에서 실제로 막힌 곳과 검증 보고서(22번)의 수정 사항을 미리 반영했다
- **같이 보기**: 자동 설치판 `D:\vagrant\oracle19c` (dbts94). 막히면 잘 된 VM과 값을 비교한다. 실패 기록은 05번 트러블슈팅에 있다
- **상태**: 문서 작성 2026-10-28. **2026-10-30 이 순서대로 OL 8.10 ISO로 처음부터 끝까지 직접 실행했다. 설치 직후, 재부팅 후 모두 check.sh PASS 17 / FAIL 0.** 실행 중 막힌 곳은 주황 상자에 '2026-10-30'으로 표시해 반영했다

실행 위치: 🪟 PC PowerShell, 🖱 화면, 🧑‍💻 root #, 🔶 oracle $, 🗄️ SQL>

## O. 먼저 그림부터: 무엇을 만드나

*설치 계획서, 교재와 다른 점, 준비물*

### O1. 설치 계획서

교재 20p의 설치 계획서 양식에 이번 VM 값을 채운 표다. 설치하는 동안 모든 입력값은 이 표에서 가져온다.

| 설정 | 값 | 교재 20p |
|---|---|---|
| OS 버전 | Oracle Linux 8.8 (UEK7 커널) | OEL 8.8 |
| Hostname | `dbts93` | DBTS91 |
| 서버 IP | `192.168.10.93/24`, 게이트웨이 **없음** (인터넷은 NAT 어댑터) | 192.168.10.91 / 192.168.10.1 |
| OS user / group | `oracle`(54321), `oinstall`(54321), `dba`(54322) 외 (preinstall RPM 기본값) | oracle(54321) / dba(54322) |
| Disk 방식 | File System (LVM + xfs) | File System |
| Engine 경로 | `/u01` ← `/dev/mapper/VGDb-LVDbOracle` 50G | 같음 |
| Data 경로 | `/oradata` ← `/dev/mapper/VGDb-LVDbData` 100G | 같음 |
| Archive/Backup 경로 | `/backup` ← `/dev/mapper/VGDb-LVDbBackup` 100G | 같음 |
| Oracle 버전 | 19.3 → RU zip이 있으면 **19.25.0.0** (Patch 36912597) | 19.25.0.0 |
| ORACLE_HOME | `/u01/app/oracle/product/19.0.0.0/dbhome_1` | 같음 |
| SID | `orcl` (**소문자**), CDB + PDB `pdb` | ORCL (non-CDB) |
| CharacterSet | `KO16MSWIN949` / National `AL16UTF16` | 같음 |
| Archive 경로 | `/backup/arch` | /backup/archive |
| 메모리 | VM 4GB → ASMM, SGA 1152MB, PGA 384MB | SGA 4096, PGA 1024 |

---

### O2. 교재와 다르게 하는 곳: 그리고 이유

- **SID**: 교재는 ORCL (대문자), 이 가이드는 `orcl` 소문자. 이유: DBCA가 만드는 파일은 소문자(`spfileorcl.ora`). 대문자로 두면 idle instance, ORA-01078 (05번).
- **DB 구조**: 교재는 non-CDB, 이 가이드는 CDB `orcl` + PDB `pdb`. 이유: SQL 실습 가이드(15번)와 그림책 25장이 CDB/PDB 기준.
- **OS 그룹**: 교재는 preinstall 그룹 삭제 후 `dba` 하나로 재생성(51p), 이 가이드는 preinstall이 만든 그룹 그대로. 이유: 역할 분리 표준(OFA)을 그대로 쓰고 단계를 줄인다. 그래서 HugePages 그룹은 `oinstall`(54321).
- **THP**: 교재는 grub 파일 수정 또는 서비스(29~30p), 이 가이드는 `grubby` 한 줄. 이유: OL8에서 BIOS, UEFI 상관없이 같은 결과. 이전에 grub 방식이 UEFI에서 안 먹었다.
- **firewalld**: 교재는 끄기(49p), 이 가이드는 켜 두고 1521만 허용. 이유: 끄면 편하지만 운영 습관이 아니다. 필요한 포트만 연다.
- **DISPLAY**: 교재는 `.bash_profile`에 고정(53p), 이 가이드는 넣지 않는다. 이유: MobaXterm SSH가 자동으로 잡는다. 고정하면 X11 창이 안 뜰 수 있다.
- **NLS_LANG**: 교재는 `...KO16MSWIN949`, 이 가이드는 `AMERICAN_AMERICA.AL32UTF8`. 이유: MobaXterm은 UTF-8로 보낸다. 안 맞으면 한글 식별자에서 ORA-00911 (05번).
- **root 스크립트**: 교재는 자동 실행(64p), 이 가이드는 같음 + 실패 시 수동 방법. 이유: root 비밀번호를 설치 때 만들어 두므로 자동이 된다.
- **HugePages 계산**: 교재는 MOS 스크립트(89~93p), 이 가이드는 한 줄 계산 + 교재 순서. 이유: 이전에 MOS 스크립트가 커널 5.x를 거부했다(05번). 계산식은 같다.
- **자동 기동**: 교재는 없음, 이 가이드는 oratab + systemd. 이유: 재부팅 후 ORA-12541, ORA-01109를 겪었다(05번).

---

### O3. 준비물, 시간

| 준비물 | 어디서 | 확인 |
|---|---|---|
| VirtualBox 7.2, MobaXterm | 이미 설치됨 (7.2.14 확인) | VirtualBox 실행, MobaXterm 실행 |
| Oracle Linux 8.8 DVD ISO (약 12GB) | `D:\ISO.zip` 안에 있는지 먼저 확인 → 없으면 5단계 주소 | `OracleLinux-R8-U8-x86_64-dvd.iso` |
| `LINUX.X64_193000_db_home.zip` | `D:\vagrant\media\` (10/28 받음) | SHA256 `ba8329c7…33aa8d8` 일치 확인 완료 |
| (선택) `p6880880…zip`, `p36912597…zip` | 원본 zip이 있을 때만. 풀린 폴더는 쓰지 않는다 | 없으면 E 파트를 건너뛴다 |
| `check.sh` | `D:\vagrant\oracle19c\scripts\check.sh` (자동판 zip) | I 파트에서 업로드 |
| D 드라이브 여유 | VM 디스크 4개는 쓴 만큼만 차지 | 약 40GB 이상 |

> **ℹ️ 참고**: 걸리는 시간은 OS 설치 30분, 사전 설정 30분, 엔진 설치 20분, (RU 40분), DBCA 30분, 운영 설정 20분으로 **반나절**이다. 파트가 끝날 때마다 VM 스냅샷을 찍어 두면 실패해도 그 지점부터 다시 할 수 있다(A 파트 끝 참고).

---

## A. VirtualBox: VM 한 대 만들기

*Host-Only 네트워크, VM, 네트워크 어댑터 2개, 데이터 디스크 3개*

### 1. Host-Only 네트워크 확인

**목표**: VM과 PC가 `192.168.10.x`로 서로 보이게 할 가상 네트워크(PC 쪽 주소 `192.168.10.1`)가 있는지 확인하고, 없으면 만든다.

🪟 **PC: PowerShell**
```powershell
& "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe" list hostonlyifs | Select-String "Name:|IPAddress:"
```

> **✅ 성공**: `IPAddress: 192.168.10.1` 이 있는 줄이 보이면 그 위의 `Name`(예: `VirtualBox Host-Only Ethernet Adapter #2`)을 적어 두고 **2단계로**. 자동판(`vagrant up`)을 한 번 돌렸다면 이미 만들어져 있다.

없으면 VirtualBox에서 만든다. 이미 192.168.10.1 어댑터가 있으면 새로 만들지 않는다.

#### 네트워크 관리자: Host-only Networks

1. **파일 → 도구 → 네트워크 관리자 → Host-only Networks → 만들기**를 누른다.
2. 새로 생긴 어댑터를 고른다. 목록에는 VirtualBox Host-Only Ethernet Adapter #2, 192.168.10.1/24, 사용 안 함처럼 보인다.
3. **어댑터** 탭을 연다.
4. 수동으로 어댑터 설정(Configure Adapter Manually): 선택한다.
5. IPv4 주소: **192.168.10.1**을 입력한다.
6. IPv4 네트워크 마스크: **255.255.255.0**을 입력한다.
7. DHCP 서버 탭: '서버 사용' 체크를 해제한다.
8. 적용한다.

- **Host-Only**: PC와 VM만 통하는 사설망. MobaXterm(SSH), DBeaver(1521)가 이 길로 VM에 들어간다.
- **DHCP 끔**: DB 서버는 IP가 바뀌면 안 된다. VM 안에서 `.93`을 직접 넣는다.
- **`192.168.10.1`**: PC 쪽 주소. VM의 게이트웨이로 쓰지 **않는다**(인터넷 출구가 아님). 3단계 참고.

---

### 2. VM 만들기

**목표**: 이름 `dbts93`, Oracle Linux 64-bit, 메모리 4GB, CPU 2, OS 디스크 50GB(동적)인 빈 VM을 만든다.

VirtualBox → **새로 만들기(New)**. 아래 값만 넣는다. VirtualBox 7.x 전문가 모드 기준이고, 구역 이름은 버전마다 조금 다르다.

#### 구역 1: 이름과 운영체제

1. VM Name: **dbts93**을 입력한다.
2. VM Folder: **D:\VirtualBoxVMs**를 고른다.
3. ISO Image: **D:\ISO\OracleLinux-R8-U8-x86_64-dvd.iso**를 고른다.
4. OS: **Linux**인지 확인한다 (ISO를 고르면 자동으로 채워진다).
5. OS Distribution: **Oracle**인지 확인한다 (ISO를 고르면 자동으로 채워진다).
6. OS Version: **Oracle Linux 8.x (64-bit)**인지 확인한다 (ISO를 고르면 자동으로 채워진다).
7. Skip Unattended Installation: 체크한다.

#### 구역 2: 하드웨어

1. Base Memory: **4096 MB**를 입력한다.
2. Processors: **2**를 입력한다.

#### 구역 3: 디스크

1. Create a Virtual Hard Disk Now: 선택한다.
2. Disk Size: **50.00 GB**를 입력한다.
3. Hard Disk File Type: **VDI (VirtualBox Disk Image)** 그대로 둔다.
4. Pre-allocate Full Size: 체크하지 않는다.

> **⚠️ 주의**: ISO를 고르면 VirtualBox가 **무인 설치(Unattended Installation)**를 자동으로 켠다. 이대로 가면 파티션, 네트워크를 고를 기회 없이 설치가 끝난다. **'Skip Unattended Installation'을 체크**(버전에 따라 'Proceed with Unattended Installation' 체크 해제)한다.

- **메모리 4096MB**: 교재 21p 최소 1GB, 권장 2GB. SGA 1.1GB + PGA + OS 여유. HugePages로 SGA를 묶어 두므로 너무 작으면 OS가 빠듯해진다.
- **CPU 2**: DBCA, 압축 해제 시간이 절반 가까이 준다.
- **EFI 끔**: BIOS 부팅이면 `/boot/efi` 파티션이 필요 없어 8단계가 단순해진다.
- **디스크 50GB 동적**: OS만 들어간다. Oracle은 따로 붙이는 디스크(4단계)에 둔다. 동적이라 실제로 쓴 만큼만 D 드라이브를 차지한다.

---

### 3. 네트워크 어댑터 2개

**목표**: 어댑터 1 = Host-Only(PC ↔ VM), 어댑터 2 = NAT(VM → 인터넷)로 **처음부터 둘 다** 꽂는다.

VM 선택 → **설정 → 네트워크**.

#### 어댑터 1 탭

1. 네트워크 어댑터 사용하기: 체크한다.
2. 다음에 연결됨: **호스트 전용 어댑터 (Host-only Adapter)**를 고른다.
3. 이름: **VirtualBox Host-Only Ethernet Adapter #2  (192.168.10.1)**을 고른다. 1단계에서 적어 둔 192.168.10.1 어댑터다.

#### 어댑터 2 탭

1. 네트워크 어댑터 사용하기: 체크한다.
2. 다음에 연결됨: **NAT**를 고른다.
3. 고급 → 포트 포워딩: 설정하지 않는다.

> **⚠️ 주의**: 이전 실습에서 Host-Only만 꽂고 시작했다가 `dnf install`에서 인터넷이 없어 막혔고, 나중에 NAT를 추가하면서 Host-Only에 게이트웨이를 넣어 **가짜 기본 경로**가 생겨 인터넷이 계속 안 됐다. 처음부터 둘 다 꽂고, Host-Only에는 게이트웨이를 넣지 않으면 이 문제 자체가 없다.

- **어댑터 1 Host-Only**: 고정 IP `192.168.10.93`(SSH, DB 접속용). VM 안에서는 보통 `enp0s3`.
- **어댑터 2 NAT**: VirtualBox가 인터넷으로 내보내 주는 출구. VM 안에서 `enp0s8`, DHCP로 `10.0.3.15`를 받는다(NAT를 어댑터 2에 두면 VirtualBox가 10.0.3.0/24 대역을 준다. 어댑터 1이면 10.0.2.x).
- **포트 포워딩 없음**: PC에서 `192.168.10.93:22`로 바로 들어가므로 NAT 포트 포워딩은 필요 없다(이전 `2293` 방식보다 단순하다).

---

### 4. 데이터 디스크 3개 붙이기

**목표**: `/u01`, `/oradata`, `/backup`이 될 디스크 3개(50, 100, 100GB)를 SATA 포트 1, 2, 3에 새로 만들어 붙인다.

VM이 **꺼진 상태**에서 아래를 세 번 한다. 포트 1, 2, 3 순서대로 만들면 VM 안에서 sdb, sdc, sdd로 잡힌다.

1. **설정 → 저장소 → SATA 컨트롤러 → 하드 디스크 추가(디스크 아이콘 +) → 만들기**를 누른다.
2. VDI, 동적 할당을 고르고 이름과 크기만 바꾼다.

#### 설정, 저장소: 세 개를 붙인 뒤

- dbts93.vdi (OS), 0, 50 GB, D:\VirtualBoxVMs\dbts93\dbts93.vdi
- dbts93_u01.vdi, 1, 50 GB, …\dbts93\dbts93_u01.vdi
- dbts93_oradata.vdi, 2, 100 GB, …\dbts93\dbts93_oradata.vdi
- dbts93_backup.vdi, 3, 100 GB, …\dbts93\dbts93_backup.vdi
- 광학 드라이브, 4, -, OracleLinux-R8-U8-x86_64-dvd.iso

> **⚠️ 주의**: Virtual Media Manager 목록에 예전 VM의 `u01.vdi` 같은 파일이 보여도 **절대 고르지 않는다.** 두 VM이 같은 디스크를 물면 둘 다 깨진다. 항상 '만들기'로 새 파일을, VM 이름이 들어간 이름으로 만든다.

- **OS와 데이터 디스크 분리**: OS를 다시 깔아도 DB 파일은 그대로다. 교재 28p도 DB 파일 시스템을 OS와 분리하라고 권장한다.
- **3개를 VG 하나로**: 교재 20p 계획대로 `VGDb` 하나에 LV 3개. 나중에 공간이 모자라면 디스크를 하나 더 붙여 VG를 키울 수 있다.
- **동적 할당**: 250GB를 잡아도 실제 사용량만 D 드라이브에 생긴다.

**💬 질문 대비**

- **Q. 왜 /u01, /oradata, /backup을 나누나?** 프로그램, 데이터, 백업은 늘어나는 속도와 장애 영향이 다르다. 백업이 디스크를 꽉 채워도 데이터 파일 공간은 영향을 받지 않고, 디스크 장애 때 무엇이 사라졌는지 바로 안다. 그림책 2장 '서버 바닥'의 세 칸이 이것이다.

> **ℹ️ 참고**: **스냅샷 습관**. 파트(A, B, C…)가 끝날 때마다 VirtualBox **스냅샷 → 찍기**로 `A-끝`, `B-끝`처럼 남겨 둔다. 다음 파트에서 꼬이면 스냅샷으로 되돌려 그 파트만 다시 한다.

---

## B. Oracle Linux 8.8 설치

*ISO, 설치 요약 화면, 네트워크, 디스크, 첫 접속*

### 5. ISO 준비하고 부팅

**목표**: Oracle Linux 8.8 DVD ISO를 VM의 광학 드라이브에 넣고 설치 화면까지 간다.

먼저 `D:\ISO.zip` 안에 `OracleLinux-R8-U8-x86_64-dvd.iso`가 있는지 본다. 없으면 Oracle 공식 주소(로그인 불필요)에서 받는다.

🪟 **PC: 브라우저 주소**
```powershell
https://yum.oracle.com/ISOS/OracleLinux/OL8/u8/x86_64/OracleLinux-R8-U8-x86_64-dvd.iso
```

> **ℹ️ 참고**: OL **8.10** DVD ISO(`OEL8_10.iso`)로도 같은 순서로 끝까지 됐다(2026-10-30). 이때 첫 화면 메뉴는 **Install Oracle Linux 8.10.0**, 9단계 확인 값은 `release 8.10`.

받은 ISO를 `D:\ISO\`에 두고, VM **설정 → 저장소 → 광학 드라이브(비어 있음) → 디스크 파일 선택**으로 넣은 뒤 **시작**. 첫 화면에서 ↑로 **Install Oracle Linux 8.8.0**을 선택하고 Enter.

> **ℹ️ 참고**: boot ISO(약 900MB)는 설치 중에 인터넷 저장소 주소를 따로 넣어야 해서 이 가이드는 DVD ISO 기준이다. 설치 언어는 **English**로 한다. 화면 이름이 교재, 이 가이드와 같고, 에러 메시지를 검색하기 쉽다.

---

### 6. 설치 요약(INSTALLATION SUMMARY) 화면

**목표**: 한 화면에 모인 6개 항목을 아래 값으로 채운다. 빨간 느낌표가 모두 사라지면 **Begin Installation**이 켜진다.

#### INSTALLATION SUMMARY: 다 채운 뒤

빨간 테두리 5곳을 채우면 아래처럼 보인다.

- Time & Date: **Asia/Seoul timezone**
- Software Selection: **Server**
- Installation Destination: **Automatic partitioning selected**
- KDUMP: **Kdump is disabled**
- Network & Host Name: **Wired (enp0s3) connected**
- Root Password: **Root password is set**

- **Time & Date**: Region **Asia** / City **Seoul**. alert log, 백업 시각이 한국 시간으로 남는다.
- **Software Selection**: **Server** (Add-on 없음). GUI 없는 서버 구성. Minimal보다 기본 관리 도구가 많다. X11에 필요한 xauth는 11단계에서 확실히 설치한다.
- **Installation Destination**: 50GB 디스크 하나만 체크, **Automatic** (8단계). Oracle용 디스크 3개는 여기서 건드리지 않는다.
- **KDUMP**: Disabled. 커널 덤프용 메모리(수백 MB)를 아낀다. 실습 VM에는 필요 없다.
- **Network & Host Name**: 7단계. IP와 이름을 설치 때 정해 둔다.
- **Root Password**: 실습용 비밀번호 (잊지 않을 값). runInstaller가 root 스크립트를 자동 실행할 때 쓴다(교재 64p).

> **ℹ️ 참고**: User Creation(일반 사용자)은 만들지 않아도 된다. 이 가이드는 root와 oracle 두 계정만 쓴다(교재도 `#` root, `$` oracle).

---

### 7. 네트워크, 호스트 이름

**목표**: `enp0s3` = `192.168.10.93/24` 게이트웨이 없음, `enp0s8` = 자동(DHCP), 호스트 이름 `dbts93`.

#### NETWORK & HOST NAME

1. Ethernet (enp0s3), Ethernet (enp0s8): 오른쪽 스위치를 둘 다 ON으로 켠다.
2. Host Name: **dbts93**을 입력하고 **Apply**를 누른다.

끝나면 아래처럼 보인다.

- Ethernet (enp0s3): Intel 82540EM, Connected, 192.168.10.93, ON
- Ethernet (enp0s8): Intel 82540EM, Connected, 10.0.3.15 (DHCP), ON
- Current host name: dbts93

#### Editing enp0s3: IPv4 Settings

Gateway를 넣지 않는 것이 핵심이다.

1. **enp0s3**를 고르고 **Configure…**를 누른다.
2. **IPv4 Settings** 탭을 연다.
3. Method: **Manual**을 고른다.
4. 주소 칸에 192.168.10.93, 24를 넣고 Gateway는 비워 둔다.
5. DNS servers: 비워 둔다.
6. General 탭: 'Connect automatically with priority'가 체크돼 있는지 본다(기본값).

> **⚠️ 주의**: Gateway 칸은 **비워 둔다.** `192.168.10.1`은 PC의 가상 어댑터일 뿐 인터넷 출구가 아니다. 여기에 넣으면 NAT의 진짜 경로보다 우선하는 기본 경로가 생겨 `dnf`가 `Could not resolve host`로 막힌다(이전 실습에서 실제로 겪었다).

- **두 어댑터 모두 ON**: OFF로 두면 설치 후에도 꺼진 채 부팅된다. 오른쪽 스위치를 둘 다 켠다. **ON으로 켜도 enp0s8이 autoconnect=no로 저장될 수 있다(2026-10-30 OL 8.10 실행에서 겪었다)** → 9단계 `ip route`에 default가 없으면 `nmcli con mod enp0s8 connection.autoconnect yes ipv4.method auto` → `nmcli con up enp0s8`.
- **Connect automatically**: IPv4 화면 옆 General 탭에서 체크(기본값 체크). 재부팅 때 자동으로 연결된다.
- **Host Name `dbts93` → Apply**: 리스너, DBCA가 이 이름을 쓴다. Apply를 눌러야 반영된다.

---

### 8. 디스크: 자동 LVM

**목표**: OS 디스크(sda, 50GB)에만 설치하고, Oracle용 디스크 3개는 비워 둔다.

#### INSTALLATION DESTINATION

1. ATA VBOX HARDDISK, sda, 50 GiB: 체크한다.
2. ATA VBOX HARDDISK, sdb, 50 GiB: 체크하지 않는다.
3. ATA VBOX HARDDISK, sdc, 100 GiB: 체크하지 않는다.
4. ATA VBOX HARDDISK, sdd, 100 GiB: 체크하지 않는다.
5. Storage Configuration: Automatic을 선택한다.

**Storage Configuration: Automatic** 그대로 Done. 자동 구성은 일반 LVM으로 `/boot` 1GB, swap(RAM과 같은 약 4GB), `/`(나머지)를 만든다. 교재 23p의 스왑 기준(RAM 2~16GB면 RAM과 같게)과 맞는다.

> **⚠️ 주의**: **Custom**으로 직접 나눌 때 Device Type이 'LVM Thin Provisioning'으로 잡히면 `/`가 요청보다 작게(36GiB → 26.34GiB) 잡히는 문제가 있었다. 고치려 하지 말고 **Reset All** 후 첫 마운트 포인트의 Device Type을 일반 **LVM**으로 지정해 다시 만든다. 그래서 이 가이드는 Automatic을 쓴다.

- **sdb, sdc, sdd 체크 안 함**: 여기서 체크하면 설치 프로그램이 Oracle용 디스크까지 OS 볼륨으로 써 버린다. 15단계에서 직접 LVM을 만든다.
- **Automatic**: OS 파티션은 표준 배치로 충분. 시간을 Oracle 쪽에 쓴다.

---

### 9. 설치, 재부팅, MobaXterm 접속

**목표**: 설치를 끝내고 PC의 MobaXterm에서 `root@192.168.10.93`, `oracle@192.168.10.93` 두 세션으로 접속할 준비를 한다.

**Begin Installation** → 10~15분 → **Reboot System**. 다시 켜질 때 ISO는 VirtualBox가 자동으로 빼 준다(설치 화면이 또 뜨면 광학 드라이브에서 ISO 제거 후 재시작).

#### MobaXterm: Session settings, SSH

9단계와 16단계에서 같은 화면을 쓴다.

1. MobaXterm에서 **Session → SSH**를 누른다.
2. Remote host: `192.168.10.93`을 입력한다.
3. Specify username: 체크한다.
4. Username: `root`를 입력한다. 두 번째 세션은 oracle이다.
5. Port: **22**인지 확인한다.
6. **Advanced SSH settings** 탭을 연다.
7. X11-Forwarding: 체크한다(기본으로 켜져 있다).
8. SSH-browser (SFTP): 체크된 상태로 둔다.
9. Bookmark settings → Session name: **dbts93-root / dbts93-oracle**인지 확인한다.
10. OK를 누른다. 비밀번호는 6단계 값이다.

🧑‍💻 **dbts93: root #**
```bash
hostnamectl --static
ip -4 -br addr
ip route
cat /etc/oracle-release; uname -r
```

> **✅ 성공**: `dbts93`, `enp0s3 UP 192.168.10.93/24`, `enp0s8 UP 10.0.3.15/24`, `default via 10.0.3.2 dev enp0s8` **한 줄만**, `Oracle Linux Server release 8.8`(8.10 ISO면 8.10), 커널 `5.15.0-…el8uek`

> **⚠️ 주의**: `ip route`에 `default via 192.168.10.1 dev enp0s3`가 같이 보이면 7단계 Gateway가 들어간 것이다. 아래 두 줄로 지운다: `nmcli connection modify enp0s3 ipv4.gateway ""` → `nmcli connection up enp0s3`

**💬 질문 대비**

- **Q. UEK 커널이 뭔가?** Oracle Linux의 기본 커널(Unbreakable Enterprise Kernel). 8.8의 UEK7은 5.15 계열이다. Oracle 19c 문서 기준으로 OL 8.8 + UEK7은 19.21 이상 RU에서 지원되므로, 19.3 그대로면 '설치는 되지만 비지원 조합'이다. E 파트에서 19.25를 적용하는 이유가 이것이다.

---

## C. OS 사전 설정

*교재 29~55p: 패키지, hosts, THP, 보안, 디스크, oracle 계정, 설치 파일*

### 10. 인터넷, 저장소 확인

**목표**: VM이 `yum.oracle.com`에서 패키지를 받을 수 있는지 먼저 확인한다.

🧑‍💻 **dbts93: root #**
```bash
ping -c 2 yum.oracle.com
dnf repolist
```

> **✅ 성공**: ping 응답 2개, `ol8_baseos_latest`, `ol8_appstream`, `ol8_UEKR7`이 목록에 있다

> **ℹ️ 참고**: 인터넷이 없는 환경이면 교재 31~32p의 DNF Local Repository(ISO를 마운트해 저장소로 쓰기)로 대신한다. 이 VM은 NAT가 있으니 필요 없다.

---

### 11. preinstall RPM과 필요한 도구

**목표**: 커널 파라미터, oracle 계정, 리소스 제한을 한 번에 맞추는 `oracle-database-preinstall-19c`와 X11, 압축 도구를 설치한다.

🧑‍💻 **dbts93: root #**
```bash
dnf install -y oracle-database-preinstall-19c
dnf install -y unzip xorg-x11-xauth xterm bc
id oracle
sysctl kernel.shmmax fs.file-max
```

> **✅ 성공**: `uid=54321(oracle) gid=54321(oinstall) groups=54321(oinstall),54322(dba),…`, `fs.file-max = 6815744`

> **📘 교재와 다름**: 교재 41p는 OL7용 `compat-libcap1`, `compat-libstdc++-33`을 추가로 받아 설치한다. OL8의 preinstall RPM은 19c에 필요한 패키지를 이미 의존성으로 가져오므로 **설치하지 않는다**(검증 보고서 사실 오류 항목). runInstaller 사전 점검에서 이 둘이 없다고 나오면 무시해도 된다.

- **preinstall RPM**: 교재 40p. 필수 패키지, 커널 파라미터(`/etc/sysctl.d/`), oracle 사용자와 그룹, limits를 Oracle 권장값으로 자동 설정한다.
- **`xorg-x11-xauth`**: SSH X11 포워딩에 필요하다. 없으면 MobaXterm에서 `DISPLAY`가 비어 runInstaller 창이 안 뜬다.
- **`xterm`**: X11이 되는지 가장 가볍게 확인하는 창(18단계). `xclock`은 OL8 저장소에 없어서 대신 쓴다.

---

### 12. /etc/hosts: 이름을 서비스 IP로

**목표**: `dbts93`이 `192.168.10.93`으로 풀리게 한다.

🧑‍💻 **dbts93: root #**
```bash
echo '192.168.10.93  dbts93.localdomain dbts93' >> /etc/hosts
getent hosts dbts93
```

> **✅ 성공**: `192.168.10.93   dbts93.localdomain dbts93`

- **이게 없으면**: DBCA 안의 netca가 `No valid IP Address returned for the host dbts93`로 실패한다(05번, 이전 Rocky 9 실습).
- **127.0.0.1에 붙이지 않는 이유**: 리스너가 루프백에만 묶이면 PC(DBeaver)에서 접속이 안 된다.

---

### 13. THP 끄기

**목표**: Transparent HugePages를 끈다(교재 29~30p).

🧑‍💻 **dbts93: root #**
```bash
cat /sys/kernel/mm/transparent_hugepage/enabled
grubby --update-kernel=ALL --args="transparent_hugepage=never"
grubby --info=DEFAULT | grep args
```

> **✅ 성공**: 첫 줄은 `[always] madvise never`(켜짐), 마지막 줄 `args="… transparent_hugepage=never"`. 실제 적용은 14단계의 재부팅 뒤

> **📘 교재와 다름**: 교재는 `/etc/default/grub` 수정 + `grub2-mkconfig`(방법 1) 또는 systemd 서비스(방법 2). `grubby`는 설치된 모든 커널의 부팅 옵션에 직접 넣어 주므로 BIOS, UEFI 경로를 신경 쓸 필요가 없다.

**💬 질문 대비**

- **Q. THP와 HugePages는 다른가?** 다르다. THP는 커널이 알아서 큰 페이지를 붙였다 떼는 기능이라 Oracle에서는 지연, 메모리 단편화를 일으켜 끈다(교재 29p, Doc ID 2066217.1). HugePages는 DBA가 미리 정해 두는 고정 큰 페이지로, SGA를 여기에 올린다(27단계).

---

### 14. SELinux, firewalld, 재부팅

**목표**: 교재대로 SELinux를 끄고, 방화벽은 켜 둔 채 리스너 포트만 연다. 재부팅해서 THP, SELinux를 적용한다.

🧑‍💻 **dbts93: root #**
```bash
sed -i 's/^SELINUX=.*/SELINUX=disabled/' /etc/selinux/config
firewall-cmd --permanent --add-port=1521/tcp
firewall-cmd --reload
systemctl disable --now avahi-daemon.socket avahi-daemon 2>/dev/null; true
reboot
```

1분 뒤 MobaXterm에서 세션을 다시 연다(탭에서 R 버튼).

🧑‍💻 **dbts93: root #**
```bash
sestatus | head -1
cat /sys/kernel/mm/transparent_hugepage/enabled
firewall-cmd --list-ports
```

> **✅ 성공**: `SELinux status: disabled`, `always madvise [never]`, `1521/tcp`

> **📘 교재와 다름**: 교재 49p는 firewalld를 끈다. 이 가이드는 켜 둔 채 리스너 포트 1521만 연다(EM Express는 교재 80p대로 쓰지 않으므로 5500은 열지 않는다). SELinux는 교재대로 끈다(실습용). 운영 서버라면 SELinux는 enforcing 유지가 원칙이다.

- **avahi-daemon**: 교재 49p. 프린터, 공유 폴더 자동 탐색. 고정 IP DB 서버에는 필요 없다. Server 설치에 없으면 메시지 없이 넘어간다.
- **재부팅**: THP 부팅 옵션과 SELinux 설정은 재부팅해야 적용된다.

---

### 15. 데이터 디스크 3개 → LVM → /u01, /oradata, /backup

**목표**: 교재 20p 계획대로 VG `VGDb` 하나에 LV 3개를 만들고 xfs로 마운트한다.

🧑‍💻 **dbts93: root #**
```bash
lsblk -d -o NAME,SIZE,TYPE
pvcreate /dev/sdb /dev/sdc /dev/sdd
vgcreate VGDb /dev/sdb /dev/sdc /dev/sdd
lvcreate -L 50G  -n LVDbOracle VGDb
lvcreate -L 100G -n LVDbData   VGDb
lvcreate -l 100%FREE -n LVDbBackup VGDb
mkfs.xfs /dev/VGDb/LVDbOracle; mkfs.xfs /dev/VGDb/LVDbData; mkfs.xfs /dev/VGDb/LVDbBackup
mkdir -p /u01 /oradata /backup
echo "UUID=$(blkid -s UUID -o value /dev/VGDb/LVDbOracle) /u01 xfs defaults 0 0" >> /etc/fstab
echo "UUID=$(blkid -s UUID -o value /dev/VGDb/LVDbData) /oradata xfs defaults 0 0" >> /etc/fstab
echo "UUID=$(blkid -s UUID -o value /dev/VGDb/LVDbBackup) /backup xfs defaults 0 0" >> /etc/fstab
mount -a
df -h /u01 /oradata /backup
```

> **✅ 성공**: `lsblk`에 `sda 50G`, `sdb 50G`, `sdc 100G`, `sdd 100G`, 마지막 `df`에 세 줄(50G, 100G, 약 100G)

> **⚠️ 주의**: `lsblk`에서 50G, 100G, 100G 디스크가 `sdb`, `sdc`, `sdd`가 아니면, 아래 명령의 장치 이름을 **실제 이름**으로 바꾼다. OS 디스크(sda, 파티션이 있는 것)를 넣으면 OS가 지워진다.

- **마지막만 `-l 100%FREE`**: `-L 100G`로 정확히 요청하면 PV 메타데이터 몫 때문에 `Insufficient free space (25597 extents): 25600 required`로 실패했다(05번). 남은 전부를 주면 이 문제가 없다.
- **`UUID=`로 fstab**: 장치 이름(`/dev/sdb`)은 디스크를 추가, 제거하면 바뀔 수 있다. UUID는 파일 시스템마다 고정이다.
- **`mount -a`**: fstab에 쓴 줄이 맞는지 재부팅 전에 확인한다. 틀리면 여기서 에러가 나므로 부팅 실패를 막는다.

---

### 16. oracle 계정, 디렉터리, .bash_profile

**목표**: oracle 비밀번호, Oracle 디렉터리와 소유권, 환경 변수를 맞춘다(교재 51~55p).

🧑‍💻 **dbts93: root #**
```bash
passwd oracle
mkdir -p /u01/app/oracle/product/19.0.0.0/dbhome_1 /u01/app/oraInventory /work/media /backup/arch
chown -R oracle:oinstall /u01 /oradata /backup /work/media
chmod -R 775 /u01 /oradata /backup
```

> **⚠️ 주의**: `passwd oracle`은 **따로 한 줄만** 붙여 넣고 비밀번호를 입력한 뒤 나머지 줄을 붙인다. 같이 붙이면 뒤의 `mkdir`, `chown` 줄이 비밀번호 입력으로 먹혀 실행되지 않는다(2026-10-30 OL 8.10 실행에서 겪었다). 그리고 아래 oracle 상자(.bash_profile)는 반드시 **oracle 세션(`$`)**에 붙인다. root 탭에 붙이면 `/root/.bash_profile`에 들어간다.

이제 MobaXterm에 **두 번째 세션**을 `oracle` 사용자로 만든다(9단계와 같고 username만 `oracle`). 이후 `oracle $` 상자는 이 세션에서 친다.

🔶 **dbts93: oracle $**
```bash
cat >> ~/.bash_profile <<'EOF'
export TZ=Asia/Seoul
export ORACLE_BASE=/u01/app/oracle
export ORACLE_HOME=$ORACLE_BASE/product/19.0.0.0/dbhome_1
export ORACLE_SID=orcl
export PATH=$ORACLE_HOME/bin:$ORACLE_HOME/OPatch:$PATH
export LD_LIBRARY_PATH=$ORACLE_HOME/lib
export NLS_LANG=AMERICAN_AMERICA.AL32UTF8
export PS1='[$ORACLE_SID]\u@\h:$PWD> '
alias ss='sqlplus / as sysdba'
alias t_dbalert='tail -f $ORACLE_BASE/diag/rdbms/orcl/orcl/trace/alert_orcl.log'
EOF
source ~/.bash_profile
echo $ORACLE_SID $ORACLE_HOME
```

> **✅ 성공**: `orcl /u01/app/oracle/product/19.0.0.0/dbhome_1`, 프롬프트가 `[orcl]oracle@dbts93:/home/oracle>`

> **📘 교재와 다름**: 교재 53p와 다른 세 가지는 다음과 같다. ① `ORACLE_SID=orcl` 소문자(대문자면 ORA-01078) ② `NLS_LANG`의 문자셋 `AL32UTF8`(DB 문자셋 KO16MSWIN949와 달라도 Oracle이 변환해 준다. 터미널 인코딩과 맞추는 것이 핵심이다) ③ `DISPLAY`는 넣지 않는다(MobaXterm이 자동 설정한다).

- **`/u01` 전체를 oracle:oinstall**: `/u01/app/oraInventory`를 runInstaller가 만들 수 있어야 한다. `/u01/app`이 root 소유로 남으면 인벤토리 생성에서 막힐 수 있다(검증 보고서 M3).
- **`/work/media`**: 교재 56p의 설치 파일 자리.
- **`/backup/arch`**: 26단계 아카이브 로그 위치. 미리 만들어 둔다.

---

### 17. 설치 파일 업로드, 압축 해제

**목표**: `LINUX.X64_193000_db_home.zip`을 VM으로 옮겨 SHA256을 확인하고 ORACLE_HOME에 푼다(교재 56~57p).

MobaXterm **oracle 세션** 왼쪽 SFTP 창에서 경로 칸에 `/work/media`를 입력하고 Enter → `D:\vagrant\media\LINUX.X64_193000_db_home.zip`을 끌어다 놓는다(약 3GB, 1~3분). RU를 적용할 거면 `p6880880…zip`, `p36912597…zip`도 같이 올린다.

🔶 **dbts93: oracle $**
```bash
cd /work/media
sha256sum LINUX.X64_193000_db_home.zip
unzip -q LINUX.X64_193000_db_home.zip -d $ORACLE_HOME
ls $ORACLE_HOME | head
```

> **⚠️ 주의**: 업로드는 MobaXterm 아래 진행 표시가 **사라질 때까지** 기다린 뒤 명령을 친다. 전송 중에 치면 `No such file`이 나온다. SFTP 창은 **Follow terminal folder**가 켜져 있으면 터미널의 `cd`를 따라가므로, 목록에 보이는 폴더가 실제 위치다(2026-10-30 OL 8.10 실행에서 겪었다).

> **✅ 성공**: SHA256 `ba8329c757133da313ed3b6d7f86c5ac42cd9970a28bf2e6233f3235233aa8d8`, `ls`에 `runInstaller`, `OPatch`, `bin` 등

- **ORACLE_HOME에 바로 푼다**: 19c부터는 zip 자체가 Oracle Home 이미지다. 푼 자리가 곧 설치 위치(교재 57p).
- **SHA256 먼저**: 3GB 파일은 전송 중에 깨질 수 있다. 깨진 채 설치하면 엉뚱한 단계에서 실패한다.

---

## D. Oracle engine 설치: runInstaller

*교재 56~67p: X11 확인, 화면 10개, 확인*

### 18. X11 창이 PC에 뜨는지 확인

**목표**: oracle 세션에서 리눅스 GUI 창이 Windows 화면에 뜨는지 본다.

🔶 **dbts93: oracle $**
```bash
echo $DISPLAY
xterm &
```

> **✅ 성공**: `localhost:10.0` 같은 값, 검은 xterm 창이 PC 화면에 뜬다 → 창을 닫는다

> **⚠️ 주의**: `DISPLAY`가 비어 있으면 11단계 `xorg-x11-xauth` 설치 **뒤에 세션을 새로 열었는지** 확인한다(설치 전 열어 둔 세션에는 적용되지 않는다). `su - oracle`로 바꾼 세션은 X11 인증이 넘어가지 않으므로, oracle로 **직접 로그인한 세션**을 쓴다.

---

### 19. runInstaller: 화면 10개

**목표**: 소프트웨어만(Set Up Software Only) Enterprise Edition으로 설치한다. 화면마다 아래 값.

🔶 **dbts93: oracle $**
```bash
cd $ORACLE_HOME
export CV_ASSUME_DISTID=OEL7.8
./runInstaller
```

> **📘 교재와 다름**: 교재 57p는 `CV_ASSUME_DISTID=OL7`로 쓰고, 이 가이드는 Oracle 문서, oracle-base에서 쓰는 형식인 `OEL7.8`을 쓴다(자동판과 같은 값). 19.3 설치 프로그램이 OL8을 몰라서 `[INS-08101] … clientSupportedOSCheck`로 멈추는 것을 막는다. 설치 프로그램에게 'OL7인 셈 치라'고 알려 주는 것일 뿐 실제 OS는 바뀌지 않는다.

#### Step 1 of 9: Select Configuration Option (교재 58p)

1. Set Up Software Only: 선택한다.

#### Step 3 of 9: Select Database Edition (교재 60p)

1. Enterprise Edition: 선택한다. 파티셔닝, 비트맵 인덱스 실습에 EE가 필요하다.

#### Step 4 of 9: Specify Installation Location (교재 61p)

1. Oracle base: **/u01/app/oracle**을 입력한다.
2. Software location: **/u01/app/oracle/product/19.0.0.0/dbhome_1**. runInstaller를 실행한 ORACLE_HOME으로 고정돼 있다.
3. 다음 Create Inventory 화면은 /u01/app/oraInventory, oinstall이다.

#### Step 6 of 9: Privileged Operating System groups (교재 63p)

기본값 그대로 둔다(교재는 모두 dba).

- Database Administrator (OSDBA) group: **dba**
- Database Operator (OSOPER) group (Optional): **oper**
- Database Backup and Recovery (OSBACKUPDBA) group: **backupdba**
- Data Guard administrative (OSDGDBA) group: **dgdba**
- Encryption Key Management administrative (OSKMDBA) group: **kmdba**
- Real Application Cluster administrative (OSRACDBA) group: **racdba**

#### Step 7 of 9: Root script execution configuration (교재 64p)

1. Automatically run configuration scripts: 체크한다.
2. Use "root" user credential: 선택한다.
3. Password: **••••••••  (6단계 root 비밀번호)**를 입력한다.

| # | 화면 | 할 것 | 교재 |
|---|---|---|---|
| 1 | Configuration Option | **Set Up Software Only** | 58p |
| 2 | Database Installation Options | **Single instance database installation** | 59p |
| 3 | Database Edition | **Enterprise Edition** | 60p |
| 4 | Installation Location | Oracle base `/u01/app/oracle`, Software location은 자동으로 ORACLE_HOME | 61p |
| 5 | Create Inventory | `/u01/app/oraInventory`, 그룹 `oinstall` | 62p |
| 6 | Operating System Groups | OSDBA `dba`, OSOPER `oper`, BACKUPDBA `backupdba`, DGDBA `dgdba`, KMDBA `kmdba`, RACDBA `racdba` (기본값) | 63p |
| 7 | Root script execution | **Automatically run** 체크, Use "root" user credential, 6단계 root 비밀번호 | 64p |
| 8 | Prerequisite Checks | 경고만 있으면 **Ignore All** → Next → Yes | 65p |
| 9 | Summary | 값 확인 → **Install** | 66p |
| 10 | Install Product | 진행 중 'execute configuration scripts' 확인 창 → **Yes** → 끝나면 Close | 67p |

> **⚠️ 주의**: 8번 Prerequisite Checks에서 **Swap Size**, **compat-libcap1** 같은 경고가 나오는 것은 정상이다(OL8 + 19.3 조합). **Ignore All**을 체크하고 넘어가면 `[INS-13016]` 확인 창이 뜨고 **Yes**. 경고가 아닌 **Failed**(빨간 ×)가 있으면 멈추고 내용을 확인한다.

> **ℹ️ 참고**: 7번에서 root 자동 실행이 실패(`[INS-32128]`)하면, 설치 진행 중 뜨는 창에 나온 두 스크립트를 **root 세션**에서 순서대로 실행한 뒤 OK: `/u01/app/oraInventory/orainstRoot.sh` → `/u01/app/oracle/product/19.0.0.0/dbhome_1/root.sh`

---

### 20. 엔진 설치 확인

**목표**: `oracle` 실행 파일이 제대로 링크됐는지, 인벤토리에 등록됐는지 본다.

🔶 **dbts93: oracle $**
```bash
ls -l $ORACLE_HOME/bin/oracle
find $ORACLE_HOME/bin -type f -size 0 ! -name tnnfg ! -name '*0'
opatch lspatches
cat /etc/oraInst.loc
```

> **✅ 성공**: `-rwsr-s--x 1 oracle oinstall 4xxxxxxxx … oracle`(수백 MB), `find` 결과 **없음**, `29517242;Database Release Update : 19.3.0.0.190416` 등, `inventory_loc=/u01/app/oraInventory`

- **`bin/oracle` 크기**: Rocky 9 실습에서 링크가 실패해 0바이트였던 파일(05번). OL8에서는 정상이어야 한다.
- **`! -name tnnfg`, `! -name '*0'`**: `tnnfg`는 원래 0바이트인 정상 파일. `oklist0`, `okinit0`, `okdstry0`, `rawutl0`처럼 이름이 0으로 끝나는 파일은 설치 중 재링크(relink)가 새 실행 파일을 만들기 전에 옛 파일을 옮겨 둔 백업이라 0바이트여도 정상(2026-10-30 8.10 실행에서 이 4개가 0바이트로 나왔고, 이후 DB 생성, 기동, 재부팅 점검이 모두 정상이었다).

**💬 질문 대비**

- **Q. `oracle` 실행 파일이 왜 그렇게 큰가?** Oracle 서버 프로세스와 백그라운드 프로세스(PMON, DBWn, LGWR …)가 전부 이 실행 파일 하나다. 같은 파일이 이름만 바꿔 여러 번 뜬다. 설치 때 OS 라이브러리와 '링크'해서 만들어지므로, 링크가 실패하면 0바이트가 된다(그림책 2장).

---

## E. Oracle Patch: 19.25 RU (zip이 있을 때만)

*교재 68~69p: OPatch 교체, RU 적용. 원본 zip이 없으면 F로 건너뛴다*

### 21. OPatch 최신으로 교체

**목표**: 19.3에 들어 있는 OPatch(12.2.0.1.17)를 최신(12.2.0.1.4x)으로 바꾼다.

🔶 **dbts93: oracle $**
```bash
opatch version
mv $ORACLE_HOME/OPatch $ORACLE_HOME/OPatch.old
unzip -q /work/media/p6880880_190000_Linux-x86-64.zip -d $ORACLE_HOME
opatch version
```

> **✅ 성공**: 처음 `OPatch Version: 12.2.0.1.17` → 마지막 `12.2.0.1.4x` 이상

---

### 22. RU 19.25 적용

**목표**: Patch 36912597(Database Release Update 19.25.0.0.241015)을 DB를 만들기 **전에** 엔진에 적용한다.

🔶 **dbts93: oracle $**
```bash
cd /work/media
unzip -q p36912597_190000_Linux-x86-64.zip
cd 36912597
opatch prereq CheckConflictAgainstOHWithDetail -ph ./
opatch apply
opatch lspatches
```

> **✅ 성공**: prereq `Prereq "checkConflictAgainstOHWithDetail" passed.`, apply 중 질문 두 번 `y`, 마지막 `36912597;Database Release Update : 19.25.0.0.241015 (36912597)` (교재 69p와 같음)

- **DB 만들기 전에**: 엔진만 있을 때 패치하면 DBCA가 19.25 기준으로 DB를 만든다. DB가 있는 상태에서 패치하면 `datapatch`로 DB 안의 딕셔너리도 따로 올려야 한다.
- **prereq 먼저**: 이미 설치된 패치와 충돌하는지 실제 적용 전에 확인(교재 69p).

**💬 질문 대비**

- **Q. RU가 뭔가? 왜 올리나?** Release Update. 분기마다 나오는 보안, 버그 수정 묶음이다. 19.3은 2019년 첫 버전이라 보안 패치가 하나도 없고, OL 8.8의 UEK7 커널은 19.21 이상에서 Oracle이 지원한다. 그래서 19.25를 적용하면 '지원 조합'이 된다.

---

## F. Oracle DB 생성: DBCA

*교재 70~85p: CDB orcl + PDB pdb, /oradata, ASMM, KO16MSWIN949*

### 23. DBCA: 화면별 값

**목표**: Advanced 모드로 CDB `orcl` + PDB `pdb`를 `/oradata`에 ASMM, KO16MSWIN949로 만든다.

🔶 **dbts93: oracle $**
```bash
dbca
```

#### Step 4 of 14: Specify Database Identification Details

교재 73p는 Create as Container를 체크하지 않는다(non-CDB).

1. Global database name: **orcl**을 입력한다.
2. SID: **orcl**을 입력한다.
3. Create as Container database: 체크한다.
4. Use Local Undo tablespace for PDBs: 체크된 상태로 둔다.
5. Create a Container database with one or more PDBs: 선택한다.
6. Number of PDBs: **1**인지 확인한다.
7. PDB name: **pdb**를 입력한다.

#### Step 5 of 14: Select Database Storage Option (교재 74p)

1. Use following for the database storage attributes: 선택한다.
2. Database files storage type: **File System**인지 확인한다.
3. Database files location: 기본값 {ORACLE_BASE}/oradata/… 를 지우고 **/oradata/{DB_UNIQUE_NAME}**을 직접 입력한다.

#### Step 9 of 14: Specify Configuration Options, Memory 탭 (교재 78p)

1. **Memory** 탭을 연다.
2. Use Automatic Shared Memory Management: 선택한다.
3. SGA size: **1152  MB**를 입력한다.
4. PGA size: **384  MB**를 입력한다.
5. 맨 아래 Use Automatic Memory Management: 고르지 않는다.

#### Step 9 of 14: Specify Configuration Options, Character sets 탭 (교재 79p)

1. **Character sets** 탭을 연다.
2. Choose from the list of character sets: 선택한다.
3. Database character set: **KO16MSWIN949 - MS Windows Code Page 949 Korean**을 고른다.
4. National character set: **AL16UTF16 - Unicode UTF-16 Universal character set**인지 확인한다.
5. Default language: **American**인지 확인한다.
6. Default territory: **United States**인지 확인한다.

| # | 화면 | 할 것 | 교재 |
|---|---|---|---|
| 1 | Database Operation | **Create a database** | 70p |
| 2 | Creation Mode | **Advanced configuration** | 71p |
| 3 | Deployment Type | Oracle Single Instance database, **General Purpose or Transaction Processing** | 72p |
| 4 | Database Identification | Global database name `orcl`, SID `orcl`, **Create as Container database** 체크, PDB 1개, PDB name `pdb` | 73p (non-CDB) |
| 5 | Storage Option | **Use following for the database storage attributes**, File System, 위치 `/oradata/{DB_UNIQUE_NAME}` | 74p |
| 6 | Fast Recovery Option | 둘 다 **체크 안 함** (아카이브는 26단계에서 SQL로) | 75p |
| 7 | Network Configuration | **Create a new listener**, 이름 `LISTENER`, 포트 `1521` | 76p |
| 8 | Data Vault Option | 아무것도 체크 안 함 | 77p |
| 9 | Configuration Options | Memory: **ASMM** SGA `1152` MB, PGA `384` MB / Character sets: **KO16MSWIN949**, National `AL16UTF16` | 78~79p |
| 10 | Management Options | EM Express, Cloud Control **둘 다 체크 해제** | 80p |
| 11 | User Credentials | **Use the same administrative password**, `<비밀번호>` | 81p |
| 12 | Creation Option | **Create database** 체크만 | 82p |
| 13 | Summary | 값 확인 → **Finish** | 83p |
| 14~15 | Progress, Finish | 20~40분 → 완료 창 **Close** | 84~85p |

> **⚠️ 주의**: **5번 Storage가 가장 큰 함정.** 기본값 `{ORACLE_BASE}/oradata/{DB_UNIQUE_NAME}`(= `/u01/app/oracle/oradata/ORCL`)를 그대로 두면 데이터 파일이 50GB `/u01`에 생기고 100GB `/oradata` 디스크는 비어 남는다. 칸을 지우고 `/oradata/{DB_UNIQUE_NAME}`을 직접 입력한다.

> **⚠️ 주의**: **4번 Global database name**에 `orcl.localdomain`처럼 도메인이 자동으로 붙으면 `.localdomain`을 지우고 `orcl`만 남긴다. 그대로 두면 `db_domain=localdomain`이 생겨 서비스 이름이 `pdb.localdomain`이 되고, 25단계 tnsnames(`SERVICE_NAME = pdb`)와 DBeaver 접속이 `ORA-12514`로 실패한다(2026-10-30 8.10 수동 설치에서 Summary로 발견). Summary에 `db_domain` 줄이 없어야 한다.

> **⚠️ 주의**: **9번 Memory**를 기본값(Automatic Memory Management)으로 두면 `memory_target`이 생겨 27단계 HugePages를 쓸 수 없다(이전 실습에서 Free가 Total과 같게 남았다). 반드시 **Use Automatic Shared Memory Management**를 고른다.

> **ℹ️ 참고**: 11번에서 `[DBT-06208] The 'SYS' password entered does not conform to the Oracle recommended standards` 경고가 뜰 수 있다(비밀번호에 'oracle'이 들어감). 실습용이므로 **Yes**로 진행한다.

- **CDB + PDB**: 19c부터 Oracle 권장 구조. 그림책 25장, SQL 실습 가이드(15번)가 이 구조로 되어 있다. 교재 73p는 non-CDB.
- **SGA 1152 / PGA 384**: VM 메모리 4GB의 약 37%. 나머지는 OS, 서버 프로세스 몫. 1152MB = 2MB × 576이라 HugePages 계산이 깔끔하다.
- **KO16MSWIN949**: 교재 20p 계획값. 한글을 2바이트로 저장하는 확장 완성형. 자동판(dbts94)은 AL32UTF8이라 두 VM을 비교해 볼 수 있다.
- **EM Express 끔**: 교재 80p. 실습은 SQL*Plus, DBeaver로 한다.

---

### 24. DB 확인, PDB 자동 OPEN

**목표**: 인스턴스, CDB, PDB 상태를 보고, 재시작해도 PDB가 열리도록 상태를 저장한다.

🔶 **dbts93: oracle $**
```bash
ls $ORACLE_HOME/dbs/ | grep orcl
ls /oradata/ORCL/
ss
```

🗄️ **SQL*Plus: sys as sysdba**
```sql
select instance_name, status, version_full from v$instance;
select name, cdb, log_mode from v$database;
show pdbs
alter pluggable database all open;
alter pluggable database all save state;
show parameter memory_target
show parameter sga_target
exit
```

> **✅ 성공**: `spfileorcl.ora`(소문자), `/oradata/ORCL/`에 `system01.dbf`, `control01.ctl`, `redo01.log` 등, `orcl OPEN 19.x`, `ORCL YES NOARCHIVELOG`, `PDB READ WRITE`, `memory_target 0`, `sga_target 1152M`

- **`save state`**: 기본으로 PDB는 CDB가 재시작되면 MOUNTED로 남는다 → `ORA-01109: database not open`(05번). 현재 OPEN 상태를 기억시킨다.
- **`memory_target 0` 확인**: 0이 아니면 AMM으로 만들어진 것이다. 27단계 전에 `alter system set memory_target=0 scope=spfile;` 등으로 고쳐야 한다.

**💬 질문 대비**

- **Q. `ls /oradata/ORCL`이 왜 대문자인가? SID는 소문자인데.** `{DB_UNIQUE_NAME}` 자리에는 DB 이름이 대문자로 들어간다. 인스턴스(SID)와 파일 이름(`spfileorcl.ora`)은 소문자, 데이터 파일 폴더는 대문자다. 그래서 `ORACLE_SID`를 반드시 소문자로 둔다.

---

## G. 네트워크 파일, 원격 접속

*교재 86~88p: listener.ora, tnsnames.ora, DBeaver*

### 25. listener.ora, tnsnames.ora, 접속 시험

**목표**: 리스너에 정적 등록을 더하고, 접속 별칭을 만든 뒤 VM 안, PC에서 PDB로 접속해 본다.

🔶 **dbts93: oracle $**
```bash
cd $ORACLE_HOME/network/admin
cat listener.ora
cat >> listener.ora <<'EOF'

SID_LIST_LISTENER =
  (SID_LIST =
    (SID_DESC = (SID_NAME = orcl)(ORACLE_HOME = /u01/app/oracle/product/19.0.0.0/dbhome_1))
  )
EOF
cat tnsnames.ora
cat >> tnsnames.ora <<'EOF'
ORCL = (DESCRIPTION = (ADDRESS = (PROTOCOL = TCP)(HOST = dbts93)(PORT = 1521)) (CONNECT_DATA = (SERVICE_NAME = orcl)))
PDB  = (DESCRIPTION = (ADDRESS = (PROTOCOL = TCP)(HOST = dbts93)(PORT = 1521)) (CONNECT_DATA = (SERVICE_NAME = pdb)))
EOF
lsnrctl reload
lsnrctl status | grep -E 'Listening|Service'
echo "select sys_context('USERENV','CON_NAME') from dual;" | sqlplus -s system/<비밀번호>@PDB
```

> **⚠️ 주의**: tnsnames.ora는 **`>>`(덧붙이기)**로 쓴다. DBCA가 이 파일에 `LISTENER_ORCL` 별칭을 만들어 두고 `local_listener=LISTENER_ORCL`로 쓰는데, `>`로 덮어쓰면 별칭이 사라져 DB 재기동 후 리스너에 `pdb` 서비스가 등록되지 않는다(2026-10-30 수동 설치에서 겪었고, 29단계 check.sh FAIL로 발견했다).

> **✅ 성공**: `listener.ora`에 DBCA가 만든 `(HOST = dbts93)(PORT = 1521)`, status에 `Service "orcl"`, `Service "pdb"`, 마지막 줄 결과 `PDB`

#### DBeaver: Connect to a database, Oracle 연결 설정

SID가 아니라 Service Name으로 접속한다.

1. PC의 DBeaver에서 **새 연결 → Oracle**을 고른다.
2. Connection type: Basic을 선택한다.
3. Host: `192.168.10.93`을 입력한다.
4. Port: `1521`을 입력한다.
5. Database: `pdb`를 입력하고, 바로 아래 종류는 **Service Name**을 고른다.
6. Authentication: **Oracle Database Native**인지 확인한다.
7. Username: `system`인지 확인한다.
8. Password: `<비밀번호>`인지 확인한다.
9. **연결 테스트**를 누른다.

> **📘 교재와 다름**: 교재 87p의 tnsnames는 `(SID = ORCL)`로 접속한다. CDB에서 PDB에 들어가려면 SID가 아니라 **SERVICE_NAME**(`pdb`)으로 접속해야 한다. 교재 88p의 `SQLNET.ALLOWED_LOGON_VERSION_*=10`은 옛 클라이언트용이라 넣지 않았다(DBeaver는 최신 JDBC).

- **정적 등록(SID_LIST)**: DB가 내려가 있어도 리스너가 `orcl`을 안다 → 원격에서 접속해 STARTUP 같은 관리가 가능(교재 86p).
- **`lsnrctl reload`**: 리스너를 끄지 않고 설정만 다시 읽는다.
- **DBeaver 실패 시**: `ORA-12541`(리스너 없음)이면 리스너를 기동하고, `ORA-12514`(서비스 모름)이면 `alter system register;`, 연결 시간 초과면 14단계 방화벽을 본다.

**💬 질문 대비**

- **Q. 리스너가 하는 일은?** 처음 연결 요청만 받아 서버 프로세스를 하나 만들어 이어 주고 빠진다. 이후 SQL은 클라이언트와 전담 서버 프로세스가 직접 주고받는다. 그래서 연결된 뒤에는 리스너가 죽어도 기존 세션은 끊기지 않는다(그림책 12장).

---

## H. 운영 설정

*ARCHIVELOG, HugePages(교재 89~93p), 재부팅 자동 기동*

### 26. ARCHIVELOG 모드

**목표**: 꽉 찬 리두 로그를 `/backup/arch`에 보관하도록 바꾼다.

🗄️ **SQL*Plus: sys as sysdba (oracle $ 에서 ss)**
```sql
archive log list
alter system set log_archive_dest_1='LOCATION=/backup/arch' scope=spfile;
shutdown immediate
startup mount
alter database archivelog;
alter database open;
alter system switch logfile;
archive log list
host ls -l /backup/arch
```

> **✅ 성공**: 처음 `No Archive Mode` → 마지막 `Archive Mode`, `Archive destination /backup/arch`, `ls`에 `1_N_xxxxxxxx.dbf` 파일 1개 이상

- **MOUNT에서 바꾸는 이유**: 로그 모드는 컨트롤 파일에 기록되는데, DB가 OPEN이면 바꿀 수 없다. 컨트롤 파일만 열린 MOUNT 단계에서 바꾼다(그림책 26장).
- **`switch logfile`**: 리두 그룹을 강제로 넘겨 아카이브 파일이 실제로 생기는지 바로 확인한다.

**💬 질문 대비**

- **Q. NOARCHIVELOG면 무엇을 잃나?** 온라인 리두는 그룹 세 개를 돌려 쓰며 덮어쓴다. 아카이브가 없으면 백업 시점까지만 복구할 수 있다. ARCHIVELOG면 백업 + 아카이브 + 온라인 리두로 장애 직전까지 복구(완전 복구, PITR)가 된다(그림책 20, 29장).

---

### 27. HugePages

**목표**: SGA를 2MB 고정 페이지에 올린다. 교재 89~93p 순서에 계산 방법과 그룹 설정을 보탠다.

**① 필요한 페이지 수 계산**: DB가 켜진 상태에서 Oracle이 잡은 공유 메모리 크기로 계산한다.

🧑‍💻 **dbts93: root #**
```bash
ipcs -m | awk '$3=="oracle"{print $5}'
N=$(ipcs -m | awk '$3=="oracle"{n+=int($5/2097152)+1} END{print n}'); echo "vm.nr_hugepages = $N"
printf 'vm.nr_hugepages = %s\nvm.hugetlb_shm_group = 54321\n' "$N" > /etc/sysctl.d/99-oracle-hugepages.conf
cat /etc/sysctl.d/99-oracle-hugepages.conf
```

> **✅ 성공**: 첫 줄에 공유 메모리 세그먼트 크기들(합계 약 1.2GB), `vm.nr_hugepages = 58x` 정도

> **⚠️ 주의**: 첫 줄에 아무것도 안 나오거나 합계가 수 MB뿐이면 DB가 **AMM**(`/dev/shm` 사용)이다. 24단계의 `memory_target`부터 고친다.

**② use_large_pages=ONLY → DB 정지** (교재 91~92p 6, 7번)

🗄️ **SQL*Plus: sys as sysdba**
```sql
alter system set use_large_pages=ONLY scope=spfile;
shutdown immediate
```

**③ 커널에 예약 → 확인** (교재 92p 8, 9번)

🧑‍💻 **dbts93: root #**
```bash
sysctl -p /etc/sysctl.d/99-oracle-hugepages.conf
grep HugePages_ /proc/meminfo
```

> **✅ 성공**: `HugePages_Total`과 `HugePages_Free`가 둘 다 위에서 계산한 N

> **⚠️ 주의**: Total이 N보다 작으면 메모리 조각 때문에 덜 잡힌 것이다(05번). `echo 1 > /proc/sys/vm/compact_memory` 후 `sysctl -p …`를 다시 하거나, VM을 재부팅하면 부팅 때 먼저 잡혀서 해결된다.

**④ DB 기동 → 실제로 쓰는지 확인** (교재 93p 10번)

🗄️ **SQL*Plus: sys as sysdba**
```sql
startup
show parameter use_large_pages
exit
```

🧑‍💻 **dbts93: root #**
```bash
grep HugePages_ /proc/meminfo
```

> **✅ 성공**: `use_large_pages ONLY`, `HugePages_Free`가 `Total`보다 **확실히 작다**(SGA가 점유 중)

- **`vm.hugetlb_shm_group = 54321`**: HugePages로 공유 메모리를 만들 수 있는 그룹(oinstall gid). 없으면 `ORA-27125`(05번). 교재 방식(dba로 재생성)이면 54322다.
- **ONLY**: HugePages를 못 잡으면 아예 기동하지 않는다 → '조용히 안 쓰고 넘어감'을 막는다(교재 91p).
- **sysctl.d 파일**: 교재는 `/etc/sysctl.conf`에 추가. preinstall이 `/etc/sysctl.d/`를 쓰므로 같은 곳에 따로 두면 무엇을 바꿨는지 한눈에 보인다.
- **memlock**: preinstall이 oracle의 memlock 한도를 RAM의 약 90%로 잡아 둔다(`ulimit -l`로 확인). SGA보다 커야 한다.

**💬 질문 대비**

- **Q. HugePages를 왜 쓰나?** 4KB 페이지로 1.1GB SGA를 관리하면 페이지 표 항목이 수십만 개이고 프로세스마다 따로 가진다. 2MB 페이지면 수백 개로 줄어 메모리와 CPU(TLB 미스)가 절약되고, 스왑되지 않게 고정된다. 대신 AMM과는 같이 못 쓴다(그림책 8장).

---

### 28. 재부팅해도 자동 기동: oratab + systemd

**목표**: VM이 켜지면 리스너, DB가 저절로 올라오게 한다.

🧑‍💻 **dbts93: root #**
```bash
sed -i 's/^orcl:\(.*\):N$/orcl:\1:Y/' /etc/oratab
grep ^orcl /etc/oratab
cat > /etc/systemd/system/oracle-db.service <<'EOF'
[Unit]
Description=Oracle Database orcl and Listener
After=network-online.target local-fs.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
User=oracle
Group=oinstall
Environment=ORACLE_HOME=/u01/app/oracle/product/19.0.0.0/dbhome_1
ExecStart=/bin/bash -c '/u01/app/oracle/product/19.0.0.0/dbhome_1/bin/dbstart /u01/app/oracle/product/19.0.0.0/dbhome_1'
ExecStop=/bin/bash -c '/u01/app/oracle/product/19.0.0.0/dbhome_1/bin/dbshut /u01/app/oracle/product/19.0.0.0/dbhome_1'
TimeoutStartSec=600
TimeoutStopSec=600
LimitMEMLOCK=infinity
LimitNOFILE=65536
LimitNPROC=16384

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable oracle-db
```

지금 손으로 띄운 DB, 리스너를 내리고 systemd로 다시 올려 서비스가 제대로 동작하는지 본다.

🔶 **dbts93: oracle $**
```bash
echo 'shutdown immediate' | sqlplus -s / as sysdba
lsnrctl stop
```

🧑‍💻 **dbts93: root #**
```bash
systemctl start oracle-db
systemctl status oracle-db --no-pager | head -5
grep HugePages_Free /proc/meminfo
```

> **✅ 성공**: `grep` 결과 `orcl:/u01/…/dbhome_1:Y`, `Active: active (exited)`, HugePages_Free가 다시 Total보다 작다

- **oratab의 Y**: `dbstart`는 `/etc/oratab`에서 `Y`로 표시된 DB만 올린다.
- **`dbstart $ORACLE_HOME`**: 인자로 홈을 주면 그 홈의 리스너도 같이 올린다.
- **`LimitMEMLOCK=infinity`**: systemd가 띄운 프로세스에는 `/etc/security/limits.d`의 memlock이 적용되지 않는다. 빠뜨리면 재부팅 뒤에만 `use_large_pages=ONLY` 기동이 실패한다.
- **`/bin/bash -c '…dbstart…'`**: SELinux가 켜져 있으면 systemd가 `/u01`의 `dbstart`를 직접 실행하지 못해 `status=203/EXEC Permission denied`가 난다(2026-10-28 자동판 dbts94에서 실측). 이 가이드는 SELinux를 끄지만, 나중에 켜도 그대로 동작하도록 셸을 거친다.
- **`Type=oneshot` + `RemainAfterExit`**: `dbstart`는 DB를 띄우고 끝나는 스크립트다. 끝난 뒤에도 서비스를 '실행 중'으로 보고, 종료 시 `dbshut`을 불러 정상 종료한다.

---

## I. 검증: 설치 직후와 재부팅 후

*check.sh 17개 항목, 재부팅 테스트, 기록*

### 29. 점검 스크립트

**목표**: 자동판과 같은 `check.sh`로 17개 항목을 한 번에 확인한다.

MobaXterm SFTP로 `D:\vagrant\oracle19c\scripts\check.sh`를 `/work/media/`에 올린다.

🧑‍💻 **dbts93: root #**
```bash
sed -i 's/\r$//' /work/media/check.sh
bash /work/media/check.sh | tee /backup/check_install.txt
```

> **✅ 성공**: 마지막 줄 `== 결과: PASS 17 / FAIL 0 ==` (firewalld가 꺼져 있으면 방화벽 항목을 건너뛰어 PASS 16. 판정 기준은 **FAIL 0**)

| 구역 | 항목 |
|---|---|
| 1. 디스크 | `/u01`, `/oradata`, `/backup` 마운트 |
| 2. OS | THP 꺼짐, `hugetlb_shm_group=54321`, `/etc/hosts` |
| 3. 소프트웨어 | `bin/oracle` 크기, 패치 목록(정보) |
| 4. 서비스, 리스너 | `oracle-db` 등록, 실행, 리스너에 `pdb` 서비스 |
| 5. DB | 인스턴스 OPEN, PDB READ WRITE, ARCHIVELOG, `memory_target=0` |
| 6. HugePages | Free < Total |
| 7. 외부 접속 | 1521 대기, 방화벽 1521 허용 |

> **ℹ️ 참고**: `sed`는 Windows에서 파일을 열어 저장했다면 생기는 줄 끝 문자(CR)를 지운다. 손대지 않았다면 아무것도 바뀌지 않는다.

---

### 30. 재부팅 테스트

**목표**: 아무것도 손대지 않고 재부팅한 뒤에도 17개가 모두 PASS인지 본다. 이것이 이 가이드의 최종 합격선이다.

🧑‍💻 **dbts93: root #**
```bash
reboot
```

2분 뒤 root 세션을 다시 연다.

🧑‍💻 **dbts93: root #**
```bash
bash /work/media/check.sh | tee /backup/check_reboot.txt
```

> **✅ 성공**: 설치 직후와 같은 PASS 수, `FAIL 0`, PC의 DBeaver에서 `pdb` 접속이 다시 된다

두 결과 파일을 SFTP로 PC에 내려받아 포트폴리오 증거로 보관한다. 다 끝나면 VirtualBox 스냅샷 `I-완료`.

**💬 질문 대비**

- **Q. 설치가 끝났다는 걸 어떻게 증명하나?** 같은 점검 스크립트를 설치 직후와 재부팅 후에 두 번 돌려 모두 PASS인 결과를 남겼다. 재부팅 후가 중요한 이유는 자동 기동, HugePages 예약, PDB 상태 저장처럼 '한 번 손으로 띄울 때는 안 보이는' 설정이 그때 처음 검증되기 때문이다.

---

## Z. 막힐 때 먼저 볼 것

*이전 실습(05번)에서 실제로 겪은 것 중 이 순서에서 나올 수 있는 것*

### Z. 증상 → 원인 → 해결

- **5단계**: 설치가 질문 없이 끝나 버린다
  - 원인: VirtualBox 무인 설치
  - 해결: VM을 삭제하고 2단계에서 Skip Unattended를 체크한다
- **9~10단계**: `dnf`, ping이 `Could not resolve host`
  - 원인: enp0s3에 게이트웨이 → 가짜 기본 경로
  - 해결: `nmcli connection modify enp0s3 ipv4.gateway ""` → `nmcli connection up enp0s3`
- **10단계**: enp0s8에 IP가 없다
  - 원인: 설치 때 어댑터 2를 OFF로 뒀거나, 설치 화면에서 ON 했어도 autoconnect=no로 저장됐다(8.10에서 실제로 겪었다)
  - 해결: `nmcli connection modify enp0s8 connection.autoconnect yes` → `nmcli connection up enp0s8`
- **15단계**: `lvcreate` 공간 부족
  - 원인: PV 메타데이터 몫
  - 해결: 마지막 LV를 `-l 100%FREE`로
- **18단계**: `DISPLAY`가 비어 있고 창이 안 뜬다
  - 원인: xauth 설치 전 세션, `su`로 전환
  - 해결: 세션 새로 열기, oracle로 직접 로그인
- **19단계**: `[INS-08101] clientSupportedOSCheck`
  - 원인: 19.3이 OL8을 모른다
  - 해결: `export CV_ASSUME_DISTID=OEL7.8` 후 다시 실행
- **19단계**: `[INS-32128]` root 스크립트 자동 실행 실패
  - 원인: root 비밀번호 틀림 등
  - 해결: root 세션에서 `orainstRoot.sh` → `root.sh` 수동 실행
- **23단계**: DBCA `[DBT-06208]` 비밀번호 경고
  - 원인: 권장 규칙(대문자, 'oracle' 포함)
  - 해결: 경고이므로 Yes. 거부되면 대문자, 숫자 섞기
- **23단계**: DBCA `No valid IP Address returned for the host`
  - 원인: `/etc/hosts`에 dbts93 없음
  - 해결: 12단계
- **23단계**: DBCA 화면이 `Copying database files 8%`에 몇십 분째 멈춘다
  - 원인: DB 생성은 끝났는데 파일 복사 단계의 `rman` 프로세스가 종료되지 않아 DBCA가 백그라운드 작업 완료를 기다린다(2026-10-30 8.10 수동 설치에서 겪었고, 원인은 추론이다)
  - 해결: 창은 그대로 두고 확인: `ls -lt $ORACLE_BASE/cfgtoollogs/dbca/orcl` 마지막에 `postPDBCreation.log`, alert log `Pluggable database PDB opened read write`, `show pdbs`에 PDB READ WRITE, `grep orcl /etc/oratab` → 모두 있으면 남은 `rman` kill → DBCA Close(안 닫히면 dbca java kill). trace의 `setting Ignorable/Fatal Error: ORA-…`는 에러가 아니라 목록 등록이다
- **24단계**: `connected to an idle instance`, `ORA-01078`, `LRM-00109`
  - 원인: `ORACLE_SID` 대문자
  - 해결: `.bash_profile`을 `orcl`로 → `grep ORACLE_SID ~/.bash_profile`로 실제로 바뀌었는지 확인
- **24단계**: `ORA-65096: invalid common user or role name`
  - 원인: CDB$ROOT에서 일반 사용자 생성
  - 해결: `alter session set container = pdb;` 후 생성
- **25단계**: `ORA-12541: TNS:no listener`
  - 원인: 리스너가 안 떠 있다
  - 해결: oracle $에서 `lsnrctl start` (sqlplus 안에서 치면 SP2-0734)
- **25단계**: `ORA-12514`
  - 원인: 리스너가 서비스를 아직 모른다
  - 해결: `alter system register;`
- **25, 29단계**: 재기동 뒤 `lsnrctl status`에 `pdb` 없음, check.sh `리스너에 pdb 서비스 없음`
  - 원인: tnsnames.ora를 `>`로 덮어써 DBCA가 만든 `LISTENER_ORCL` 별칭이 사라지고, `local_listener`를 못 풀어 동적 등록이 실패한다
  - 해결: `grep -c LISTENER_ORCL tnsnames.ora`가 0이면 `echo 'LISTENER_ORCL = (ADDRESS = (PROTOCOL = TCP)(HOST = dbts93.localdomain)(PORT = 1521))' >> tnsnames.ora` → SQL> `alter system set local_listener='LISTENER_ORCL' scope=both;` → `alter system register;` (값을 다시 설정해야 별칭을 새로 푼다. register만으로는 반영되지 않는다)
- **27단계**: Free = Total (HugePages를 안 쓴다)
  - 원인: AMM(`memory_target`)
  - 해결: ASMM으로: `memory_target=0`, `memory_max_target=0`, `sga_target=1152M` scope=spfile 후 재기동
- **27단계**: `ORA-27125`
  - 원인: `hugetlb_shm_group` 없음
  - 해결: 27단계 ①의 sysctl 파일 확인
- **27단계**: `ORA-27102`, `ORA-27138`
  - 원인: HugePages 부족, 조각
  - 해결: `compact_memory` 후 재적용 또는 재부팅
- **30단계**: 재부팅 후 PDB `MOUNTED`, `ORA-01109`
  - 원인: save state를 하지 않았다
  - 해결: `alter pluggable database all open;` → `… save state;`
- **30단계**: 재부팅 후 DB가 안 뜬다
  - 원인: oratab N, 서비스 미등록, LimitMEMLOCK 누락
  - 해결: 28단계, `journalctl -u oracle-db`
- **28단계**: `oracle-db` `status=203/EXEC Permission denied`
  - 원인: SELinux가 라벨 없는(`unlabeled_t`) `/u01` 파일 실행을 막는다 (audit 로그 `avc: denied { execute }`)
  - 해결: `ExecStart=/bin/bash -c '…'` 형태 확인, `restorecon -R /u01 /oradata /backup`, `systemctl daemon-reload`
- **SQL**: 한글 식별자 `ORA-00911`
  - 원인: `NLS_LANG` 문자셋 ≠ 터미널(UTF-8)
  - 해결: `export NLS_LANG=AMERICAN_AMERICA.AL32UTF8`

로그 위치: 설치 `/u01/app/oraInventory/logs/`, DBCA `/u01/app/oracle/cfgtoollogs/dbca/orcl/`, DB `alert_orcl.log`(`t_dbalert`), 리스너 `/u01/app/oracle/diag/tnslsnr/dbts93/listener/trace/listener.log`, 서비스 `journalctl -u oracle-db`

