@echo off
rem ============================================================================
rem  setup-node.cmd  -  Windows cmd native installer for Node.js 22+
rem
rem  Pure cmd implementation, does NOT require PowerShell.
rem  Detects Node.js >= 22, installs via nvm if available, otherwise downloads
rem  from nodejs.org and extracts to the script directory.
rem
rem  Usage:
rem    setup-node.cmd                default install dir (script dir\nodejs)
rem    setup-node.cmd --dir C:\path  custom install dir
rem    setup-node.cmd --no-env       do not modify PATH
rem    setup-node.cmd --dry-run      detect only, do not install
rem    setup-node.cmd --debug        isolated verification install
rem    setup-node.cmd --help         show help
rem    setup-node.cmd /nopause       exit without pausing (for double-click)
rem
rem  i18n: load locales/{zh,en,ja,ko,fr,de,es}.lang by system language,
rem       default to Chinese (zh) when undetectable. Use:
rem       call :msg <key> <arg1> <arg2> -> result stored in !M!
rem ============================================================================
setlocal EnableExtensions EnableDelayedExpansion

rem ---- language detection (load FIRST, default zh; zh-TW for Traditional) ----
rem Runs before chcp: chcp 65001 makes CurrentUICulture fall back to en-US, so use
rem InstalledUICulture (system UI language). SETUP_LANG env var overrides detection
rem (for testing / forcing a language).
rem NOTE: NEVER write "if(" (if directly followed by an open paren) anywhere in this
rem file, even inside a quoted PowerShell string: cmd mis-parses it as a block open
rem and corrupts goto/call label lookup later in the script. Always keep a space.
set "LANG=zh"
set "LANGTMP=%TEMP%\sn_lang.txt"
powershell -NoProfile -Command "$c=if ($env:SETUP_LANG) {$env:SETUP_LANG.ToLower()} else {([System.Globalization.CultureInfo]::InstalledUICulture).Name.ToLower()}; if ($c -match '^zh[-_]?(tw|hk|mo)') {$r='zh-TW'} elseif ($c -match '^zh') {$r='zh'} elseif ($c -match '^ja') {$r='ja'} elseif ($c -match '^ko') {$r='ko'} elseif ($c -match '^fr') {$r='fr'} elseif ($c -match '^de') {$r='de'} elseif ($c -match '^es') {$r='es'} elseif ($c -match '^en') {$r='en'} else {$r='zh'}; [System.IO.File]::WriteAllText($env:LANGTMP, $r)" 2>nul
if exist "%LANGTMP%" set /p LANG=<"%LANGTMP%"
del /f /q "%LANGTMP%" >nul 2>nul

set "SCRIPT_DIR=%~dp0"
set "VERSION=v22.23.2"
set "NVM_VERSION=22.23.2"
set "MIN_MAJOR=22"
set "BASE_URL=https://nodejs.org/dist"
set "SELF=%~nx0"

rem ---- defaults ----
set "INSTALL_DIR=%SCRIPT_DIR%nodejs"
set "DO_ENV=1"
set "DRY_RUN=0"
set "DEBUG_MODE=0"
set "NO_PAUSE=0"

rem ---- switch console to UTF-8 (after language detection above) ----
chcp 65001 >nul 2>nul

rem ---- load language file into MSG_<key> ----
set "LANG_FILE=%SCRIPT_DIR%locales\%LANG%.lang"
if not exist "%LANG_FILE%" (
    echo [WARN] Language file missing, fallback to Chinese.
    set "LANG_FILE=%SCRIPT_DIR%locales\zh.lang"
)
for /f "usebackq eol=# tokens=1,* delims==" %%a in ("%LANG_FILE%") do set "MSG_%%a=%%b"

