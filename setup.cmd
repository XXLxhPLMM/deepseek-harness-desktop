@echo off
rem ============================================================================
rem  setup.cmd  -  Windows cmd native setup for the whole toolchain
rem
rem  Detects/installs nvm -> node -> (npm taobao mirror + nrm) -> dsh level by level.
rem  Refuses to reinstall anything that is already present. Detection/install only.
rem
rem  Pure cmd implementation, does NOT require PowerShell.
rem  Detects Node.js >= 22, installs via nvm if available, otherwise downloads
rem  from nodejs.org and extracts to the script directory. Installs dsh via npm.
rem
rem  Usage:
rem    setup.cmd                default install dir (script dir\nodejs)
rem    setup.cmd --dir C:\path  custom install dir
rem    setup.cmd --no-env       do not modify PATH
rem    setup.cmd --dry-run      detect only, do not install
rem    setup.cmd --debug        isolated session-only install into script dir
rem    setup.cmd --help         show help
rem    setup.cmd /nopause       exit without pausing (for double-click)
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
set "DSH_PKG=@deepseek-ai/dsh"
set "NPM_REGISTRY=https://registry.npmmirror.com"
set "NRM_PKG=nrm"

rem ---- defaults ----
set "INSTALL_DIR=%SCRIPT_DIR%nodejs"
set "DO_ENV=1"
set "DRY_RUN=0"
set "DEBUG_MODE=0"
set "NO_PAUSE=0"
set "EXIT_CODE=0"

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

rem ============================================================================
rem  Main flow: nvm -> node -> dsh (refuse duplicate install)
rem ============================================================================
call :msg main_title
echo [INFO] !M!

if "%DEBUG_MODE%"=="1" (
    call :msg debug_title "%INSTALL_DIR%"
    echo [INFO] !M!
    call :remove_node_from_path
    set "INSTALL_DIR=%SCRIPT_DIR%nodejs"
)

rem ---- level 1: nvm (detect only, never install) ----
call :detect_nvm
if not errorlevel 1 (
    call :msg nvm_found
    echo [OK]    !M!
)

rem ---- level 2: node (skip if already ok) ----
call :ensure_node
if errorlevel 1 (
    set "EXIT_CODE=1"
    goto :finish
)

rem ---- level 2.5: migrate user-level node/nvm dirs to system PATH (admin only) ----
call :promote_node_path

rem ---- level 2.6: npm taobao mirror + global nrm (node must be ready) ----
call :ensure_npm_mirror

rem ---- level 3: dsh (skip if already ok) ----
call :ensure_dsh
if errorlevel 1 (
    set "EXIT_CODE=1"
    goto :finish
)
set "EXIT_CODE=0"
rem ---- environment (only when we installed node ourselves; system node untouched) ----
if "%NODE_INSTALLED%"=="1" (
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
    if "%NODE_METHOD%"=="nvm" (
        rem node installed via nvm: nvm manages PATH, INSTALL_DIR was never created
        call :msg env_nvm_skip
        echo [INFO] !M!
        goto :done
    )
    call :configure_env
)

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
rem  Subroutines (called from main flow before :finish)
rem ============================================================================

