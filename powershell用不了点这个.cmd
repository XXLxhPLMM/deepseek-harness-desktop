@echo off
rem ============================================================================
rem  enable-ps.cmd - standalone helper: enable PowerShell script execution
rem
rem  Detects the effective PowerShell ExecutionPolicy and, when it is more
rem  restrictive than RemoteSigned, enables RemoteSigned for the current user
rem  (no admin rights needed). Safe/idempotent: skips when already enabled.
rem  Makes .ps1 scripts runnable on the machine (setup.ps1, start.ps1, ...).
rem
rem  Usage:
rem    enable-ps.cmd                enable PowerShell script execution
rem    enable-ps.cmd --help         show help
rem    enable-ps.cmd /nopause       exit without pausing (for double-click)
rem
rem  i18n: load locales/{lang}.lang by system language (default zh). Use:
rem       call :msg <key> <arg1> <arg2> -> result stored in !M!
rem
rem  NOTE: keep this file pure ASCII and CRLF line endings, and never write
rem  "if(" (if directly followed by an open paren) anywhere in this file.
rem ============================================================================
setlocal EnableExtensions EnableDelayedExpansion

rem ---- language detection (load FIRST, default zh) ----
set "LANG=zh"
set "LANGTMP=%TEMP%\sn_lang.txt"
powershell -NoProfile -Command "$c=if ($env:SETUP_LANG) {$env:SETUP_LANG.ToLower()} else {([System.Globalization.CultureInfo]::InstalledUICulture).Name.ToLower()}; if ($c -match '^zh[-_]?(tw|hk|mo)') {$r='zh-TW'} elseif ($c -match '^zh') {$r='zh'} elseif ($c -match '^ja') {$r='ja'} elseif ($c -match '^ko') {$r='ko'} elseif ($c -match '^fr') {$r='fr'} elseif ($c -match '^de') {$r='de'} elseif ($c -match '^es') {$r='es'} elseif ($c -match '^en') {$r='en'} else {$r='zh'}; [System.IO.File]::WriteAllText($env:LANGTMP, $r)" 2>nul
if exist "%LANGTMP%" set /p LANG=<"%LANGTMP%"
del /f /q "%LANGTMP%" >nul 2>nul

chcp 65001 >nul 2>nul

set "SCRIPT_DIR=%~dp0"
set "SELF=%~nx0"
set "NO_PAUSE=0"

rem ---- load language file into MSG_<key> ----
set "LANG_FILE=%SCRIPT_DIR%locales\%LANG%.lang"
if not exist "%LANG_FILE%" set "LANG_FILE=%SCRIPT_DIR%locales\zh.lang"
for /f "usebackq eol=# tokens=1,* delims==" %%a in ("%LANG_FILE%") do set "MSG_%%a=%%b"

rem ---- parse arguments ----
:parse
if "%~1"=="" goto :args_done
if /i "%~1"=="--help"    goto :show_help
if /i "%~1"=="/help"     goto :show_help
if /i "%~1"=="-h"        goto :show_help
if /i "%~1"=="/nopause"  set "NO_PAUSE=1"    & shift /1 & goto :parse
call :msg unknown_arg "%~1"
echo [WARN] !M!
shift /1
goto :parse
:args_done

rem ============================================================================
rem  Main flow
rem ============================================================================
call :msg ps_title
echo ===== !M! =====
call :enable_ps1_policy
echo.
if "%NO_PAUSE%"=="0" pause
exit /b 0

:show_help
call :msg ps_usage "%SELF%"
echo !M!
call :msg usage_nopause & echo !M!
exit /b 0

rem ---- enable PowerShell ExecutionPolicy for the current user if not already ----
:enable_ps1_policy
set "CURPOL="
for /f "usebackq delims=" %%p in (`powershell -NoProfile -Command "(Get-ExecutionPolicy).ToString()" 2^>nul`) do set "CURPOL=%%p"
if /i "%CURPOL%"=="RemoteSigned" goto :already_ok
if /i "%CURPOL%"=="Unrestricted" goto :already_ok
if /i "%CURPOL%"=="Bypass" goto :already_ok
powershell -NoProfile -Command "Set-ExecutionPolicy -Scope CurrentUser RemoteSigned -Force" >nul 2>nul
if errorlevel 1 (
    call :msg ps1_policy_fail
    echo [WARN] !M!
) else (
    call :msg ps1_policy_set
    echo [OK]    !M!
)
exit /b 0
:already_ok
call :msg ps1_policy_ok "%CURPOL%"
echo [OK]    !M!
exit /b 0

rem ---- message lookup: call :msg <key> <arg1> <arg2>; result in M ----
:msg
set "M=!MSG_%~1!"
set "M=!M:{1}=%~2!"
set "M=!M:{2}=%~3!"
:msg_ret
exit /b 0
