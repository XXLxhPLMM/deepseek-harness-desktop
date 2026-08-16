@echo off
rem ============================================================================
rem  start.cmd  -  Windows cmd launcher for deepseek harness (dsh)
rem
rem  Runs setup first to prepare the toolchain (node + taobao mirror + nrm + dsh),
rem  detects whether the dsh service (scheduled task dsh-web) is running,
rem  resolves the service port, then opens http://localhost:<port> in a webview
rem  / browser app window.
rem
rem  Pure cmd implementation. PowerShell is used for language detection and
rem  for scheduled-task status/port queries (State enum is locale-independent).
rem
rem  Usage:
rem    start.cmd                start deepseek harness
rem    start.cmd --port 3080    specify dsh service port
rem    start.cmd --debug        run setup --debug
rem    start.cmd --help         show help
rem    start.cmd /nopause       exit without pausing (for double-click)
rem
rem  i18n: load locales/{lang}.lang by system language (default zh). Use:
rem       call :msg <key> <arg1> <arg2> -> result stored in !M!
rem ============================================================================
setlocal EnableExtensions EnableDelayedExpansion

rem ---- language detection (load FIRST, default zh) ----
rem NOTE: NEVER write "if(" (if directly followed by an open paren) anywhere in
rem this file, even inside a quoted PowerShell string: cmd mis-parses it as a
rem block open and corrupts goto/call label lookup later in the script.
rem Always keep a space after if/elseif.
set "LANG=zh"
set "LANGTMP=%TEMP%\sh_lang.txt"
powershell -NoProfile -Command "$c=if ($env:SETUP_LANG) {$env:SETUP_LANG.ToLower()} else {([System.Globalization.CultureInfo]::InstalledUICulture).Name.ToLower()}; if ($c -match '^zh[-_]?(tw|hk|mo)') {$r='zh-TW'} elseif ($c -match '^zh') {$r='zh'} elseif ($c -match '^ja') {$r='ja'} elseif ($c -match '^ko') {$r='ko'} elseif ($c -match '^fr') {$r='fr'} elseif ($c -match '^de') {$r='de'} elseif ($c -match '^es') {$r='es'} elseif ($c -match '^en') {$r='en'} else {$r='zh'}; [System.IO.File]::WriteAllText($env:LANGTMP, $r)" 2>nul
if exist "%LANGTMP%" set /p LANG=<"%LANGTMP%"
del /f /q "%LANGTMP%" >nul 2>nul

chcp 65001 >nul 2>nul

set "SCRIPT_DIR=%~dp0"
set "SELF=%~nx0"
set "DEFAULT_PORT=3080"
set "PORT=%DEFAULT_PORT%"
if defined DSH_PORT set "PORT=%DSH_PORT%"
set "CLI_PORT="
set "DEBUG_MODE=0"
set "NO_PAUSE=0"
set "SVC_NAME=dsh-web"

rem ---- load language file into MSG_<key> ----
set "LANG_FILE=%SCRIPT_DIR%locales\%LANG%.lang"
if not exist "%LANG_FILE%" (
    echo [WARN] Language file missing, fallback to Chinese.
    set "LANG_FILE=%SCRIPT_DIR%locales\zh.lang"
)
for /f "usebackq eol=# tokens=1,* delims==" %%a in ("%LANG_FILE%") do set "MSG_%%a=%%b"

rem ---- parse arguments ----
:parse
if "%~1"=="" goto :args_done
if /i "%~1"=="--port"    goto :set_port
if /i "%~1"=="/port"     goto :set_port
if /i "%~1"=="-port"     goto :set_port
if /i "%~1"=="--debug"   set "DEBUG_MODE=1"  & shift /1 & goto :parse
if /i "%~1"=="/debug"    set "DEBUG_MODE=1"  & shift /1 & goto :parse
if /i "%~1"=="--help"    goto :show_help
if /i "%~1"=="/help"     goto :show_help
if /i "%~1"=="-h"        goto :show_help
if /i "%~1"=="/nopause"  set "NO_PAUSE=1"    & shift /1 & goto :parse
call :msg sh_unknown "%~1"
echo [WARN] !M!
shift /1
goto :parse
:set_port
if "%~2"=="" goto :args_done
set "PORT=%~2"
set "CLI_PORT=%~2"
shift /1
shift /1
goto :parse
:args_done

rem ============================================================================
rem  Main flow
rem ============================================================================
call :msg sh_title
echo [INFO] !M!

rem ---- 1) ensure dsh is available: skip setup when dsh already ready ----
call :check_dsh
if not errorlevel 1 goto :dsh_ok

call :msg sh_setup_run
echo [INFO] !M!
if "%DEBUG_MODE%"=="1" (
    call "%SCRIPT_DIR%setup.cmd" --debug /nopause
) else (
    call "%SCRIPT_DIR%setup.cmd" /nopause
)
if errorlevel 1 (
    call :msg sh_setup_fail
    echo [ERROR] !M!
    set "EXIT_CODE=1"
    goto :finish
)
:dsh_ok

rem ---- 2) resolve service port: --port > task config > DSH_PORT > default ----
if "%CLI_PORT%"=="" call :get_task_port
if defined TASK_PORT set "PORT=%TASK_PORT%"

call :msg sh_port_using "%PORT%"
echo [INFO] !M!

set "URL=http://localhost:%PORT%"

rem ---- 3) detect whether the dsh service is running ----
call :svc_running
if "%RUNNING%"=="1" goto :service_running

rem ---- start the service (scheduled task) ----
call :start_service
if "%STARTED%"=="1" goto :service_ready

call :msg sh_service_fail "%URL%"
echo [WARN] !M!
goto :finish

:service_running
call :msg sh_service_running "%URL%"
echo [OK]    !M!
goto :open_browser

