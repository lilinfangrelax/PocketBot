param(
  [switch]$KeepDb,
  [string]$Only
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$e2eDir = Join-Path $root 'build\e2e'
$mockSrc = Join-Path $e2eDir 'mock_agent_src'
$mockExe = Join-Path $e2eDir 'mock_acp_agent.exe'
$dbDir = Join-Path $e2eDir 'db'

New-Item -ItemType Directory -Force -Path $mockSrc | Out-Null
Copy-Item (Join-Path $PSScriptRoot 'mock_acp_agent.dart') (Join-Path $mockSrc 'mock_acp_agent.dart') -Force
@'
name: pocketbot_mock_acp_agent
environment:
  sdk: ">=3.0.0 <4.0.0"
'@ | Set-Content -Path (Join-Path $mockSrc 'pubspec.yaml') -Encoding utf8

Push-Location $mockSrc
try {
  dart pub get --offline | Out-Null
  dart compile exe mock_acp_agent.dart -o $mockExe | Out-Null
} finally {
  Pop-Location
}

if (-not $KeepDb) {
  Get-ChildItem -Path $dbDir -Filter 'pocket_bot.db*' -ErrorAction SilentlyContinue |
    Remove-Item -Force
}
New-Item -ItemType Directory -Force -Path $dbDir | Out-Null

$env:POCKETBOT_E2E_DB_DIR = $dbDir
$env:POCKETBOT_E2E_MOCK_AGENT = $mockExe
if ($KeepDb) {
  $env:POCKETBOT_E2E_KEEP_DB = '1'
} else {
  Remove-Item Env:POCKETBOT_E2E_KEEP_DB -ErrorAction SilentlyContinue
}
# Flutter 的本地调试 WebSocket 必须绕过系统代理。
$env:HTTP_PROXY = $null
$env:HTTPS_PROXY = $null
$env:ALL_PROXY = $null
$env:NO_PROXY = '127.0.0.1,localhost'

$tests = Get-ChildItem -Path (Join-Path $root 'integration_test') -Filter '*_test.dart' |
  Where-Object { -not $Only -or $_.Name -like "*$Only*" } |
  Sort-Object Name
if (-not $tests) {
  throw "没有匹配的集成测试：$Only"
}
foreach ($test in $tests) {
  flutter test $test.FullName -d windows
  if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
  }
}
exit 0
