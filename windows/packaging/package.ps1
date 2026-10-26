# Stage the Flutter Windows release into a zip and, when Inno Setup is
# installed, a per-user installer. The Setup.exe is what the in-app updater runs.
param(
  [Parameter(Mandatory = $true)][string]$Version,
  [string]$RepoRoot = ""
)

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
  $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
}
Set-Location $RepoRoot

$releaseDir = Join-Path $RepoRoot "build\windows\x64\runner\Release"
$exePath = Join-Path $releaseDir "PocketBot.exe"
if (-not (Test-Path $exePath)) {
  throw "PocketBot.exe was not found in $releaseDir"
}

$stage = Join-Path $RepoRoot "build-output"
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
New-Item -ItemType Directory -Path $stage | Out-Null
Copy-Item (Join-Path $releaseDir "*") -Recurse -Destination $stage

foreach ($dll in @(
    "$env:SystemRoot\System32\vcruntime140.dll",
    "$env:SystemRoot\System32\vcruntime140_1.dll",
    "$env:SystemRoot\System32\msvcp140.dll"
  )) {
  if (Test-Path $dll) {
    Copy-Item $dll -Destination $stage
  } else {
    Write-Warning "VC++ runtime DLL not found: $dll"
  }
}

Set-Content -Path (Join-Path $stage "version.txt") -Value $Version -Encoding ascii
$readme = @(
  "PocketBot for Windows",
  "",
  "1. Extract this zip to any folder, or run the Setup exe from the same release.",
  "2. Run PocketBot.exe.",
  "",
  "Version: $Version"
) -join "`r`n"
Set-Content -Path (Join-Path $stage "README.txt") -Value $readme -Encoding utf8

Add-Type -AssemblyName System.IO.Compression.FileSystem
$zipName = "PocketBot-Windows-$Version.zip"
$zipPath = Join-Path $RepoRoot $zipName
if (Test-Path $zipPath) { Remove-Item $zipPath }
[System.IO.Compression.ZipFile]::CreateFromDirectory(
  (Resolve-Path $stage).Path,
  $zipPath,
  [System.IO.Compression.CompressionLevel]::Optimal,
  $false
)
Write-Host "Wrote $zipPath"

$iscc = @(
  "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
  "$env:ProgramFiles\Inno Setup 6\ISCC.exe",
  "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe"
) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1

if (-not $iscc) {
  Write-Warning "Inno Setup was not found. The zip was created without an installer."
  return
}

$setupBase = "PocketBot-Windows-$Version-Setup"
$iss = Join-Path $PSScriptRoot "pocketbot.iss"
# ISCC resolves relative /D paths from the .iss file, and its preprocessor
# treats "\" as an escape. Pass absolute paths with escaped backslashes.
$stageIss = ((Resolve-Path $stage).Path).Replace('\', '\\')
$outIss = ((Resolve-Path $RepoRoot).Path).Replace('\', '\\')
& $iscc `
  "/DAppVersion=$Version" `
  "/DSourceDir=$stageIss" `
  "/DOutputDir=$outIss" `
  "/DSetupBaseName=$setupBase" `
  $iss
if ($LASTEXITCODE -ne 0) {
  throw "Inno Setup failed with exit code $LASTEXITCODE"
}
Write-Host "Wrote $(Join-Path $RepoRoot "$setupBase.exe")"