:service_ready
call :msg sh_service_ready "%URL%"
echo [OK]    !M!
goto :open_browser

:open_browser
call :msg sh_browser "%URL%"
echo [INFO] !M!
call :open_browser_internal
goto :finish

:finish
if defined EXIT_CODE exit /b %EXIT_CODE%
exit /b 0

:show_help
call :msg sh_usage "%SELF%"
echo !M!
call :msg sh_usage_port "%DEFAULT_PORT%"
echo !M!
call :msg sh_usage_debug
echo !M!
call :msg sh_usage_help
echo !M!
call :msg sh_usage_nopause
echo !M!
exit /b 0

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
exit /b 0

rem ---- dsh ready? errorlevel 0=yes (skip setup), 1=no (need setup) ----
rem Normal mode checks PATH; debug mode only accepts the script-dir node global.
:check_dsh
if "%DEBUG_MODE%"=="1" (
    if exist "%SCRIPT_DIR%nodejs\dsh.cmd" (
        call :msg sh_dsh_ok
        echo [OK]    !M!
        exit /b 0
    )
    exit /b 1
)
where dsh >nul 2>nul
if not errorlevel 1 (
    call :msg sh_dsh_ok
    echo [OK]    !M!
)
exit /b

rem ---- read the --port value from the dsh-web task config (empty if none) ----
:get_task_port
set "TASK_PORT="
for /f "usebackq delims=" %%a in (`powershell -NoProfile -Command "$t=Get-ScheduledTask -TaskName '%SVC_NAME%' -ErrorAction SilentlyContinue; if ($t) {$m=[regex]::Match($t.Actions.Arguments,'--port\s+(\d+)'); if ($m.Success) {Write-Output $m.Groups[1].Value}}"`) do set "TASK_PORT=%%a"
exit /b 0

rem ---- service running (scheduled task or port): sets RUNNING=1/0 ----
rem Uses PowerShell for task state (locale-independent). Results passed via a
rem variable instead of errorlevel (errorlevel right after nested call is
rem unreliable in cmd).
:svc_running
set "RUNNING=0"
powershell -NoProfile -Command "$t=Get-ScheduledTask -TaskName '%SVC_NAME%' -ErrorAction SilentlyContinue; if ($t -and $t.State -eq 'Running'){exit 0}else{exit 1}" >nul 2>nul
if not errorlevel 1 set "RUNNING=1"
netstat -ano 2>nul | findstr /C:":%PORT% " | findstr /C:"LISTENING" >nul
if not errorlevel 1 set "RUNNING=1"
exit /b 0

rem ---- port listening: errorlevel 0=running, 1=not ----
:check_port
netstat -ano 2>nul | findstr /C:":%PORT% " | findstr /C:"LISTENING" >nul
if errorlevel 1 exit /b 1
exit /b 0

rem ---- task registered? errorlevel 0=yes, 1=no ----
:svc_exists
schtasks /query /tn "%SVC_NAME%" >nul 2>nul
if not errorlevel 1 exit /b 0
exit /b 1

rem ---- start service (registered -> start; not registered -> install & start), poll port ----
:start_service
set "STARTED=0"
call :msg sh_service_start
echo [INFO] !M!
rem 任务已注册则 start, 未注册则 install (注册并启动)。
rem 避免 call 放在括号块内 (cmd 的块/goto 上下文会被被调脚本的 label 破坏)。
call :svc_exists
if not errorlevel 1 goto :svc_start
if exist "%SCRIPT_DIR%server\server-service.cmd" goto :svc_install
goto :svc_start_done
:svc_install
call "%SCRIPT_DIR%server\server-service.cmd" install /nopause >nul 2>nul
goto :svc_start_done
:svc_start
call "%SCRIPT_DIR%server\server-service.cmd" start /nopause >nul 2>nul
:svc_start_done
call :msg sh_service_wait
echo [INFO] !M!
set "WAITED=0"
:wait_loop
call :check_port
if not errorlevel 1 (
    set "STARTED=1"
    exit /b 0
)
set /a WAITED+=1
if %WAITED% GEQ 30 exit /b 1
ping -n 2 127.0.0.1 >nul
goto :wait_loop

rem ---- open URL in webview/browser app mode (Edge/Chrome), fallback default ----
:open_browser_internal
set "EDGE="
if exist "%ProgramFiles(x86)%\Microsoft\Edge\Application\msedge.exe" set "EDGE=%ProgramFiles(x86)%\Microsoft\Edge\Application\msedge.exe"
if not defined EDGE if exist "%ProgramFiles%\Microsoft\Edge\Application\msedge.exe" set "EDGE=%ProgramFiles%\Microsoft\Edge\Application\msedge.exe"
if not defined EDGE if exist "%LocalAppData%\Microsoft\Edge\Application\msedge.exe" set "EDGE=%LocalAppData%\Microsoft\Edge\Application\msedge.exe"
if defined EDGE (
    start "" "%EDGE%" --app=%URL%
    exit /b 0
)
set "CHROME="
if exist "%ProgramFiles%\Google\Chrome\Application\chrome.exe" set "CHROME=%ProgramFiles%\Google\Chrome\Application\chrome.exe"
if not defined CHROME if exist "%ProgramFiles(x86)%\Google\Chrome\Application\chrome.exe" set "CHROME=%ProgramFiles(x86)%\Google\Chrome\Application\chrome.exe"
if not defined CHROME if exist "%LocalAppData%\Google\Chrome\Application\chrome.exe" set "CHROME=%LocalAppData%\Google\Chrome\Application\chrome.exe"
if defined CHROME (
    start "" "%CHROME%" --app=%URL%
    exit /b 0
)
start "" "%URL%"
exit /b 0
