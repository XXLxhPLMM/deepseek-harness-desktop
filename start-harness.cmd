@echo off
rem ============================================================================
rem  start-harness.cmd  -  Windows cmd native launcher for deepseek harness (dsh)
rem
rem  Ensures Node.js and dsh are ready, starts the dsh web service and opens
rem  http://localhost:<port> in the browser (app mode). The window auto-closes
rem  after a successful launch (the service keeps running independently).
rem
rem  Pure cmd implementation. PowerShell is used ONLY for language detection
rem  (same approach as setup.cmd).
rem
rem  Usage:
rem    start-harness.cmd                detect/install and start
rem    start-harness.cmd --port 3080    specify dsh service port
rem    start-harness.cmd --debug        use nodejs under script dir
rem    start-harness.cmd --help         show help
rem    start-harness.cmd /nopause       exit without pausing (for double-click)
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
set "DEBUG_MODE=0"
set "NO_PAUSE=0"
set "SUCCESS=0"

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
if "%~2"=="" (
    call :msg sh_need_port "%~1"
    echo [ERROR] !M!
    exit /b 1
)
set "PORT=%~2"
shift /1
shift /1
goto :parse
:args_done

rem ============================================================================
rem  Main flow
rem ============================================================================
call :msg sh_title
echo [INFO] !M!

if "%DEBUG_MODE%"=="1" (
    call :msg sh_node_local "%SCRIPT_DIR%nodejs"
    echo [INFO] !M!
    call :remove_node_from_path
)

rem ---- ensure Node.js ----
call :ensure_node
if errorlevel 1 goto :finish

rem ---- ensure dsh globally installed ----
call :ensure_dsh
if errorlevel 1 goto :finish

rem ---- check service: running -> open browser; not running -> start & poll ----
set "URL=http://localhost:%PORT%"

call :check_port
if not errorlevel 1 goto :service_running

call :msg sh_service_start
echo [INFO] !M!
call :start_dsh

set "WAITED=0"
:wait_loop
call :check_port
if not errorlevel 1 goto :service_ready
set /a WAITED+=1
if %WAITED% GEQ 30 goto :service_fail
ping -n 2 127.0.0.1 >nul
goto :wait_loop

:service_running
call :msg sh_service_running "%URL%"
echo [OK]    !M!
set "SUCCESS=1"
goto :open_browser

:service_ready
call :msg sh_service_ready "%URL%"
echo [OK]    !M!
set "SUCCESS=1"
goto :open_browser

:service_fail
call :msg sh_service_fail "%URL%"
echo [WARN] !M!
goto :finish

:open_browser
call :msg sh_browser "%URL%"
echo [INFO] !M!
call :open_browser_internal
if "%SUCCESS%"=="1" exit /b 0
goto :finish

:finish
if "%NO_PAUSE%"=="1" exit /b 0
echo.
echo Press any key to close this window...
pause >nul
exit /b 0

:show_help
call :msg sh_usage "%SELF%"
echo !M!
echo   --port ^<port^>    dsh service port (default: %DEFAULT_PORT%)
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
if "%~2"=="" goto :msg_ret
set "M=!M:{1}=%~2!"
if "%~3"=="" goto :msg_ret
set "M=!M:{2}=%~3!"
:msg_ret
exit /b 0

rem ---- ensure Node.js is available: errorlevel 0=ok, 1=missing ----
:ensure_node
call :detect_node
if not errorlevel 1 exit /b 0

call :msg sh_node_missing
echo [INFO] !M!
if "%DEBUG_MODE%"=="1" (
    call "%SCRIPT_DIR%setup.cmd" --debug /nopause
) else (
    call "%SCRIPT_DIR%setup.cmd" /nopause
)
if errorlevel 1 (
    call :msg sh_node_fail
    echo [ERROR] !M!
    exit /b 1
)
if exist "%SCRIPT_DIR%nodejs\node.exe" set "PATH=%SCRIPT_DIR%nodejs;%PATH%"
call :detect_node
if not errorlevel 1 exit /b 0
call :msg sh_node_fail
echo [ERROR] !M!
exit /b 1

