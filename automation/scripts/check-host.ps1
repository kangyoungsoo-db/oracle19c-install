<#
  check-host.ps1 — vagrant up 전에 이 PC가 Oracle 19c 자동 설치를 돌릴 수 있는지 검사합니다.
  실행 (D:\vagrant\oracle19c 에서):
    powershell -ExecutionPolicy Bypass -File scripts\check-host.ps1
    powershell -ExecutionPolicy Bypass -File scripts\check-host.ps1 -SkipHash   # 설치 zip SHA256 계산(1~2분) 생략
  결과: [PASS] 통과 · [WARN] 돌아가지만 확인 필요 · [FAIL] 이대로는 실패. FAIL이 0이면 vagrant up 진행.
  이 파일은 UTF-8(BOM)로 저장되어 있어야 Windows PowerShell 5.1에서 한글이 깨지지 않습니다.
#>
param([switch]$SkipHash)

$ErrorActionPreference = 'SilentlyContinue'
$script:pass = 0; $script:warn = 0; $script:fail = 0
function Ok($m)   { Write-Host "  [PASS] $m" -ForegroundColor Green;  $script:pass++ }
function Wn($m)   { Write-Host "  [WARN] $m" -ForegroundColor Yellow; $script:warn++ }
function Ng($m)   { Write-Host "  [FAIL] $m" -ForegroundColor Red;    $script:fail++ }
function Sec($m)  { Write-Host "-- $m" -ForegroundColor Cyan }

# 이 스크립트 기준 경로 (scripts\ 의 한 칸 위 = 프로젝트, 두 칸 위 = media가 있는 폴더)
$Project = Split-Path -Parent $PSScriptRoot
$Media   = Join-Path (Split-Path -Parent $Project) 'media'
$ZipName = 'LINUX.X64_193000_db_home.zip'
$ZipSize = 3059705302
$ZipSha  = 'BA8329C757133DA313ED3B6D7F86C5AC42CD9970A28BF2E6233F3235233AA8D8'
$VmName  = 'dbts94'
$VmIpPrefix = '192.168.10.'

Write-Host "== Oracle 19c 자동 설치 사전 점검 $(Get-Date -Format 'yyyy-MM-dd HH:mm') · $env:COMPUTERNAME ==" -ForegroundColor Cyan
Write-Host "  프로젝트: $Project"
Write-Host "  설치 파일 폴더: $Media"

# ── 1. 프로그램 ─────────────────────────────────────────
Sec '1. 프로그램'
$vbox = $null
if ($env:VBOX_MSI_INSTALL_PATH) { $vbox = Join-Path $env:VBOX_MSI_INSTALL_PATH 'VBoxManage.exe' }
if (-not $vbox -or -not (Test-Path $vbox)) { $vbox = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe' }
if (Test-Path $vbox) {
  $vv = (& $vbox --version) -replace 'r\d+$', ''
  if ([version]($vv -replace '[^\d\.].*$', '') -ge [version]'7.0') { Ok "VirtualBox $vv" } else { Wn "VirtualBox $vv — 7.0 이상 권장 (검증 버전 7.2.14)" }
} else { Ng 'VirtualBox가 없습니다 — virtualbox.org에서 설치' }

$vg = (vagrant --version) 2>$null
if ($vg) {
  $gv = ($vg -replace 'Vagrant ', '').Trim()
  if ([version]$gv -ge [version]'2.4.0') { Ok "Vagrant $gv" } else { Wn "Vagrant $gv — 2.4 이상 권장 (검증 버전 2.4.9). VirtualBox 7.2는 최신 Vagrant가 필요할 수 있음" }
} else { Ng 'Vagrant가 없습니다 — vagrantup.com에서 설치 후 PowerShell을 새로 여세요' }

# ── 2. 하드웨어 ─────────────────────────────────────────
Sec '2. 하드웨어'
$cs  = Get-CimInstance Win32_ComputerSystem
$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
$ramGB = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
if ($ramGB -ge 12) { Ok "메모리 ${ramGB}GB (VM 4GB)" }
elseif ($ramGB -ge 8) { Wn "메모리 ${ramGB}GB — 동작은 하지만 다른 프로그램을 줄이세요 (VM 4GB)" }
else { Ng "메모리 ${ramGB}GB — VM에 4GB를 주기 어렵습니다. Vagrantfile VM_MEMORY와 vars.yml total_memory_mb를 함께 줄여야 함" }

if ($cs.HypervisorPresent) {
  Wn 'Hyper-V(또는 WSL2 · 메모리 무결성)가 켜져 있습니다 — VirtualBox가 느린 방식으로 동작해 설치가 오래 걸리거나 VM이 멈출 수 있음'
} elseif ($cpu.VirtualizationFirmwareEnabled) {
  Ok 'CPU 가상화(VT-x/AMD-V) 켜짐'
} else {
  Ng 'CPU 가상화가 꺼져 있습니다 — BIOS/UEFI에서 Intel VT-x 또는 AMD SVM을 켜세요'
}

$drive = (Get-Item $Project).PSDrive
$freeGB = [math]::Round($drive.Free / 1GB, 1)
if ($freeGB -ge 40) { Ok "$($drive.Name): 여유 ${freeGB}GB" }
elseif ($freeGB -ge 25) { Wn "$($drive.Name): 여유 ${freeGB}GB — 40GB 이상 권장 (박스 · VM · 디스크 3개)" }
else { Ng "$($drive.Name): 여유 ${freeGB}GB — 공간 부족" }

# ── 3. 설치 파일 ────────────────────────────────────────
Sec '3. 설치 파일'
$zip = Join-Path $Media $ZipName
if (Test-Path $zip) {
  $len = (Get-Item $zip).Length
  if ($len -ne $ZipSize) { Ng "$ZipName 크기 $len — 정상 $ZipSize (다운로드가 덜 됐거나 다른 파일)" }
  elseif ($SkipHash) { Ok "$ZipName 크기 일치 (SHA256 생략)" }
  else {
    Write-Host '  SHA256 계산 중 (1~2분)...'
    $h = (Get-FileHash $zip -Algorithm SHA256).Hash
    if ($h -eq $ZipSha) { Ok "$ZipName SHA256 일치" } else { Ng "$ZipName SHA256 불일치 — 다시 받으세요" }
  }
} else { Ng "$zip 이 없습니다 — oracle.com 19c Linux x86-64 ZIP을 받아 media 폴더에 두세요(Oracle 계정 필요)" }

$ru = Join-Path $Media 'p36912597_190000_Linux-x86-64.zip'
$op = Join-Path $Media 'p6880880_190000_Linux-x86-64.zip'
if ((Test-Path $ru) -and (Test-Path $op)) { Ok 'RU 19.25 + OPatch zip 있음 → 설치하면서 19.25 적용(지원 조합)' }
else { Write-Host '  [INFO] RU zip 없음 → base 19.3으로 설치 (동작은 하지만 OL8 UEK7에서는 Oracle 비지원 조합)' }

# ── 4. 네트워크 ─────────────────────────────────────────
Sec '4. 네트워크'
$clash = Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -like "$VmIpPrefix*" -and $_.InterfaceAlias -notlike '*VirtualBox*' }
if ($clash) { Ng ("이 PC의 실제 네트워크가 이미 192.168.10.x 대역을 씁니다 (" + ($clash.InterfaceAlias -join ', ') + ") — Vagrantfile의 VM_IP를 다른 대역으로 바꾸세요") }
else { Ok '192.168.10.x 대역 충돌 없음' }