rem ---- configure PATH (system + current session, requires admin) ----
:configure_env
if "%DRY_RUN%"=="1" (
    call :msg dryrun_skip
    echo [INFO] !M!
    exit /b 0
)
call :msg env_writing
echo [INFO] !M!
rem System PATH write requires administrator rights. Without them, warn and only
rem update the current session (node/dsh still usable in this terminal).
net session >nul 2>nul
if errorlevel 1 goto :no_admin
rem Write the Windows system PATH (HKLM\...\Session Manager\Environment) via reg
rem instead of setx: setx has a 1024-char limit and silently fails on real-world
rem long PATHs, leaving the env var unwritten. Pure cmd, no PowerShell dependency.
set "REG_PATH_FILE=%TEMP%\sn_path.txt"
reg query "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" /v Path > "%REG_PATH_FILE%" 2>nul
set "CURTYPE="
set "CURPATH="
if exist "%REG_PATH_FILE%" (
    for /f "usebackq skip=2 tokens=1,2,*" %%a in ("%REG_PATH_FILE%") do (
        set "CURTYPE=%%b"
        set "CURPATH=%%c"
    )
)
del /f /q "%REG_PATH_FILE%" >nul 2>nul
rem reg query wraps the REG_SZ/REG_EXPAND_SZ value in double quotes for display;
rem strip them (PATH entries never contain double quotes, deleting is safe).
if defined CURPATH set "CURPATH=!CURPATH:"=!"
if not defined CURTYPE set "CURTYPE=REG_EXPAND_SZ"
if defined CURPATH (
    rem Substring check via variable substitution (no echo/findstr pipe, so it
    rem survives very long PATHs that would overflow echo). INSTALL_DIR contains
    rem no % or !, so substitution is safe.
    if not "!CURPATH:%INSTALL_DIR%=!"=="!CURPATH!" (
        call :msg winpath_already "%INSTALL_DIR%"
        echo [INFO] !M!
    ) else (
        reg add "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" /v Path /t !CURTYPE! /d "%INSTALL_DIR%;!CURPATH!" /f >nul 2>nul
        if errorlevel 1 (
            call :msg winpath_fail "%INSTALL_DIR%"
            echo [WARN] !M!
        ) else (
            call :msg winpath_updated "%INSTALL_DIR%"
            echo [OK]    !M!
            set "BCAST=1"
        )
    )
) else (
    reg add "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" /v Path /t !CURTYPE! /d "%INSTALL_DIR%" /f >nul 2>nul
    if errorlevel 1 (
        call :msg winpath_fail "%INSTALL_DIR%"
        echo [WARN] !M!
    ) else (
        call :msg winpath_updated "%INSTALL_DIR%"
        echo [OK]    !M!
        set "BCAST=1"
    )
)
set "PATH=%INSTALL_DIR%;%PATH%"
rem Notify running processes (Explorer) so newly opened terminals pick up the
rem updated system PATH without waiting for the next sign-in.
if defined BCAST call :broadcast_env
call :msg env_session_ok "%INSTALL_DIR%;%PATH%"
echo [OK]    !M!
exit /b 0

:no_admin
call :msg env_no_admin "%INSTALL_DIR%"
echo [WARN] !M!
call :msg noenv_manual "%INSTALL_DIR%"
echo [INFO] !M!
set "PATH=%INSTALL_DIR%;%PATH%"
call :msg env_session_ok "%INSTALL_DIR%;%PATH%"
echo [OK]    !M!
exit /b 0

rem ---- migrate user-level node/nvm dirs into the system PATH (admin only) ----
rem If node/nvm live only in the user PATH, the SYSTEM account cannot see them
rem and the dsh web service (run as SYSTEM) cannot start. When running with
rem admin rights in a normal (non-debug, non-dry-run, no --no-env) run, move
rem those dirs from the user PATH into the system PATH and drop them from the
rem user PATH. Pure cmd, no PowerShell dependency.
:promote_node_path
if "%DEBUG_MODE%"=="1" exit /b 0
if "%DRY_RUN%"=="1" exit /b 0
if "%DO_ENV%"=="0" exit /b 0
net session >nul 2>nul
if errorlevel 1 exit /b 0
set "REG_PATH_FILE=%TEMP%\sn_promote.txt"
reg query "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" /v Path > "%REG_PATH_FILE%" 2>nul
set "MACHINE_PATH="
set "MACHINE_TYPE=REG_EXPAND_SZ"
if exist "%REG_PATH_FILE%" (
    for /f "usebackq skip=2 tokens=1,2,*" %%a in ("%REG_PATH_FILE%") do (
        set "MACHINE_TYPE=%%b"
        set "MACHINE_PATH=%%c"
    )
)
del /f /q "%REG_PATH_FILE%" >nul 2>nul
reg query "HKCU\Environment" /v Path > "%REG_PATH_FILE%" 2>nul
set "USER_PATH="
set "USER_TYPE=REG_EXPAND_SZ"
if exist "%REG_PATH_FILE%" (
    for /f "usebackq skip=2 tokens=1,2,*" %%a in ("%REG_PATH_FILE%") do (
        set "USER_TYPE=%%b"
        set "USER_PATH=%%c"
    )
)
del /f /q "%REG_PATH_FILE%" >nul 2>nul
if defined MACHINE_PATH set "MACHINE_PATH=!MACHINE_PATH:"=!"
if defined USER_PATH set "USER_PATH=!USER_PATH:"=!"
if not defined USER_PATH exit /b 0
for %%c in (node nvm) do (
    set "PROG="
    for /f "usebackq delims=" %%v in (`where %%c 2^>nul`) do if not defined PROG set "PROG=%%v"
    if defined PROG (
        for %%I in ("!PROG!") do set "PROG_DIR=%%~dpI"
        call :promote_one_dir "!PROG_DIR!"
    )
)
exit /b 0

