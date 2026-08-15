@echo off
rem ============================================================================
rem  server-service.cmd  -  Windows cmd native service manager for dsh web
rem
rem  Installs/manages the `dsh web` DeepSeek Harness service on Windows, using
rem  `sc create` with node.exe run directly:
rem      <node.exe> <dsh cli.js> web --port <port> --host <host>
rem
rem  Service name is fixed to dsh-web (auto start on boot).
rem
rem  Pure cmd implementation. PowerShell is used ONLY for language detection,
rem  and node.exe is used to resolve the dsh CLI entry from package.json
rem  (consistent with setup.cmd which also shells out to node/npm).
rem
rem  Usage:
rem    server-service.cmd install       register and start the service
rem    server-service.cmd uninstall     remove the service
rem    server-service.cmd status        show status
rem    server-service.cmd start         start the service
rem    server-service.cmd stop          stop the service
rem    server-service.cmd --port 8080 install
rem    server-service.cmd --host 0.0.0.0 install
rem    server-service.cmd --debug install   use nodejs/dsh under script dir
rem    server-service.cmd --help
rem    server-service.cmd /nopause      exit without pausing (for double-click)
rem
rem  i18n: load locales/{lang}.lang by system language (default zh). Use:
rem       call :msg <key> <arg1> <arg2> -> result stored in !M!
rem ============================================================================
setlocal EnableExtensions EnableDelayedExpansion

rem ---- language detection (load FIRST, default zh) ----
rem NOTE: NEVER write "if" directly followed by an open paren anywhere in this
rem file, even inside a quoted PowerShell string: cmd mis-parses it as a
rem block open and corrupts goto/call label lookup later in the script.
rem Always keep a space after if/elseif.
set "LANG=zh"
set "LANGTMP=%TEMP%\srv_lang.txt"
powershell -NoProfile -Command "$c=if ($env:SETUP_LANG) {$env:SETUP_LANG.ToLower()} else {([System.Globalization.CultureInfo]::InstalledUICulture).Name.ToLower()}; if ($c -match '^zh[-_]?(tw|hk|mo)') {$r='zh-TW'} elseif ($c -match '^zh') {$r='zh'} elseif ($c -match '^ja') {$r='ja'} elseif ($c -match '^ko') {$r='ko'} elseif ($c -match '^fr') {$r='fr'} elseif ($c -match '^de') {$r='de'} elseif ($c -match '^es') {$r='es'} elseif ($c -match '^en') {$r='en'} else {$r='zh'}; [System.IO.File]::WriteAllText($env:LANGTMP, $r)" 2>nul
if exist "%LANGTMP%" set /p LANG=<"%LANGTMP%"
del /f /q "%LANGTMP%" >nul 2>nul

chcp 65001 >nul 2>nul

set "SCRIPT_DIR=%~dp0"
set "ROOT_DIR=%~dp0.."
set "SELF=%~nx0"
set "SVC_NAME=dsh-web"
set "DEFAULT_PORT=3080"
set "PORT=%DEFAULT_PORT%"
if defined DSH_PORT set "PORT=%DSH_PORT%"
set "HOST=127.0.0.1"
set "DEBUG_MODE=0"
set "NO_PAUSE=0"
set "ACTION="
set "EXIT_CODE=0"

rem ---- load language file into MSG_<key> ----
set "LANG_FILE=%ROOT_DIR%\locales\%LANG%.lang"
if not exist "%LANG_FILE%" (
    set "LANG_FILE=%ROOT_DIR%\locales\zh.lang"
)
for /f "usebackq eol=# tokens=1,* delims==" %%a in ("%LANG_FILE%") do set "MSG_%%a=%%b"

