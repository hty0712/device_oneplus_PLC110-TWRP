@echo off
REM ============================================
REM TWRP Build Launcher for Windows
REM Runs build.sh in WSL (Windows Subsystem for Linux)
REM ============================================

echo ========================================
echo  TWRP Build for OnePlus Ace 5 Racing
echo  Device: PLF110
echo  Platform: MT6991 (Dimensity 9400e)
echo ========================================
echo.

REM Check if WSL is installed
wsl --list --verbose 2>nul
if errorlevel 1 (
    echo [ERROR] WSL is not installed or not enabled.
    echo.
    echo Install WSL with:
    echo   wsl --install
    echo.
    echo Or use Ubuntu directly.
    pause
    exit /b 1
)

REM Find the script directory
set SCRIPT_DIR=%~dp0

REM Convert Windows path to WSL path
for /f "tokens=*" %%i in ('wsl wslpath "%SCRIPT_DIR%"') do set WSL_DIR=%%i

echo [INFO] Script directory: %WSL_DIR%
echo [INFO] Launching WSL build...
echo.

REM Run build script in WSL
wsl -e bash -c "cd '%WSL_DIR%' && chmod +x build.sh && ./build.sh"

echo.
echo [INFO] Build process completed.
pause