:promote_one_dir
set "D=%~1"
if "%D%"=="" exit /b 0
if "!D:~-1!"=="\" set "D=!D:~0,-1!"
rem already in the system PATH?
set "CHECK=!MACHINE_PATH:%D%=!"
if not "!CHECK!"=="!MACHINE_PATH!" (
    rem system has it: drop the duplicate from the user PATH if present
    set "CHECK=!USER_PATH:%D%=!"
    if not "!CHECK!"=="!USER_PATH!" (
        set "USER_PATH=!USER_PATH:%D%;=!"
        set "USER_PATH=!USER_PATH:;%D%=!"
        set "USER_PATH=!USER_PATH:%D%=!"
        if "!USER_PATH!"=="" (
            reg delete "HKCU\Environment" /v Path /f >nul 2>nul
        ) else (
            reg add "HKCU\Environment" /v Path /t !USER_TYPE! /d "!USER_PATH!" /f >nul 2>nul
        )
        call :broadcast_env
        call :msg env_promote_clean "%D%"
        echo [INFO] !M!
    )
    exit /b 0
)
rem only in the user PATH: move it into the system PATH
set "CHECK=!USER_PATH:%D%=!"
if not "!CHECK!"=="!USER_PATH!" (
    set "NM=!D!;!MACHINE_PATH!"
    if "!NM!"=="!D!;" set "NM=!D!"
    reg add "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" /v Path /t !MACHINE_TYPE! /d "!NM!" /f >nul 2>nul
    if errorlevel 1 (
        call :msg env_promote_fail "%D%"
        echo [WARN] !M!
        exit /b 0
    )
    set "MACHINE_PATH=!NM!"
    set "USER_PATH=!USER_PATH:%D%;=!"
    set "USER_PATH=!USER_PATH:;%D%=!"
    set "USER_PATH=!USER_PATH:%D%=!"
    if "!USER_PATH!"=="" (
        reg delete "HKCU\Environment" /v Path /f >nul 2>nul
    ) else (
        reg add "HKCU\Environment" /v Path /t !USER_TYPE! /d "!USER_PATH!" /f >nul 2>nul
    )
    call :broadcast_env
    call :msg env_promoted "%D%"
    echo [OK]    !M!
)
exit /b 0

rem ---- broadcast WM_SETTINGCHANGE("Environment") after the PATH change ----
rem reg.exe writes the system PATH (HKLM\...\Session Manager\Environment) but
rem never notifies running processes, so Explorer keeps the old environment and
rem every newly opened terminal (a child of Explorer) inherits the stale PATH
rem until the next sign-in - exactly the "works only in the current session"
rem symptom. PowerShell's SetEnvironmentVariable broadcasts automatically;
rem replicate that here.
rem Best effort only: stay silent when powershell is unavailable, the PATH
rem change then simply applies at the next logon.
:broadcast_env
powershell -NoProfile -Command "Add-Type -MemberDefinition '[DllImport(\"user32.dll\", SetLastError=true, CharSet=CharSet.Auto)] public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam, uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);' -Name NativeMethods -Namespace Win32; $r=[UIntPtr]::Zero; [Win32.NativeMethods]::SendMessageTimeout([IntPtr]0xffff, 0x1a, [UIntPtr]::Zero, 'Environment', 2, 5000, [ref]$r) | Out-Null" >nul 2>nul
exit /b 0

goto :finish

rem ============================================================================
rem  Subroutines (only called from other subroutines)
rem ============================================================================

rem ---- message lookup: call :msg <key> <arg1> <arg2>; result in M ----
:msg
set "M=!MSG_%~1!"
set "M=!M:{1}=%~2!"
set "M=!M:{2}=%~3!"
:msg_ret
exit /b 0

rem ---- detect nvm: errorlevel 0=found, 1=not found ----
:detect_nvm
if "%DEBUG_MODE%"=="1" exit /b 1
where nvm >nul 2>nul
if not errorlevel 1 exit /b 0
if defined NVM_HOME (
    if exist "%NVM_HOME%\nvm.exe" exit /b 0
)
exit /b 1