rem ---- ensure dsh is globally installed: errorlevel 0=ok, 1=missing ----
:ensure_dsh
where dsh >nul 2>nul
if not errorlevel 1 exit /b 0

call :msg sh_dsh_missing
echo [INFO] !M!
call :msg sh_dsh_install
echo [INFO] !M!
npm install -g @deepseek-ai/dsh
if errorlevel 1 goto :dsh_fail
rem refresh PATH if npm global dir is not on it yet
set "DSH_FOUND="
where dsh >nul 2>nul && set "DSH_FOUND=1"
if not defined DSH_FOUND if exist "%APPDATA%\npm\dsh.cmd" (
    set "PATH=%APPDATA%\npm;%PATH%"
    set "DSH_FOUND=1"
)
if not defined DSH_FOUND if exist "%SCRIPT_DIR%nodejs\dsh.cmd" (
    set "PATH=%SCRIPT_DIR%nodejs;%PATH%"
    set "DSH_FOUND=1"
)
if not defined DSH_FOUND goto :dsh_fail
call :msg sh_dsh_done
echo [OK]    !M!
exit /b 0
:dsh_fail
call :msg sh_dsh_fail "@deepseek-ai/dsh"
echo [ERROR] !M!
exit /b 1

rem ---- detect Node: errorlevel 0=ok (>=22), 1=missing/too old ----
:detect_node
if "%DEBUG_MODE%"=="1" (
    if exist "%SCRIPT_DIR%nodejs\node.exe" (
        set "PATH=%SCRIPT_DIR%nodejs;%PATH%"
        goto :node_version
    )
)
where node >nul 2>nul
if errorlevel 1 goto :no_node
:node_version
for /f "usebackq delims=" %%v in (`node --version 2^>nul`) do set "NV=%%v"
if not defined NV goto :no_node
set "NODE_VERSION=%NV:~1%"
for /f "tokens=1 delims=." %%m in ("%NODE_VERSION%") do set "NODE_MAJOR=%%m"
if not defined NODE_MAJOR goto :no_node
if %NODE_MAJOR% GEQ 22 goto :node_ok
call :msg node_low "%NODE_VERSION%" "22"
echo [WARN] !M!
exit /b 1
:node_ok
call :msg node_ok "%NODE_VERSION%" "22"
echo [OK]    !M!
exit /b 0
:no_node
call :msg node_not_found
echo [INFO] !M!
exit /b 1

rem ---- debug mode: strip nvm/node entries from current PATH ----
:remove_node_from_path
set "KEPT="
set "REMOVED="
for %%p in ("%PATH:;=" "%") do (
    set "PI=%%~p"
    if /i not "!PI:nvm=!"=="!PI!" (
        set "REMOVED=!REMOVED!;!PI!"
    ) else if /i not "!PI:node=!"=="!PI!" (
        set "REMOVED=!REMOVED!;!PI!"
    ) else (
        set "KEPT=!KEPT!;!PI!"
    )
)
if defined REMOVED (
    set "PATH=!KEPT!"
    call :msg sh_path_cleaned
    echo [INFO] !M!
)
exit /b 0

rem ---- check port: errorlevel 0=running, 1=not running ----
:check_port
netstat -ano 2>nul | findstr /C:":%PORT% " | findstr /C:"LISTENING" >nul
if errorlevel 1 exit /b 1
exit /b 0

rem ---- start dsh web in a new cmd window (background), then return ----
rem Use `start "" cmd /c` so dsh (a .cmd shim) runs in a real console. Plain
rem `start "title" dsh web ...` makes cmd treat the quoted arg as a window title
rem and ShellExecute dsh, which can hand the command to the default browser and
rem pop it open before the service has even been detected.
:start_dsh
start "" cmd /c "dsh web --port %PORT%"
exit /b 0

rem ---- open browser in app mode (Edge/Chrome), fallback default browser ----
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
