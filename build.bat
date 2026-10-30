@echo off
REM ============================================
REM TWRP 16 build launcher for OnePlus Ace 5 Ultra (PLC110)
REM Runs build.sh inside WSL (Ubuntu).
REM ============================================

echo ========================================
echo  TWRP 16 build for OnePlus Ace 5 Ultra
echo  Device: PLC110  (MediaTek MT6991)
echo  Output: vendor_boot.img
echo ========================================
echo.

wsl --list --verbose >nul 2>&1
if errorlevel 1 (
    echo [ERROR] WSL is not installed or no distribution is registered.
    echo.
    echo Install WSL and Ubuntu first:
    echo   wsl --install -d Ubuntu
    echo Then install the Android 16 build dependencies in Ubuntu.
    pause
    exit /b 1
)

set SCRIPT_DIR=%~dp0
for /f "tokens=*" %%i in ('wsl wslpath "%SCRIPT_DIR%"') do set WSL_DIR=%%i

echo [INFO] Device tree: %WSL_DIR%
echo [INFO] Starting WSL build (this can take a long time)...
echo.

wsl -e bash -c "cd '%WSL_DIR%' && chmod +x build.sh tools/extract-prebuilts.sh && ./build.sh"

echo.
echo [INFO] Build finished. Check the output above.
pause