@echo off
rem ============================================================================
rem  server-service.cmd  -  Windows cmd native service manager for dsh web
rem
rem  Installs/manages the `dsh web` DeepSeek Harness service on Windows, using
rem  a scheduled task (`schtasks /sc onstart`). The task runs a short generated
rem  wrapper (run-dsh-web.cmd); non-debug mode calls `dsh web` from PATH:
rem      dsh web [--patch <overlay>] --port <port> --host <host>
rem  Default (no --service) registers an interactive task (/it) in the logged-on
rem  user's session, launched hidden via wscript (no cmd window), with the native
rem  folder dialog. When VBScript is unavailable (on-demand feature since Windows
rem  11 24H2) it falls back to a hidden PowerShell launcher. --service registers
rem  a SYSTEM task that auto-starts before login and pins the in-app browse picker.
rem
rem  Task name is fixed to dsh-web (auto start at boot).
rem
rem  Pure cmd implementation. PowerShell is used for language detection and
rem  for task status queries (State enum is locale-independent),
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
rem    server-service.cmd --service install run as SYSTEM (auto-start pre-login)
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
set "SERVICE_MODE=0"
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
if /i "%~1"=="--service"  set "SERVICE_MODE=1"  & shift /1 & goto :parse
if /i "%~1"=="/service"   set "SERVICE_MODE=1"  & shift /1 & goto :parse
if /i "%~1"=="-service"   set "SERVICE_MODE=1"  & shift /1 & goto :parse
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
)
rem Stop any running instance so the forced re-create below takes effect cleanly.
schtasks /end /tn "%SVC_NAME%" >nul 2>nul
rem Re-create with /f every time so a changed command is refreshed on re-install.
rem Two run modes:
rem   --service: task runs as SYSTEM in session 0, where the native OS folder
rem     dialog (IFileOpenDialog) cannot be shown, so the browse directory
rem     picker is pinned via --patch. USERPROFILE is baked into the wrapper.
rem   default (interactive): task runs with /it in the logged-on user's session
rem     and the native folder dialog just works (no --patch needed).
rem
rem schtasks caps the /tr value at 261 chars, so register a short run wrapper
rem (run-dsh-web.cmd) that carries the real command. Non-debug mode calls `dsh
rem web` from PATH (no absolute node paths); debug mode pins the script-dir
rem nodejs. --patch is a dsh launcher flag and must come right after `web`,
rem before the inner app flags (--port/--host).
set "RUNNER=%SCRIPT_DIR%run-dsh-web.cmd"
set "RUNNER_VBS=%SCRIPT_DIR%run-dsh-web.vbs"
set "RUNNER_PS1=%SCRIPT_DIR%run-dsh-web.ps1"
>  "%RUNNER%" echo @echo off
>> "%RUNNER%" echo set "DSH_HOME=%USERPROFILE%\.dsh"
>> "%RUNNER%" echo set "USERPROFILE=%USERPROFILE%"
if "%SERVICE_MODE%"=="1" (
    if "%DEBUG_MODE%"=="1" (
        >> "%RUNNER%" echo "%NODE_EXE%" "%DSH_CLI%" web --patch "%SCRIPT_DIR%service-directory-picker-browse.yml" --port %PORT% --host %HOST%
    ) else (
        >> "%RUNNER%" echo dsh web --patch "%SCRIPT_DIR%service-directory-picker-browse.yml" --port %PORT% --host %HOST%
    )
) else (
    if "%DEBUG_MODE%"=="1" (
        >> "%RUNNER%" echo "%NODE_EXE%" "%DSH_CLI%" web --port %PORT% --host %HOST%
    ) else (
        >> "%RUNNER%" echo dsh web --port %PORT% --host %HOST%
    )
)
rem Interactive mode: launch via a hidden wscript wrapper so no cmd window pops
rem up in the user's session. The VBS body is written at top level because its
rem parentheses would otherwise break a cmd if-block. The second echo line must
rem keep the doubled quotes (VBS string escaping).
>  "%RUNNER_VBS%" echo Set sh = CreateObject("WScript.Shell")
>> "%RUNNER_VBS%" echo sh.Run "cmd /c ""%RUNNER%""", 0, True
rem Fallback for machines where the VBScript feature is not installed (it is an
rem on-demand feature since Windows 11 24H2): a hidden PowerShell launcher that
rem Start-Processes the wrapper with -WindowStyle Hidden and waits.
>  "%RUNNER_PS1%" echo Start-Process -FilePath "%RUNNER%" -WindowStyle Hidden -Wait
rem Probe VBScript availability; result in VBS_OK.
set "VBS_OK="
>  "%TEMP%\dsh_vbs_probe.vbs" echo WScript.Echo "OK"
for /f "usebackq delims=" %%o in (`cscript //nologo "%TEMP%\dsh_vbs_probe.vbs" 2^>nul`) do if "%%o"=="OK" set "VBS_OK=1"
del /f /q "%TEMP%\dsh_vbs_probe.vbs" >nul 2>nul
if "%SERVICE_MODE%"=="1" (
    set "BINPATH=cmd /c \"\"%RUNNER%\"\""
    schtasks /create /tn "%SVC_NAME%" /tr "!BINPATH!" /sc onstart /ru SYSTEM /rl highest /f >nul 2>nul
) else (
    if defined VBS_OK (
        set "BINPATH=wscript.exe \"%RUNNER_VBS%\""
    ) else (
        set "BINPATH=powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File \"%RUNNER_PS1%\""
    )
    schtasks /create /tn "%SVC_NAME%" /tr "!BINPATH!" /sc onstart /ru "%USERNAME%" /it /rl highest /f >nul 2>nul
)
if errorlevel 1 (
    call :msg srvc_install_fail "%SVC_NAME%"
    echo [ERROR] !M!
    set "EXIT_CODE=1"
    goto :finish
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
if not errorlevel 1 schtasks /end /tn "%SVC_NAME%" >nul 2>nul
schtasks /delete /tn "%SVC_NAME%" /f >nul 2>nul
if errorlevel 1 (
    call :msg srvc_uninstall_fail
    echo [ERROR] !M!
    set "EXIT_CODE=1"
    goto :finish
)
call :kill_dsh_web
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
schtasks /run /tn "%SVC_NAME%" >nul 2>nul
set "TRY=0"
:start_wait
call :svc_running
if not errorlevel 1 goto :start_ok
set /a TRY+=1
if "%TRY%" GEQ "10" goto :start_fail
ping -n 1 -w 500 127.0.0.1 >nul 2>nul
goto :start_wait
:start_ok
call :msg srvc_started "%SVC_NAME%"
echo [OK]    !M!
goto :finish
:start_fail
call :msg srvc_stopped
echo [ERROR] !M!
set "EXIT_CODE=1"
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
    schtasks /end /tn "%SVC_NAME%" >nul 2>nul
)
call :kill_dsh_web
call :msg srvc_stopped_ok
echo [OK]    !M!
goto :finish

