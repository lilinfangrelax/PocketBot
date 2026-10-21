param(
  [string]$Feature = 'features\zh-CN\启动与底部导航.feature',
  [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

if (-not $SkipBuild) {
  flutter build windows --debug
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

$exe = Join-Path $root 'build\windows\x64\runner\Debug\pocket_bot.exe'
$dbDir = Join-Path $root 'build\e2e\db'
New-Item -ItemType Directory -Force -Path $dbDir | Out-Null
$env:POCKETBOT_E2E_DB_DIR = $dbDir
$app = Start-Process -FilePath $exe -WorkingDirectory $root -PassThru
$exitCode = 1
try {
  $attached = $false
  $attachOutput = ''
  for ($i = 0; $i -lt 30; $i++) {
    if ($app.HasExited) {
      throw "PocketBot 已退出（exit code $($app.ExitCode)），无法附加 UI 自动化。"
    }
    # Native stderr capture throws under 'Stop', so relax it for this attempt.
    $ErrorActionPreference = 'Continue'
    $attachOutput = teshi winapp attach --pid $app.Id 2>&1 | Out-String
    $attachCode = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    if ($attachCode -eq 0) {
      $attached = $true
      break
    }
    Start-Sleep -Seconds 1
  }
  if (-not $attached) {
    Write-Host $attachOutput
    throw "teshi winapp attach 在 30 秒内未成功（pid $($app.Id)）。"
  }
  teshi winapp snapshot | Out-Null
  if ($LASTEXITCODE -ne 0) {
    throw "teshi winapp snapshot 失败（exit code $LASTEXITCODE）。"
  }
  teshi check --feature $Feature --json
  if ($LASTEXITCODE -ne 0) {
    throw "teshi check 未通过（exit code $LASTEXITCODE），已跳过 replay。"
  }
  teshi winapp replay --feature $Feature --non-interactive --mode background
  $exitCode = $LASTEXITCODE
} finally {
  if (-not $app.HasExited) {
    Stop-Process -Id $app.Id -Force
  }
}
exit $exitCode