rem ---- ensure node is ready: errorlevel 0=ok, 1=failed ----
rem Sets NODE_INSTALLED=1 when it actually installs a fresh node.
:ensure_node
set "NODE_INSTALLED=0"
set "NODE_METHOD=direct"
call :detect_node
if not errorlevel 1 exit /b 0
if "%DRY_RUN%"=="1" (
    call :msg dryrun_skip
    echo [INFO] !M!
    exit /b 1
)
set "NODE_DONE=0"
if "%DEBUG_MODE%"=="1" (
    call :msg debug_skip_nvm
    echo [INFO] !M!
    call :download_and_extract
    if errorlevel 1 (
        call :msg install_failed
        echo [ERROR] !M!
        exit /b 1
    )
    set "NODE_DONE=1"
    goto :node_installed
)
call :detect_nvm
if not errorlevel 1 (
    call :msg nvm_using "%NVM_VERSION%"
    echo [INFO] !M!
    call :nvm_install
    if not errorlevel 1 (
        set "NODE_DONE=1"
        set "NODE_METHOD=nvm"
        goto :node_installed
    )
    call :msg nvm_fail_fallback
    echo [WARN] !M!
)
call :msg no_nvm
echo [INFO] !M!
call :download_and_extract
if errorlevel 1 (
    call :msg install_failed
    echo [ERROR] !M!
    exit /b 1
)
set "NODE_DONE=1"
:node_installed
set "NODE_INSTALLED=1"
exit /b 0

rem ---- ensure dsh is ready: errorlevel 0=ok, 1=failed ----
:ensure_dsh
call :detect_dsh
if not errorlevel 1 exit /b 0
if "%DRY_RUN%"=="1" (
    call :msg dryrun_skip
    echo [INFO] !M!
    exit /b 1
)
call :install_dsh
exit /b

rem ---- detect node: errorlevel 0=ok (>=22), 1=missing/too old ----
:detect_node
set "NODE_VERSION="
set "NODE_MAJOR="
if "%DEBUG_MODE%"=="1" (
    if exist "%INSTALL_DIR%\node.exe" (
        set "PATH=%INSTALL_DIR%;%PATH%"
        for /f "usebackq delims=" %%v in (`node --version 2^>nul`) do set "NV=%%v"
        if defined NV (
            set "NODE_VERSION=!NV:~1!"
            for /f "tokens=1 delims=." %%m in ("!NODE_VERSION!") do set "NODE_MAJOR=%%m"
            goto :node_version_done
        )
    )
    goto :no_node
)
where node >nul 2>nul
if errorlevel 1 goto :no_node
for /f "usebackq delims=" %%v in (`node --version 2^>nul`) do set "NV=%%v"
if not defined NV goto :no_node
set "NODE_VERSION=%NV:~1%"
for /f "tokens=1 delims=." %%m in ("%NODE_VERSION%") do set "NODE_MAJOR=%%m"
:node_version_done
if not defined NODE_MAJOR goto :no_node
if %NODE_MAJOR% GEQ %MIN_MAJOR% goto :node_ok
call :msg node_low "%NODE_VERSION%" "%MIN_MAJOR%"
echo [WARN] !M!
exit /b 1
:node_ok
call :msg node_ok "%NODE_VERSION%" "%MIN_MAJOR%"
echo [OK]    !M!
exit /b 0
:no_node
call :msg node_not_found
echo [INFO] !M!
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
rem In a 32-bit cmd, PROCESSOR_ARCHITECTURE wrongly reports x86 on a 64-bit
rem system; PROCESSOR_ARCHITEW6432 then carries the real architecture, prefer it.
:detect_arch
set "NODE_ARCH=x64"
if defined PROCESSOR_ARCHITEW6432 (
    if /i "%PROCESSOR_ARCHITEW6432%"=="ARM64" set "NODE_ARCH=arm64"
) else (
    if /i "%PROCESSOR_ARCHITECTURE%"=="ARM64" set "NODE_ARCH=arm64"
    if /i "%PROCESSOR_ARCHITECTURE%"=="x86" set "NODE_ARCH=x86"
)
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

rem ---- detect dsh: errorlevel 0=found, 1=not found ----
rem (debug mode: PATH already points to the script-dir node global, same view)
:detect_dsh
set "DSH_FOUND=0"
where dsh >nul 2>nul
if not errorlevel 1 (
    call :msg dsh_ok
    echo [OK]    !M!
    exit /b 0
)
exit /b 1

rem ---- install dsh ----
:install_dsh
call :msg dsh_not_found
echo [INFO] !M!
call :msg dsh_install
echo [INFO] !M!
rem run npm in a child cmd: npm.cmd's internal goto would corrupt the parent
rem batch's label tracking when invoked from a call :label subroutine
cmd /c npm install -g "%DSH_PKG%"
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
call :msg dsh_done
echo [OK]    !M!
exit /b 0
:dsh_fail
call :msg dsh_fail "%DSH_PKG%"
echo [ERROR] !M!
exit /b 1

