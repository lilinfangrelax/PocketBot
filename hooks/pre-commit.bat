@echo off
REM PocketBot Pre-commit Hook (Windows)
REM Runs linting and format checks before allowing commits

echo ============================================
echo [Pre-commit] PocketBot Quality Check
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
echo [Step 1/2] Running Flutter analyze...

set ANALYSIS_FAILED=0

for /f "usebackq delims=" %%f in (`git diff --cached --name-only --diff-filter=d ^| findstr /r "\.dart$"`) do (
    echo [Analyze] %%f
    flutter analyze "%%f" 2>&1 | findstr /c:"error" >nul
    if !errorlevel! equ 0 (
        echo [ERROR] Lint errors found in %%f
        set ANALYSIS_FAILED=1
    )
)

if !ANALYSIS_FAILED! equ 0 (
    echo [OK] All staged Dart files passed analysis!
) else (
    echo [FAILED] Analysis found errors. Run 'flutter analyze' for details.
    exit 1
)

echo.
echo [Step 2/2] Checking code format...

flutter format --check lib test 2>&1 > format_check.txt
set FORMAT_RESULT=!errorlevel!
del format_check.txt 2>nul

if !FORMAT_RESULT! equ 0 (
    echo [FAILED] Code formatting check failed.
    echo [INFO] Run 'flutter format lib test' to fix.
    exit 1
) else (
    echo [OK] Code formatting is correct!
)

echo.
echo ============================================
echo [Pre-commit] ALL CHECKS PASSED
echo ============================================

exit 0
