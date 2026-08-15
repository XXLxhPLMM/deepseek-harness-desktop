@echo off
rem ============================================================================
rem  stop-server-service.cmd  -  stop the dsh web service (thin wrapper)
rem
rem  Delegates to server-service.cmd stop. Pure cmd, PowerShell used only for
rem  language detection inside server-service.cmd (unchanged here).
rem
rem  Usage:
rem    stop-server-service.cmd        stop the dsh-web service
rem    stop-server-service.cmd /nopause   exit without pausing
rem    stop-server-service.cmd --help     show help
rem ============================================================================
setlocal
set "SD=%~dp0"
set "NO_PAUSE=0"

rem ---- detect --help / -h ----
for %%a in (%*) do (
    if /i "%%~a"=="--help" goto :help
    if /i "%%~a"=="/help"  goto :help
    if /i "%%~a"=="-h"     goto :help
    if /i "%%~a"=="/nopause" set "NO_PAUSE=1"
)

call "%SD%server-service.cmd" stop %*
exit /b %ERRORLEVEL%

:help
call "%SD%server-service.cmd" --help %*
exit /b 0