rem ============================================================================
rem  Subroutines
rem ============================================================================

rem ---- message lookup: call :msg <key> <arg1> <arg2>; result in M ----
:msg
set "M=!MSG_%~1!"
set "M=!M:{1}=%~2!"
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
    if exist "%ROOT_DIR%\nodejs\node_modules\@deepseek-ai\dsh\package.json" set "DSH_PKG_DIR=%ROOT_DIR%\nodejs\node_modules\@deepseek-ai\dsh"
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
    rem extract the quoted value of the "dsh" bin entry from package.json (no node needed)
    set "RAW="
    for /f "usebackq delims=" %%L in (`findstr /I /C:"\"dsh\":" "%DSH_PKG_DIR%\package.json"`) do if not defined RAW set "RAW=%%L"
    if defined RAW (
        set "RAW=!RAW:*"dsh":=!"
        for /f "tokens=1 delims=,}" %%P in ("!RAW!") do set "DSH_BIN_REL=%%P"
        set "DSH_BIN_REL=!DSH_BIN_REL: =!"
        set "DSH_BIN_REL=!DSH_BIN_REL:"=!"
        if defined DSH_BIN_REL set "DSH_CLI=!DSH_PKG_DIR!\!DSH_BIN_REL!"
    )
)
if defined NODE_EXE if exist "%NODE_EXE%" goto :node_ok
call :msg srvc_node_fail
echo [ERROR] !M!
exit /b 1
:node_ok
if defined DSH_CLI if exist "%DSH_CLI%" exit /b 0
call :msg srvc_dsh_fail
echo [ERROR] !M!
exit /b 1

rem ---- task exists: errorlevel 0=yes, 1=no ----
:svc_exists
schtasks /query /tn "%SVC_NAME%" >nul 2>nul
if not errorlevel 1 exit /b 0
exit /b 1

rem ---- task running: errorlevel 0=running, 1=not ----
rem Uses PowerShell (State enum is locale-independent). NOTE: never write
rem "if(" without a space inside the quoted string (cmd label mis-parse).
:svc_running
powershell -NoProfile -Command "$t=Get-ScheduledTask -TaskName '%SVC_NAME%' -ErrorAction SilentlyContinue; if ($t -and $t.State -eq 'Running'){exit 0}else{exit 1}" >nul 2>nul
if not errorlevel 1 exit /b 0
exit /b 1

rem ---- kill leftover dsh web process tree ----
rem schtasks /end only terminates the task's primary process (wscript.exe in
rem interactive mode); the hidden cmd -> node chain would be orphaned and keep
rem serving, so kill the dsh web node explicitly (the wrapper cmd then exits).
:kill_dsh_web
powershell -NoProfile -Command "Get-CimInstance Win32_Process | Where-Object { $_.Name -eq 'node.exe' -and $_.CommandLine -like '*@deepseek-ai*' -and $_.CommandLine -like '*web --port*' } | ForEach-Object { taskkill /F /T /PID $_.ProcessId }" >nul 2>nul
exit /b 0

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
call :msg srvc_usage_service & echo !M!
call :msg srvc_usage_help & echo !M!
call :msg srvc_usage_nopause & echo !M!
goto :finish

:finish
exit /b %EXIT_CODE%
