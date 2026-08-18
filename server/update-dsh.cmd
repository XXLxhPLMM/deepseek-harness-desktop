@echo off
rem ============================================================================
rem  update-dsh.cmd  -  update the @deepseek-ai/dsh CLI to the latest version
rem
rem  Pure cmd implementation (PowerShell used only for language detection).
rem  Updates the global dsh, then restarts the dsh-web service if installed.
rem
rem  Usage:
rem    update-dsh.cmd                update dsh to the latest version
rem    update-dsh.cmd --dry-run      show current/latest version only, no update
rem    update-dsh.cmd --debug        update dsh under the script-dir node
rem    update-dsh.cmd --help         show help
rem    update-dsh.cmd /nopause       exit without pausing (for double-click)
rem
rem  NOTE: keep this file pure ASCII (GBK/UTF-8 multibyte comments corrupt cmd
rem  parsing), keep CRLF line endings, and always space PowerShell if keywords.
rem ============================================================================
setlocal EnableExtensions EnableDelayedExpansion

rem ---- language detection (same as server-service.cmd) ----
rem Runs before chcp: chcp 65001 makes CurrentUICulture fall back to en-US, so
rem use InstalledUICulture (system UI language). SETUP_LANG overrides detection.
set "LANG=zh"
set "LANGTMP=%TEMP%\ud_lang.txt"
powershell -NoProfile -Command "$c=if ($env:SETUP_LANG) {$env:SETUP_LANG.ToLower()} else {([System.Globalization.CultureInfo]::InstalledUICulture).Name.ToLower()}; if ($c -match '^zh[-_]?(tw|hk|mo)') {$r='zh-TW'} elseif ($c -match '^zh') {$r='zh'} elseif ($c -match '^ja') {$r='ja'} elseif ($c -match '^ko') {$r='ko'} elseif ($c -match '^fr') {$r='fr'} elseif ($c -match '^de') {$r='de'} elseif ($c -match '^es') {$r='es'} elseif ($c -match '^en') {$r='en'} else {$r='zh'}; [System.IO.File]::WriteAllText($env:LANGTMP, $r)" 2>nul
if exist "%LANGTMP%" set /p LANG=<"%LANGTMP%"
del /f /q "%LANGTMP%" >nul 2>nul

chcp 65001 >nul 2>nul

set "SCRIPT_DIR=%~dp0"
set "ROOT_DIR=%~dp0.."
set "SELF=%~nx0"
set "SVC_NAME=dsh-web"
set "DSH_PKG=@deepseek-ai/dsh"
set "DRY_RUN=0"
set "DEBUG_MODE=0"
set "NO_PAUSE=0"
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
if /i "%~1"=="--dry-run" set "DRY_RUN=1"   & shift /1 & goto :parse
if /i "%~1"=="/dry-run"  set "DRY_RUN=1"   & shift /1 & goto :parse
if /i "%~1"=="--debug"   set "DEBUG_MODE=1" & shift /1 & goto :parse
if /i "%~1"=="/debug"    set "DEBUG_MODE=1" & shift /1 & goto :parse
if /i "%~1"=="--help"    goto :show_help
if /i "%~1"=="/help"     goto :show_help
if /i "%~1"=="-h"        goto :show_help
if /i "%~1"=="/nopause"  set "NO_PAUSE=1"   & shift /1 & goto :parse
call :msg unknown_arg "%~1"
echo [WARN] !M!
shift /1
goto :parse
:args_done

rem ============================================================================
rem  Main flow
rem ============================================================================
call :msg ud_title
echo [INFO] !M!

rem ---- locate dsh: debug mode only accepts the script-dir node global ----
if "%DEBUG_MODE%"=="1" (
    if exist "%ROOT_DIR%\nodejs\dsh.cmd" goto :dsh_found
    goto :no_dsh
)
where dsh >nul 2>nul
if errorlevel 1 goto :no_dsh
:dsh_found

rem ---- debug mode: use the script-dir node's npm/global dir ----
if "%DEBUG_MODE%"=="1" (
    set "PATH=%ROOT_DIR%\nodejs;%PATH%"
    set "npm_config_prefix=%ROOT_DIR%\nodejs"
)

rem ---- current version ----
set "CUR_VER="
for /f "usebackq delims=" %%v in (`dsh --version 2^>nul`) do if not defined CUR_VER set "CUR_VER=%%v"
if not defined CUR_VER set "CUR_VER=unknown"
call :msg ud_current "%CUR_VER%"
echo [INFO] !M!

if "%DRY_RUN%"=="1" goto :dry_run

rem ---- update to latest ----
call :msg ud_updating
echo [INFO] !M!
cmd /c npm install -g "%DSH_PKG%@latest" >nul 2>nul
if errorlevel 1 (
    call :msg ud_fail "%DSH_PKG%"
    echo [ERROR] !M!
    set "EXIT_CODE=1"
    goto :finish
)

rem ---- new version ----
set "NEW_VER="
for /f "usebackq delims=" %%v in (`dsh --version 2^>nul`) do if not defined NEW_VER set "NEW_VER=%%v"
if not defined NEW_VER set "NEW_VER=unknown"
call :msg ud_done "%NEW_VER%"
echo [OK]    !M!

rem ---- restart the service if it is installed ----
schtasks /query /tn "%SVC_NAME%" >nul 2>nul
if errorlevel 1 goto :finish
call :msg ud_restarting
echo [INFO] !M!
call "%SCRIPT_DIR%server-service.cmd" stop /nopause >nul 2>nul
call "%SCRIPT_DIR%server-service.cmd" start /nopause >nul 2>nul
call :msg ud_restart_done
echo [OK]    !M!
goto :finish

:dry_run
set "LATEST_VER="
for /f "usebackq delims=" %%v in (`cmd /c npm view "%DSH_PKG%" version 2^>nul`) do if not defined LATEST_VER set "LATEST_VER=%%v"
if not defined LATEST_VER set "LATEST_VER=unknown"
call :msg ud_latest "%LATEST_VER%"
echo [INFO] !M!
if /i not "%CUR_VER%"=="unknown" if /i not "%LATEST_VER%"=="unknown" if /i "%CUR_VER%"=="%LATEST_VER%" (
    call :msg ud_up_to_date
    echo [OK]    !M!
)
goto :finish

:no_dsh
call :msg ud_no_dsh
echo [ERROR] !M!
set "EXIT_CODE=1"
goto :finish

:finish
exit /b %EXIT_CODE%

rem ---- message lookup: call :msg <key> <arg1> <arg2>; result in M ----
:msg
set "M=!MSG_%~1!"
set "M=!M:{1}=%~2!"
set "M=!M:{2}=%~3!"
:msg_ret
exit /b 0

:show_help
call :msg ud_usage "%SELF%"
echo !M!
call :msg ud_usage_dryrun & echo !M!
call :msg ud_usage_debug & echo !M!
call :msg ud_usage_help & echo !M!
call :msg ud_usage_nopause & echo !M!
exit /b 0
