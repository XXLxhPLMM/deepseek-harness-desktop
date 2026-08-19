@echo off
rem ============================================================================
rem  start.cmd  -  Windows cmd launcher for deepseek harness (dsh)
rem
rem  Runs setup first to prepare the toolchain (node + taobao mirror + nrm + dsh),
rem  detects whether the dsh service (scheduled task dsh-web) is running,
rem  resolves the service port, then opens http://localhost:<port> in a webview
rem  / browser app window.
rem
rem  Pure cmd implementation. No PowerShell: language via registry LCID,
rem  task port via schtasks /xml, service state via netstat.
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
rem Use the install-language LCID from the registry (locale-independent),
rem not PowerShell/InstalledUICulture. SETUP_LANG overrides detection.
set "LANG=zh"
if defined SETUP_LANG set "LANG=%SETUP_LANG%"
set "LCID="
for /f "tokens=3 delims= " %%A in ('reg query "HKLM\SYSTEM\CurrentControlSet\Control\Nls\Language" /v InstallLanguage') do set "LCID=%%A"
if defined SETUP_LANG goto :lang_done
if "%LCID%"=="0404" set "LANG=zh-TW"
if "%LCID%"=="0C04" set "LANG=zh-TW"
if "%LCID%"=="1404" set "LANG=zh-TW"
if "%LCID%"=="1004" set "LANG=zh"
if "%LCID%"=="0411" set "LANG=ja"
if "%LCID%"=="0412" set "LANG=ko"
if "%LCID%"=="040C" set "LANG=fr"
if "%LCID%"=="0407" set "LANG=de"
if "%LCID%"=="0C0A" set "LANG=es"
if "%LCID%"=="0409" set "LANG=en"
if "%LCID%"=="0809" set "LANG=en"
if "%LCID%"=="0C09" set "LANG=en"
:lang_done
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
if not "%TASK_PORT%"=="" set "PORT=%TASK_PORT%"

call :msg sh_port_using "%PORT%"
echo [INFO] !M!

set "URL=http://localhost:%PORT%"

rem ---- 3) detect whether the dsh service is running ----
call :svc_running
if "%RUNNING%"=="1" goto :service_running

rem ---- start the service (registered -> start; not registered -> install & start) ----
rem Do NOT call a subroutine and then goto other labels (it corrupts cmd's call
rem return stack, causing "/goto is not recognized"). Also do NOT call
rem server-service.cmd inside a parenthesized block (it uses goto internally and
rem breaks the block/goto context). Keep it flat in main flow with goto dispatch.
call :msg sh_service_start
echo [INFO] !M!
call :svc_exists
if not errorlevel 1 if "%CLI_PORT%"=="" goto :svc_start
goto :svc_install

:svc_install
call "%SCRIPT_DIR%server\server-service.cmd" install --port "%PORT%" /nopause >nul 2>nul
if errorlevel 1 (
    call :msg sh_service_fail "%URL%"
    echo [WARN] !M!
    goto :finish
)
goto :svc_wait

:svc_start
call "%SCRIPT_DIR%server\server-service.cmd" start --port "%PORT%" /nopause >nul 2>nul
if errorlevel 1 (
    call :msg sh_service_fail "%URL%"
    echo [WARN] !M!
    goto :finish
)
goto :svc_wait

:svc_wait
call :msg sh_service_wait
echo [INFO] !M!
call :msg sh_first_slow
echo [INFO] !M!
set "WAITED=0"
:wait_loop
call :check_port
if not errorlevel 1 goto :service_ready
set /a WAITED+=1
if %WAITED% GEQ 60 goto :service_fail
ping -n 2 127.0.0.1 >nul
goto :wait_loop

:service_fail
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
rem schtasks /xml redirects to a file as single-byte (no UTF-16 BOM), so
rem findstr/for /f can parse it. Token layout of the Arguments line:
rem   <Arguments Context="Author">"path..." --port 3080</Arguments>
rem tokens (delims "<> "): [1]<Arguments [2]Context..vbs [3]--port [4]3080
rem No PowerShell needed.
:get_task_port
set "TASK_PORT="
schtasks /query /tn "%SVC_NAME%" /xml > "%TEMP%\dsh_task.xml" 2>nul
if exist "%TEMP%\dsh_task.xml" (
    for /f "tokens=4 delims=<> " %%a in ('findstr /c:"--port" "%TEMP%\dsh_task.xml"') do set "TASK_PORT=%%a"
    del /f /q "%TEMP%\dsh_task.xml" >nul 2>nul
)
exit /b 0

rem ---- service running (port listening): sets RUNNING=1/0 ----
rem Pure netstat check; no PowerShell/task-state needed.
:svc_running
set "RUNNING=0"
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
