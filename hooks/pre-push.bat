@echo off
REM PocketBot Pre-push Build & Test Hook (Windows)

echo ============================================
echo [Pre-push] PocketBot Quality Check
echo ============================================

REM Check for --no-verify flag
if "%1"=="--no-verify" (
    echo [Hook] Skipped by --no-verify
    exit 0
)

REM Get project root
for /f "delims=" %%i in ('git rev-parse --show-toplevel') do set "PROJECT_ROOT=%%i"

REM Change to project root
cd /d "%PROJECT_ROOT%" 2>nul

echo.
echo [Step 1/5] Running flutter pub get...

flutter pub get > nul 2>&1
if errorlevel 1 (
    echo [FAILED] flutter pub get failed
    exit 1
)
echo [OK] Dependencies updated

echo.
echo [Step 2/5] Running flutter analyze...

flutter analyze > nul 2>&1
if errorlevel 1 (
    echo [FAILED] Analysis found errors.
    echo [INFO] Run 'flutter analyze' for details.
    exit 1
)
echo [OK] Analysis passed

echo.
echo [Step 3/5] Running flutter test...

flutter test --no-coverage > nul 2>&1
if errorlevel 1 (
    echo [FAILED] Tests must pass before push.
    exit 1
)
echo [OK] All tests passed

echo.
echo [Step 4/5] Building APK (debug)...

flutter build apk --debug > nul 2>&1
if errorlevel 1 (
    echo [FAILED] Build failed.
    echo [INFO] Run 'flutter build apk --debug' for details.
    exit 1
)
echo [OK] APK build successful

echo.
echo ============================================
echo [Pre-push] ALL CHECKS PASSED
echo ============================================

exit 0
