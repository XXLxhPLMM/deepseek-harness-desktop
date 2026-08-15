@echo off
rem ============================================================================
rem  start-server-service.cmd  -  start the dsh web service (wrapper)
rem
rem  Delegates to server-service.cmd start. Pure cmd, PowerShell used only for
rem  language detection inside server-service.cmd (unchanged here).
rem
rem  Usage:
rem    start-server-service.cmd          start the dsh-web service
rem    start-server-service.cmd /nopause exit without pausing
rem    start-server-service.cmd --help   show help
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

call "%SD%server-service.cmd" start %*
exit /b %ERRORLEVEL%

:help
call "%SD%server-service.cmd" --help %*
exit /b 0
