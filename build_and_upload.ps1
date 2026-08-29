# PocketBot Build & Upload Script
# Run with: powershell -ExecutionPolicy Bypass -File build_and_upload.ps1
#
# Optional: set POCKETBOT_ARCHIVE_DIR to copy APK/Windows builds somewhere
# other than %USERPROFILE%\PocketBot-dist.

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $scriptDir
Write-Host "[DEBUG] Working directory: $scriptDir" -ForegroundColor Gray

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  PocketBot Build & Upload to OTA" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$version = "dev_$timestamp"
Write-Host "Version: $version"
Write-Host ""

$targetDir = $env:POCKETBOT_ARCHIVE_DIR
if ([string]::IsNullOrWhiteSpace($targetDir)) {
    $targetDir = Join-Path $env:USERPROFILE "PocketBot-dist"
}
$androidDir = "$targetDir\android"
$windowsDir = "$targetDir\windows"

New-Item -ItemType Directory -Force -Path "$androidDir\history" | Out-Null
New-Item -ItemType Directory -Force -Path "$windowsDir\history" | Out-Null

Write-Host "[DEBUG] Archive target: $targetDir" -ForegroundColor Gray
Write-Host ""

Write-Host "[1/4] Building APK..." -ForegroundColor Yellow
$flutterBuild = cmd /c "flutter build apk --release --build-name=$version 2>&1"
if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] Build failed" -ForegroundColor Red
    Write-Host $flutterBuild
    Read-Host "Press Enter to exit"
    exit 1
}
Write-Host "[OK] APK built successfully" -ForegroundColor Green
Write-Host ""

$apkPath = "build\app\outputs\flutter-apk\app-release.apk"
$versionedApkPath = "build\app\outputs\flutter-apk\pocketbot-$version.apk"

if (-not (Test-Path $apkPath)) {
    Write-Host "[ERROR] APK not found: $apkPath" -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

Write-Host "APK path: $apkPath" -ForegroundColor Gray
Write-Host ""

Write-Host "[2/4] Renaming APK to pocketbot-$version.apk..." -ForegroundColor Yellow
Move-Item -Path $apkPath -Destination $versionedApkPath -Force
Write-Host "[OK] APK renamed to pocketbot-$version.apk" -ForegroundColor Green
Write-Host ""

Write-Host "[3/4] Copying APK to archive..." -ForegroundColor Yellow
Copy-Item $versionedApkPath "$androidDir\history\pocketbot-android-$timestamp.apk" -Force
Copy-Item $versionedApkPath "$androidDir\pocketbot-android-latest.apk" -Force
Write-Host "[OK] APK copied" -ForegroundColor Green
Write-Host ""

Write-Host "[4/4] Building Windows..." -ForegroundColor Yellow
$winBuild = cmd /c "flutter build windows --release 2>&1"
if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] Windows build failed" -ForegroundColor Red
    Write-Host $winBuild
    Read-Host "Press Enter to exit"
    exit 1
}
Write-Host "[OK] Windows built successfully" -ForegroundColor Green

$winPath = "build\windows\x64\runner\Release"
$winLatestDir = "$windowsDir\latest"

Remove-Item -Recurse -Force $winLatestDir -ErrorAction SilentlyContinue
Copy-Item $winPath -Recurse -Destination $winLatestDir
Write-Host "[OK] Windows files copied to latest" -ForegroundColor Green

$winZipPath = "$windowsDir\history\pocketbot-windows-$timestamp.zip"
Add-Type -AssemblyName System.IO.Compression.FileSystem
if (Test-Path $winZipPath) { Remove-Item $winZipPath }
[System.IO.Compression.ZipFile]::CreateFromDirectory(
    (Resolve-Path $winPath).Path,
    $winZipPath,
    [System.IO.Compression.CompressionLevel]::Optimal,
    $false
)
Write-Host "[OK] Windows zip created in history" -ForegroundColor Green

@"
@echo off
cd /d "%~dp0"
pocket_bot.exe
"@ | Out-File -FilePath "$winLatestDir\run.bat" -Encoding ascii

Write-Host "[OK] Windows build complete" -ForegroundColor Green
Write-Host ""

$otaServer = if ($env:POCKETBOT_OTA_SERVER) { $env:POCKETBOT_OTA_SERVER } else { "http://localhost:3000" }
Write-Host "[5/5] Uploading OTA update package..." -ForegroundColor Yellow
$curlResult = curl -F "file=@$versionedApkPath" -F "version=$version" -F "changelog=Bug fixes and improvements" "$otaServer/api/upload" 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "[WARNING] OTA upload failed, continuing..." -ForegroundColor Yellow
} else {
    Write-Host "[OK] OTA update uploaded" -ForegroundColor Green
}
Write-Host ""

Write-Host "[6/6] Uploading APK for web download..." -ForegroundColor Yellow
$curlResult = curl -F "file=@$versionedApkPath" "$otaServer/api/upload-apk" 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "[WARNING] APK upload failed" -ForegroundColor Yellow
} else {
    Write-Host "[OK] APK uploaded" -ForegroundColor Green
}
Write-Host ""

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Build & Upload Complete!" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Version: $version"
Write-Host "APK: build\app\outputs\flutter-apk\pocketbot-$version.apk"
Write-Host "OTA server: $otaServer"
Write-Host "Archive: $targetDir"
Write-Host ""
Read-Host "Press Enter to exit"