rem ---- parse arguments ----
:parse
if "%~1"=="" goto :args_done
if /i "%~1"=="install"    set "ACTION=install"    & shift /1 & goto :parse
if /i "%~1"=="uninstall"  set "ACTION=uninstall"  & shift /1 & goto :parse
if /i "%~1"=="status"     set "ACTION=status"     & shift /1 & goto :parse
if /i "%~1"=="start"      set "ACTION=start"      & shift /1 & goto :parse
if /i "%~1"=="stop"       set "ACTION=stop"       & shift /1 & goto :parse
if /i "%~1"=="--port"     goto :set_port
if /i "%~1"=="/port"      goto :set_port
if /i "%~1"=="-port"      goto :set_port
if /i "%~1"=="--host"     goto :set_host
if /i "%~1"=="/host"      goto :set_host
if /i "%~1"=="-host"      goto :set_host
if /i "%~1"=="--debug"    set "DEBUG_MODE=1"  & shift /1 & goto :parse
if /i "%~1"=="/debug"     set "DEBUG_MODE=1"  & shift /1 & goto :parse
if /i "%~1"=="--help"     goto :show_help
if /i "%~1"=="/help"      goto :show_help
if /i "%~1"=="-h"         goto :show_help
if /i "%~1"=="/nopause"   set "NO_PAUSE=1"    & shift /1 & goto :parse
call :msg unknown_arg "%~1"
echo [WARN] !M!
shift /1
goto :parse
:set_port
if "%~2"=="" goto :args_done
set "PORT=%~2"
shift /1
shift /1
goto :parse
:set_host
if "%~2"=="" goto :args_done
set "HOST=%~2"
shift /1
shift /1
goto :parse
:args_done

if "%ACTION%"=="" (
    call :msg srvc_unknown_action ""
    echo [ERROR] !M!
    goto :show_help
)

rem ============================================================================
rem  Main flow
rem ============================================================================
call :msg srvc_title
echo [INFO] !M!

if "%ACTION%"=="status" goto :do_status

rem ---- admin check ----
net session >nul 2>nul
if not errorlevel 1 goto :admin_ok
call :msg srvc_no_admin "%ACTION%"
echo [WARN] !M!
:admin_ok

if "%ACTION%"=="install"   goto :do_install
if "%ACTION%"=="uninstall" goto :do_uninstall
if "%ACTION%"=="start"     goto :do_start
if "%ACTION%"=="stop"      goto :do_stop
goto :finish

:do_install
call :resolve_runtime
if errorlevel 1 goto :finish
call :svc_exists
if not errorlevel 1 (
    call :msg srvc_exists "%SVC_NAME%"
    echo [INFO] !M!
) else (
    call :msg srvc_install "%PORT%"
    echo [INFO] !M!
    set "BINPATH="%NODE_EXE%" "%DSH_CLI%" web --port %PORT% --host %HOST%"
    sc create "%SVC_NAME%" binPath= "!BINPATH!" start= auto DisplayName= "DeepSeek Harness Web (dsh web)" >nul 2>nul
    if errorlevel 1 (
        call :msg srvc_install_fail "%SVC_NAME%"
        echo [ERROR] !M!
        set "EXIT_CODE=1"
        goto :finish
    )
    sc failure "%SVC_NAME%" reset= 86400 actions= restart/5000/restart/5000/restart/5000 >nul 2>nul
)
call :msg srvc_installed "%SVC_NAME%"
echo [OK]    !M!
goto :do_start

:do_uninstall
call :svc_exists
if errorlevel 1 (
    call :msg srvc_not_installed
    echo [INFO] !M!
    goto :finish
)
call :msg srvc_uninstall
echo [INFO] !M!
call :svc_running
if not errorlevel 1 sc stop "%SVC_NAME%" >nul 2>nul
sc delete "%SVC_NAME%" >nul 2>nul
if errorlevel 1 (
    call :msg srvc_uninstall_fail
    echo [ERROR] !M!
    set "EXIT_CODE=1"
    goto :finish
)
call :msg srvc_uninstalled
echo [OK]    !M!
goto :finish

:do_status
call :svc_exists
if errorlevel 1 (
    call :msg srvc_not_installed
    echo [INFO] !M!
    goto :finish
)
call :svc_running
if not errorlevel 1 (
    call :msg srvc_running "%SVC_NAME%"
    echo [OK]    !M!
) else (
    call :msg srvc_stopped
    echo [WARN] !M!
)
goto :finish

:do_start
call :svc_exists
if errorlevel 1 (
    call :msg srvc_not_installed
    echo [ERROR] !M!
    set "EXIT_CODE=1"
    goto :finish
)
call :msg srvc_starting
echo [INFO] !M!
sc start "%SVC_NAME%" >nul 2>nul
call :svc_running
if errorlevel 1 (
    call :msg srvc_stopped
    echo [ERROR] !M!
    set "EXIT_CODE=1"
    goto :finish
)
call :msg srvc_started "%SVC_NAME%"
echo [OK]    !M!
goto :finish

