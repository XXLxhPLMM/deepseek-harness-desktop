@echo off
rem ============================================================================
rem  install-server-service.cmd  -  install and start the dsh web service (wrapper)
rem
rem  Delegates to server-service.cmd install. Pure cmd, PowerShell used only for
rem  language detection inside server-service.cmd (unchanged here).
rem
rem  Usage:
rem    install-server-service.cmd            install and start the dsh-web service
rem    install-server-service.cmd --port 8080   specify port
rem    install-server-service.cmd --host 0.0.0.0 specify bind host
rem    install-server-service.cmd --debug       debug mode
rem    install-server-service.cmd /nopause     exit without pausing
rem    install-server-service.cmd --help       show help
rem
rem  NOTE: install requires administrator rights (sc create).
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

call "%SD%server-service.cmd" install %*
exit /b %ERRORLEVEL%

:help
call "%SD%server-service.cmd" --help %*
exit /b 0