rem ---- parse arguments ----
set "ARG_DIR="
set "HAS_DIR=0"
:parse
if "%~1"=="" goto :args_done
if /i "%~1"=="--dir"       goto :set_dir
if /i "%~1"=="/dir"        goto :set_dir
if /i "%~1"=="-dir"        goto :set_dir
if /i "%~1"=="--no-env"    set "DO_ENV=0"      & shift /1 & goto :parse
if /i "%~1"=="/no-env"     set "DO_ENV=0"      & shift /1 & goto :parse
if /i "%~1"=="--dry-run"   set "DRY_RUN=1"     & shift /1 & goto :parse
if /i "%~1"=="/dry-run"    set "DRY_RUN=1"     & shift /1 & goto :parse
if /i "%~1"=="--debug"     set "DEBUG_MODE=1"  & shift /1 & goto :parse
if /i "%~1"=="/debug"      set "DEBUG_MODE=1"  & shift /1 & goto :parse
if /i "%~1"=="--help"      goto :show_help
if /i "%~1"=="/help"       goto :show_help
if /i "%~1"=="-h"          goto :show_help
if /i "%~1"=="/nopause"    set "NO_PAUSE=1"    & shift /1 & goto :parse
call :msg unknown_arg "%~1"
echo [WARN] !M!
shift /1
goto :parse
:set_dir
if "%~2"=="" ( call :msg dir_need_path "%~1" & echo [ERROR] !M! & exit /b 1 )
set "ARG_DIR=%~2"
set "HAS_DIR=1"
shift /1
shift /1
goto :parse
:args_done

if "%HAS_DIR%"=="1" set "INSTALL_DIR=%ARG_DIR%"

if "%DEBUG_MODE%"=="1" (
    call :msg debug_title "%INSTALL_DIR%"
    echo [INFO] !M!
    call :remove_node_from_path
)

rem ---- detect existing Node ----
call :detect_node
if errorlevel 2 exit /b 0
if errorlevel 1 goto :need_install

:already_ok
exit /b 0

:need_install
if "%DRY_RUN%"=="1" (
    call :msg dryrun_skip
    echo [INFO] !M!
    exit /b 1
)

rem ---- choose install path ----
if "%DEBUG_MODE%"=="1" (
    call :msg debug_skip_nvm
    echo [INFO] !M!
    call :download_and_extract
    if errorlevel 1 goto :install_failed
    goto :env_setup
)

rem ---- try nvm ----
call :detect_nvm
if errorlevel 1 goto :no_nvm

call :msg nvm_using "%NVM_VERSION%"
echo [INFO] !M!
call :nvm_install
if errorlevel 1 (
    call :msg nvm_fail_fallback
    echo [WARN] !M!
    goto :no_nvm
)
set "INSTALLED_BY_NVM=1"
goto :env_setup

:no_nvm
call :msg no_nvm
echo [INFO] !M!
call :download_and_extract
if errorlevel 1 goto :install_failed

:install_failed
call :msg install_failed
echo [ERROR] !M!
exit /b 1

:env_setup
if "%DEBUG_MODE%"=="1" (
    call :msg debug_session_only
    echo [INFO] !M!
    set "PATH=%INSTALL_DIR%;%PATH%"
    goto :done
)
if "%DO_ENV%"=="0" (
    call :msg noenv_skip
    echo [INFO] !M!
    call :msg noenv_manual "%INSTALL_DIR%"
    echo [WARN] !M!
    goto :done
)
call :configure_env

:done
echo.
call :msg done
echo [OK]    !M!
for /f "usebackq delims=" %%v in (`node --version 2^>nul`) do set "CUR_VER=%%v"
if defined CUR_VER (
    call :msg node_version "%CUR_VER%"
    echo [INFO] !M!
) else (
    call :msg node_version "unknown"
    echo [INFO] !M!
)

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

rem ---- detect Node: errorlevel 2=already ok, 1=needs install ----
:detect_node
where node >nul 2>nul
if errorlevel 1 goto :no_node
for /f "usebackq delims=" %%v in (`node --version 2^>nul`) do set "NV=%%v"
if not defined NV goto :no_node
set "NODE_VERSION=%NV:~1%"
set "MAJOR=%NV:~1%"
for /f "tokens=1 delims=." %%m in ("%MAJOR%") do set "NODE_MAJOR=%%m"
if not defined NODE_MAJOR goto :no_node
if %NODE_MAJOR% GEQ %MIN_MAJOR% goto :node_ok
call :msg node_low "%NODE_VERSION%" "%MIN_MAJOR%"
echo [WARN] !M!
exit /b 1
:node_ok
call :msg node_ok "%NODE_VERSION%" "%MIN_MAJOR%"
echo [OK]    !M!
exit /b 2
:no_node
call :msg node_not_found
echo [INFO] !M!
exit /b 1