:do_stop
call :svc_exists
if errorlevel 1 (
    call :msg srvc_not_installed
    echo [ERROR] !M!
    set "EXIT_CODE=1"
    goto :finish
)
call :svc_running
if not errorlevel 1 (
    call :msg srvc_stopping
    echo [INFO] !M!
    sc stop "%SVC_NAME%" >nul 2>nul
)
call :msg srvc_stopped_ok
echo [OK]    !M!
goto :finish

rem ============================================================================
rem  Subroutines
rem ============================================================================

rem ---- message lookup: call :msg <key> <arg1> <arg2>; result in M ----
:msg
set "M=!MSG_%~1!"
if "%~2"=="" goto :msg_ret
set "M=!M:{1}=%~2!"
if "%~3"=="" goto :msg_ret
set "M=!M:{2}=%~3!"
:msg_ret
exit /b 0

rem ---- resolve node.exe and dsh cli.js: errorlevel 0=ok, 1=fail ----
:resolve_runtime
set "NODE_EXE="
set "DSH_CLI="
set "DSH_PKG_DIR="
set "DSH_BIN_REL="
if "%DEBUG_MODE%"=="1" (
    if exist "%ROOT_DIR%\nodejs\node.exe" set "NODE_EXE=%ROOT_DIR%\nodejs\node.exe"
    if exist "%ROOT_DIR%\node_modules\@deepseek-ai\dsh\package.json" set "DSH_PKG_DIR=%ROOT_DIR%\node_modules\@deepseek-ai\dsh"
    goto :have_dsh_dir
)
where node >nul 2>nul
if not errorlevel 1 (
    for /f "usebackq delims=" %%v in (`where node`) do if not defined NODE_EXE set "NODE_EXE=%%v"
)
where npm >nul 2>nul
if not errorlevel 1 (
    for /f "usebackq delims=" %%r in (`npm root -g 2^>nul`) do (
        if not defined DSH_PKG_DIR if exist "%%r\@deepseek-ai\dsh\package.json" set "DSH_PKG_DIR=%%r\@deepseek-ai\dsh"
    )
)
:have_dsh_dir
if defined DSH_PKG_DIR (
    rem extract "dsh":  "<path>" value from package.json without running node -e
    set "RAW="
    for /f "usebackq delims=" %%L in (`findstr /I /C:"\"dsh\"" "%DSH_PKG_DIR%\package.json"`) do set "RAW=%%L"
    for /f "tokens=2 delims=:" %%T in ("!RAW!") do set "DSH_BIN_REL=%%T"
    set "DSH_BIN_REL=!DSH_BIN_REL:"=!"
    set "DSH_BIN_REL=!DSH_BIN_REL:~1!"
    set "DSH_BIN_REL=!DSH_BIN_REL: =!"
    set "DSH_CLI=!DSH_PKG_DIR!\!DSH_BIN_REL!"
)
if not defined NODE_EXE if not exist "%NODE_EXE%" (
    call :msg srvc_node_fail
    echo [ERROR] !M!
    exit /b 1
)
if not defined DSH_CLI if not exist "%DSH_CLI%" (
    call :msg srvc_dsh_fail
    echo [ERROR] !M!
    exit /b 1
)
exit /b 0

rem ---- service exists: errorlevel 0=yes, 1=no ----
:svc_exists
sc query "%SVC_NAME%" >nul 2>nul
if not errorlevel 1 exit /b 0
exit /b 1

rem ---- service running: errorlevel 0=running, 1=not ----
:svc_running
sc query "%SVC_NAME%" 2>nul | findstr /C:"RUNNING" >nul
if not errorlevel 1 exit /b 0
exit /b 1

:show_help
call :msg srvc_usage "%SELF%"
echo !M!
call :msg srvc_usage_action & echo !M!
call :msg srvc_usage_uninstall & echo !M!
call :msg srvc_usage_status & echo !M!
call :msg srvc_usage_start & echo !M!
call :msg srvc_usage_stop & echo !M!
call :msg srvc_usage_port "%DEFAULT_PORT%"
echo   !M!
call :msg srvc_usage_host
echo   !M!
call :msg srvc_usage_debug & echo !M!
call :msg srvc_usage_help & echo !M!
call :msg srvc_usage_nopause & echo !M!
goto :finish

:finish
if "%NO_PAUSE%"=="1" exit /b %EXIT_CODE%
echo.
echo Press any key to close this window...
pause >nul
exit /b %EXIT_CODE%
