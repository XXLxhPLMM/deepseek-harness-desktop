@echo off
rem setup-node.cmd
rem Windows cmd launcher: runs setup-node.ps1 to detect/install Node.js 22+
rem Usage: setup-node.cmd [options forwarded to ps1] [/nopause]

setlocal
set "SCRIPT_DIR=%~dp0"

rem Switch console to UTF-8 so Chinese output displays correctly
chcp 65001 >nul 2>nul

where powershell >nul 2>nul
if errorlevel 1 (
    echo [ERROR] PowerShell not found. Please install it and try again.
    exit /b 1
)

rem Pause the window by default (for double-click). Use /nopause to exit silently.
if /i "%~1"=="/nopause" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%setup-node.ps1" %2 %3 %4 %5 %6 %7 %8 %9
    exit /b %errorlevel%
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%setup-node.ps1" %*
echo.
echo Press any key to close this window...
pause >nul
exit /b %errorlevel%