rem ---- detect nvm ----
:detect_nvm
where nvm >nul 2>nul
if not errorlevel 1 exit /b 0
if defined NVM_HOME (
    if exist "%NVM_HOME%\nvm.exe" exit /b 0
)
exit /b 1

rem ---- nvm install ----
:nvm_install
nvm list 2>nul | findstr /C:"%NVM_VERSION%" >nul
if not errorlevel 1 (
    call :msg nvm_installed "%NVM_VERSION%"
    echo [INFO] !M!
) else (
    call :msg nvm_install_run "%NVM_VERSION%"
    echo [INFO] !M!
    nvm install %NVM_VERSION%
    if errorlevel 1 exit /b 1
)
call :msg nvm_use_run "%NVM_VERSION%"
echo [INFO] !M!
nvm use %NVM_VERSION%
if errorlevel 1 (
    call :msg nvm_use_fail "%NVM_VERSION%"
    echo [WARN] !M!
    exit /b 1
)
exit /b 0

rem ---- detect platform arch ----
:detect_arch
set "NODE_ARCH=x64"
if /i "%PROCESSOR_ARCHITECTURE%"=="ARM64" set "NODE_ARCH=arm64"
if /i "%PROCESSOR_ARCHITECTURE%"=="x86" set "NODE_ARCH=x86"
exit /b 0

rem ---- download zip then extract to INSTALL_DIR ----
:download_and_extract
call :detect_arch
call :msg platform "win" "%NODE_ARCH%"
echo [INFO] !M!
set "DIST_URL=%BASE_URL%/%VERSION%/node-%VERSION%-win-%NODE_ARCH%.zip"

rem locate a downloader: curl.exe > certutil > bitsadmin
set "DL_TOOL="
where curl.exe >nul 2>nul && set "DL_TOOL=curl"
if not defined DL_TOOL (
    where certutil >nul 2>nul && set "DL_TOOL=certutil"
)
if not defined DL_TOOL (
    where bitsadmin >nul 2>nul && set "DL_TOOL=bitsadmin"
)
if not defined DL_TOOL (
    echo [ERROR] No downloader available: curl/certutil/bitsadmin. Cannot download Node.js.
    exit /b 1
)

set "TMPZIP=%SCRIPT_DIR%node-%VERSION%-win-%NODE_ARCH%.zip"
if exist "%TMPZIP%" del /f /q "%TMPZIP%" >nul 2>nul

call :msg downloading "%DIST_URL%"
echo [INFO] !M!
if "%DL_TOOL%"=="curl" (
    curl.exe -L --fail --progress-bar -o "%TMPZIP%" "%DIST_URL%"
    if errorlevel 1 (
        call :msg download_fail "%DIST_URL%"
        echo [ERROR] !M!
        exit /b 1
    )
) else if "%DL_TOOL%"=="certutil" (
    certutil -urlcache -split -f "%DIST_URL%" "%TMPZIP%" >nul
    if errorlevel 1 (
        call :msg download_fail "%DIST_URL%"
        echo [ERROR] !M!
        exit /b 1
    )
) else (
    bitsadmin /transfer dsh /download /priority normal "%DIST_URL%" "%TMPZIP%" >nul
    if errorlevel 1 (
        call :msg download_fail "%DIST_URL%"
        echo [ERROR] !M!
        exit /b 1
    )
)

call :msg mkdir "%INSTALL_DIR%"
echo [INFO] !M!
if not exist "%INSTALL_DIR%" mkdir "%INSTALL_DIR%"