foreach ($u in @('https://oracle.github.io/vagrant-projects/boxes/oraclelinux/8.json', 'https://yum.oracle.com/')) {
  try {
    $r = Invoke-WebRequest -Uri $u -Method Head -UseBasicParsing -TimeoutSec 15
    if ($r.StatusCode -eq 200) { Ok ("인터넷 접속 " + ([uri]$u).Host) } else { Wn ("$u 응답 " + $r.StatusCode) }
  } catch { Ng ("인터넷 접속 실패 " + ([uri]$u).Host + " — 학원 · 회사망 방화벽이나 프록시를 확인하세요") }
}

# ── 5. 이전 실행 흔적 ───────────────────────────────────
Sec '5. 이전 실행 흔적'
if (Test-Path $vbox) {
  $vms = & $vbox list vms
  if ($vms -match "`"$VmName`"") { Wn "VirtualBox에 이미 '$VmName' VM이 있습니다 — 새로 만들려면 vagrant destroy -f (또는 VirtualBox에서 삭제)" }
  else { Ok "'$VmName' VM 없음 (새로 만들 수 있음)" }
}
$vdis = Get-ChildItem (Join-Path $Project 'disks') -Filter *.vdi
if ($vdis -and -not ($vms -match "`"$VmName`"")) { Wn ('disks 폴더에 옛 디스크가 남아 있습니다 (' + ($vdis.Name -join ', ') + ') — 새 VM에 옛 DB가 붙습니다. 지우세요: Remove-Item disks\*.vdi') }
elseif (-not $vdis) { Ok 'disks 폴더 비어 있음' }

$boxes = (vagrant box list) 2>$null
if ($boxes -match 'oraclelinux/8\s+\(virtualbox, 8\.10\.700') { Write-Host '  [INFO] 박스 oraclelinux/8 (8.10.700) 받아 둠 — 내려받기 생략' }
else { Write-Host '  [INFO] 박스가 없어 처음 실행 때 약 1GB를 내려받습니다' }

# ── 결과 ────────────────────────────────────────────────
Write-Host ''
$color = if ($script:fail -gt 0) { 'Red' } elseif ($script:warn -gt 0) { 'Yellow' } else { 'Green' }
Write-Host "== 결과: PASS $($script:pass) / WARN $($script:warn) / FAIL $($script:fail) ==" -ForegroundColor $color
if ($script:fail -gt 0) { Write-Host '   FAIL을 먼저 해결한 뒤 vagrant up 하세요.'; exit 1 }
Write-Host '   vagrant up 을 실행해도 됩니다.'
exit 0