rem ---- ensure npm registry (taobao mirror) + global nrm: always errorlevel 0 ----
:ensure_npm_mirror
rem ensure npm is available in this session (PATH not yet updated after fresh node install)
set "NPM_FOUND="
where npm >nul 2>nul && set "NPM_FOUND=1"
if not defined NPM_FOUND if exist "%INSTALL_DIR%\npm.cmd" set "PATH=%INSTALL_DIR%;%PATH%"
rem debug mode: use session-only env vars, do not touch the user npm config.
rem The global prefix must be overridden too, otherwise a prefix= in the user
rem npmrc redirects npm install -g to the user global (e.g. the nvm-managed
rem system node), breaking the isolation.
if "%DEBUG_MODE%"=="1" set "npm_config_registry=%NPM_REGISTRY%"
if "%DEBUG_MODE%"=="1" set "npm_config_prefix=%INSTALL_DIR%"

if "%DRY_RUN%"=="1" (
    where nrm >nul 2>nul
    if not errorlevel 1 (
        call :msg nrm_ok
        echo [OK]    !M!
    ) else (
        call :msg dryrun_skip
        echo [INFO] !M!
    )
    set "CUR_REG="
    for /f "usebackq delims=" %%r in (`npm config get registry 2^>nul`) do set "CUR_REG=%%r"
    echo !CUR_REG! | findstr /I "npmmirror" >nul
    if not errorlevel 1 (
        call :msg registry_already "!CUR_REG!"
        echo [OK]    !M!
    ) else (
        call :msg dryrun_skip
        echo [INFO] !M!
    )
    exit /b 0
)

if "%DEBUG_MODE%"=="1" (
    call :msg registry_set_session "%NPM_REGISTRY%"
    echo [INFO] !M!
) else (
    set "CUR_REG="
    for /f "usebackq delims=" %%r in (`npm config get registry 2^>nul`) do set "CUR_REG=%%r"
    echo !CUR_REG! | findstr /I "npmmirror" >nul
    if not errorlevel 1 (
        call :msg registry_already "!CUR_REG!"
        echo [OK]    !M!
    ) else (
        cmd /c npm config set registry "%NPM_REGISTRY%" >nul 2>nul
        if errorlevel 1 (
            call :msg registry_fail "%NPM_REGISTRY%"
            echo [WARN] !M!
        ) else (
            call :msg registry_set "%NPM_REGISTRY%"
            echo [OK]    !M!
        )
    )
)

where nrm >nul 2>nul
if not errorlevel 1 (
    call :msg nrm_ok
    echo [OK]    !M!
    exit /b 0
)
call :msg nrm_install
echo [INFO] !M!
cmd /c npm install -g "%NRM_PKG%" >nul 2>nul
if errorlevel 1 (
    call :msg nrm_fail "%NRM_PKG%"
    echo [WARN] !M!
) else (
    call :msg nrm_done
    echo [OK]    !M!
)
exit /b 0

rem ---- debug mode: strip nvm/node entries from current PATH ----
:remove_node_from_path
call :msg debug_scan
echo [INFO] !M!
set "KEPT="
set "REMOVED="
for %%p in ("%PATH:;=" "%") do (
    set "PI=%%~p"
    set "MATCHED="
    if /i not "!PI:nvm=!"=="!PI!" set "MATCHED=1"
    if not defined MATCHED if /i not "!PI:node=!"=="!PI!" set "MATCHED=1"
    if defined MATCHED (
        rem report each unique removed path once (PATH may hold duplicates)
        echo(!REMOVED! | findstr /I /C:";!PI!;" >nul 2>nul
        if errorlevel 1 (
            call :msg removing "!PI!"
            echo [WARN] !M!
            set "REMOVED=!REMOVED!;!PI!;"
        )
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
if not defined EXIT_CODE set "EXIT_CODE=0"
rem Keep session changes when called via "call setup.cmd --debug" (activate
rem current cmd session): endlocal & set the key vars with the inner values.
rem %KEEP_*% expand during line parse (before endlocal) so they carry the
rem inner values; npm_config_* only exist in debug mode.
set "KEEP_PATH=%PATH%"
set "KEEP_REG=%npm_config_registry%"
set "KEEP_PFX=%npm_config_prefix%"
endlocal & set "PATH=%KEEP_PATH%" & set "npm_config_registry=%KEEP_REG%" & set "npm_config_prefix=%KEEP_PFX%"
exit /b %EXIT_CODE%