call :msg extracting
echo [INFO] !M!
rem Prefer the system tar (libarchive), as PATH may contain a GNU tar that
rem misinterprets "C:\..." paths as a remote address.
set "SYS_TAR=%SystemRoot%\System32\tar.exe"
if exist "%SYS_TAR%" (
    set "TAR_CMD=%SYS_TAR%"
) else (
    where tar.exe >nul 2>nul
    if errorlevel 1 (
        echo [ERROR] tar.exe not found. Cannot extract zip without tar/PowerShell.
        echo [ERROR] Please extract node-%VERSION%-win-%NODE_ARCH%.zip manually into %INSTALL_DIR%
        exit /b 1
    )
    set "TAR_CMD=tar.exe"
)
set "EXTRACT_DIR=%TEMP%\node-extract-%RANDOM%"
if exist "%EXTRACT_DIR%" rmdir /s /q "%EXTRACT_DIR%" >nul 2>nul
mkdir "%EXTRACT_DIR%"
"%TAR_CMD%" -xf "%TMPZIP%" -C "%EXTRACT_DIR%"
if errorlevel 1 (
    call :msg extract_fail "%TMPZIP%"
    echo [ERROR] !M!
    rmdir /s /q "%EXTRACT_DIR%" >nul 2>nul
    del /f /q "%TMPZIP%" >nul 2>nul
    exit /b 1
)
rem move extracted node-xxx-win-xxx\* into INSTALL_DIR
for /d %%d in ("%EXTRACT_DIR%\node-%VERSION%-win-%NODE_ARCH%") do set "SRC=%%d"
if not defined SRC (
    echo [ERROR] Expected directory not found in archive.
    rmdir /s /q "%EXTRACT_DIR%" >nul 2>nul
    exit /b 1
)
xcopy /e /i /q /y "%SRC%\*" "%INSTALL_DIR%\" >nul 2>nul
rmdir /s /q "%EXTRACT_DIR%" >nul 2>nul
del /f /q "%TMPZIP%" >nul 2>nul

if exist "%INSTALL_DIR%\node.exe" (
    call :msg installed "%INSTALL_DIR%"
    echo [OK]    !M!
    exit /b 0
) else (
    call :msg exe_not_found "%INSTALL_DIR%"
    echo [WARN] !M!
    exit /b 0
)

rem ---- configure PATH (user + current session) ----
:configure_env
call :msg env_writing
echo [INFO] !M!
set "CURRENT_PATH=%PATH%"
echo %CURRENT_PATH% | findstr /I /C:"%INSTALL_DIR%" >nul
if errorlevel 1 (
    where setx >nul 2>nul
    if not errorlevel 1 (
        setx PATH "%INSTALL_DIR%;%PATH%" >nul 2>nul
        if errorlevel 1 (
            call :msg winpath_fail "%INSTALL_DIR%"
            echo [WARN] !M!
        ) else (
            call :msg winpath_updated "%INSTALL_DIR%"
            echo [OK]    !M!
        )
    ) else (
        call :msg winpath_fail "%INSTALL_DIR%"
        echo [WARN] !M!
    )
) else (
    call :msg winpath_already "%INSTALL_DIR%"
    echo [INFO] !M!
)
set "PATH=%INSTALL_DIR%;%PATH%"
call :msg env_session_ok "%INSTALL_DIR%;%PATH%"
echo [OK]    !M!
exit /b 0

rem ---- debug mode: strip nvm/node entries from current PATH ----
:remove_node_from_path
call :msg debug_scan
echo [INFO] !M!
set "KEPT="
set "REMOVED="
for %%p in ("%PATH:;=" "%") do (
    set "PI=%%~p"
    if /i not "!PI:nvm=!"=="!PI!" (
        call :msg removing "!PI!"
        echo [WARN] !M!
        set "REMOVED=!REMOVED!;!PI!"
    ) else if /i not "!PI:node=!"=="!PI!" (
        call :msg removing "!PI!"
        echo [WARN] !M!
        set "REMOVED=!REMOVED!;!PI!"
    ) else (
        set "KEPT=!KEPT!;!PI!"
    )
)
if defined REMOVED (
    set "PATH=!KEPT!"
    call :msg removed
    echo [INFO] !M!
) else (
    call :msg nothing_removed
    echo [INFO] !M!
)
exit /b 0

:show_help
call :msg usage_usage "%SELF%"
echo !M!
call :msg usage_dir & echo !M!
call :msg usage_noenv & echo !M!
call :msg usage_dryrun & echo !M!
call :msg usage_debug & echo !M!
call :msg usage_help & echo !M!
call :msg usage_nopause & echo !M!
exit /b 0

:finish
if "%NO_PAUSE%"=="1" exit /b 0
echo.
echo Press any key to close this window...
pause >nul
exit /b 0
