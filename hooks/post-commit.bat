@echo off
REM PocketBot Git Post-Commit Hook

REM Check if OTA server is running
curl -s --connect-timeout 2 http://localhost:3000/health >nul
if %errorlevel% neq 0 (
    echo [Dev OTA] Skipped - OTA server not running
    exit 0
)

REM Get project root
for /f "delims=" %%i in ('git rev-parse --show-toplevel') do set "PROJECT_ROOT=%%i"
set "SCRIPT=%PROJECT_ROOT%\build_and_upload.ps1"

if exist "%SCRIPT%" (
    echo [Dev OTA] Commit detected, running build...
    powershell -ExecutionPolicy Bypass -File "%SCRIPT%"
) else (
    echo [Dev OTA] Script not found: %SCRIPT%
)
