# Loads repo-root .env and runs the @real feature
# features/zh-CN/真实远程Agent.feature.
# @integration features stay on the Mock ACP agent.
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$envFile = Join-Path $root '.env'
if (-not (Test-Path -LiteralPath $envFile)) {
  throw "缺少 $envFile。请复制 .env.example 并填入真实 SSH 主机。"
}

Get-Content -LiteralPath $envFile | ForEach-Object {
  $line = $_.Trim()
  if ($line -eq '' -or $line.StartsWith('#')) { return }
  $eq = $line.IndexOf('=')
  if ($eq -lt 1) { return }
  $name = $line.Substring(0, $eq).Trim()
  $value = $line.Substring($eq + 1).Trim()
  if (
    ($value.StartsWith('"') -and $value.EndsWith('"') -and $value.Length -ge 2) -or
    ($value.StartsWith("'") -and $value.EndsWith("'") -and $value.Length -ge 2)
  ) {
    $value = $value.Substring(1, $value.Length - 2)
  }
  Set-Item -Path "Env:$name" -Value $value
}

foreach ($name in @(
    'POCKETBOT_REAL_SSH_HOST',
    'POCKETBOT_REAL_SSH_PORT',
    'POCKETBOT_REAL_SSH_USER',
    'POCKETBOT_REAL_SSH_KEY_FILE'
  )) {
  $value = [Environment]::GetEnvironmentVariable($name)
  if ([string]::IsNullOrWhiteSpace($value)) {
    throw ".env 缺少 $name"
  }
}

$keyFile = $env:POCKETBOT_REAL_SSH_KEY_FILE
if (-not (Test-Path -LiteralPath $keyFile)) {
  throw "私钥文件不存在：$keyFile"
}

$dbDir = Join-Path $root 'build\e2e\real-db'
New-Item -ItemType Directory -Force -Path $dbDir | Out-Null
$env:POCKETBOT_E2E_DB_DIR = $dbDir

# The Flutter driver talks to the app over a localhost WebSocket. Keep any
# existing proxy for GitHub downloads, but do not send loopback through it.
$env:NO_PROXY = '127.0.0.1,localhost'
$env:no_proxy = '127.0.0.1,localhost'

Write-Host "真实 SSH 验收：$($env:POCKETBOT_REAL_SSH_USER)@$($env:POCKETBOT_REAL_SSH_HOST):$($env:POCKETBOT_REAL_SSH_PORT)"
Write-Host "数据库目录：$dbDir"

flutter test integration_test/manual/real_ssh_test.dart -d windows
exit $LASTEXITCODE
