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
rem ============================================================================
setlocal EnableExtensions EnableDelayedExpansion

set "SCRIPT_DIR=%~dp0"
set "VERSION=v22.23.2"
set "NVM_VERSION=22.23.2"
set "MIN_MAJOR=22"
set "BASE_URL=https://nodejs.org/dist"

rem ---- defaults ----
set "INSTALL_DIR=%SCRIPT_DIR%nodejs"
set "DO_ENV=1"
set "DRY_RUN=0"
set "DEBUG_MODE=0"
set "NO_PAUSE=0"

rem Switch console to UTF-8 so output renders correctly (best effort)
chcp 65001 >nul 2>nul

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
echo [WARN] Unknown argument: %~1
shift /1
goto :parse
:set_dir
if "%~2"=="" ( echo [ERROR] --dir requires a path value & exit /b 1 )
set "ARG_DIR=%~2"
set "HAS_DIR=1"
shift /1
shift /1
goto :parse
:args_done

if "%HAS_DIR%"=="1" set "INSTALL_DIR=%ARG_DIR%"

rem ---- command aliases (allow --flag style) ----
set "P_ECHO=echo"
set "P_EXIT=exit /b"

if "%DEBUG_MODE%"=="1" (
    echo [INFO] === Debug mode enabled: install dir = %INSTALL_DIR% ===
    call :remove_node_from_path
)

rem ---- detect existing Node ----
call :detect_node
if errorlevel 2 exit /b 0
if errorlevel 1 goto :need_install

:already_ok
echo [OK]    Node.js is already installed and satisfies the requirement.
exit /b 0

:need_install
if "%DRY_RUN%"=="1" (
    echo [INFO] --dry-run mode, skipping installation
    exit /b 1
)

rem ---- choose install path ----
if "%DEBUG_MODE%"=="1" (
    echo [INFO] Debug mode: skipping nvm, direct download...
    call :download_and_extract
    if errorlevel 1 goto :install_failed
    goto :env_setup
)

rem ---- try nvm ----
call :detect_nvm
if errorlevel 1 goto :no_nvm

echo [INFO] nvm detected, installing Node.js %NVM_VERSION% via nvm...
call :nvm_install
if errorlevel 1 (
    echo [WARN] nvm install failed, falling back to official download...
    goto :no_nvm
)
set "INSTALLED_BY_NVM=1"
goto :env_setup

:no_nvm
echo [INFO] nvm not detected, using official download...
call :download_and_extract
if errorlevel 1 goto :install_failed

:install_failed
echo [ERROR] Node.js installation failed. Please check your network.
exit /b 1

:env_setup
if "%DEBUG_MODE%"=="1" (
    echo [INFO] Debug mode: only updating current session PATH, not persistent.
    set "PATH=%INSTALL_DIR%;%PATH%"
    goto :done
)
if "%DO_ENV%"=="0" (
    echo [INFO] --no-env specified, skipping PATH configuration.
    echo [WARN] Please add %INSTALL_DIR% to your PATH manually.
    goto :done
)
call :configure_env

:done
echo.
echo [OK]    Done! Please reopen your terminal for changes to take effect.
for /f "usebackq delims=" %%v in (`node --version 2^>nul`) do set "CUR_VER=%%v"
if defined CUR_VER ( echo [INFO] Current Node version: %CUR_VER% ) else ( echo [INFO] Current Node version: unknown )

goto :finish

rem ============================================================================
rem  Subroutines
rem ============================================================================

rem ---- detect Node: errorlevel 2=already ok, 1=needs install ----
:detect_node
where node >nul 2>nul
if errorlevel 1 goto :no_node
for /f "usebackq delims=" %%v in (`node --version 2^>nul`) do set "NV=%%v"
if not defined NV goto :no_node
set "NODE_VERSION=%NV%"
set "MAJOR=%NV:~1%"
for /f "tokens=1 delims=." %%m in ("%MAJOR%") do set "NODE_MAJOR=%%m"
if not defined NODE_MAJOR goto :no_node
if %NODE_MAJOR% GEQ %MIN_MAJOR% goto :node_ok
echo [WARN] Detected Node.js %NODE_VERSION%, but below %MIN_MAJOR%, need to install new version.
exit /b 1
:node_ok
echo [OK]    Detected Node.js %NODE_VERSION%, nothing to do.
exit /b 2
:no_node
echo [INFO] Node.js not detected, starting installation...
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
    echo [INFO] Node %NVM_VERSION% already installed in nvm, switching...
) else (
    echo [INFO] Running: nvm install %NVM_VERSION% ...
    nvm install %NVM_VERSION%
    if errorlevel 1 exit /b 1
)
nvm use %NVM_VERSION%
if errorlevel 1 (
    echo [WARN] nvm use may require administrator rights. Run manually: nvm use %NVM_VERSION%
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
echo [INFO] Platform: win / %NODE_ARCH%
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

echo [INFO] Downloading %DIST_URL% ...
if "%DL_TOOL%"=="curl" (
    curl.exe -L --fail --progress-bar -o "%TMPZIP%" "%DIST_URL%"
    if errorlevel 1 (
        echo [ERROR] Download failed: %DIST_URL%
        exit /b 1
    )
) else if "%DL_TOOL%"=="certutil" (
    certutil -urlcache -split -f "%DIST_URL%" "%TMPZIP%" >nul
    if errorlevel 1 (
        echo [ERROR] Download failed: %DIST_URL%
        exit /b 1
    )
) else (
    bitsadmin /transfer dsh /download /priority normal "%DIST_URL%" "%TMPZIP%" >nul
    if errorlevel 1 (
        echo [ERROR] Download failed: %DIST_URL%
        exit /b 1
    )
)

echo [INFO] Creating install directory: %INSTALL_DIR%
if not exist "%INSTALL_DIR%" mkdir "%INSTALL_DIR%"

echo [INFO] Extracting...
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
    echo [ERROR] Extraction failed.
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
    echo [OK]    Node.js installed to %INSTALL_DIR%
    exit /b 0
) else (
    echo [WARN] Extracted, but node.exe not found. Please check %INSTALL_DIR%
    exit /b 0
)

rem ---- configure PATH (user + current session) ----
:configure_env
set "CURRENT_PATH=%PATH%"
echo %CURRENT_PATH% | findstr /I /C:"%INSTALL_DIR%" >nul
if errorlevel 1 (
    where setx >nul 2>nul
    if not errorlevel 1 (
        setx PATH "%INSTALL_DIR%;%PATH%" >nul 2>nul
        if errorlevel 1 (
            echo [WARN] setx failed, please add %INSTALL_DIR% to PATH manually.
        ) else (
            echo [OK]    Added %INSTALL_DIR% to user PATH.
        )
    ) else (
        echo [WARN] setx not found, please add %INSTALL_DIR% to PATH manually.
    )
) else (
    echo [INFO] PATH already contains %INSTALL_DIR%, skipping.
)
set "PATH=%INSTALL_DIR%;%PATH%"
echo [OK]    Current session PATH updated.
exit /b 0

rem ---- debug mode: strip nvm/node entries from current PATH ----
:remove_node_from_path
echo [INFO] Debug mode: scanning PATH for nvm/node entries...
set "KEPT="
set "REMOVED="
for %%p in ("%PATH:;=" "%") do (
    set "PI=%%~p"
    if /i not "!PI:nvm=!"=="!PI!" (
        echo [WARN]  Removing: !PI!
        set "REMOVED=!REMOVED!;!PI!"
    ) else if /i not "!PI:node=!"=="!PI!" (
        echo [WARN]  Removing: !PI!
        set "REMOVED=!REMOVED!;!PI!"
    ) else (
        set "KEPT=!KEPT!;!PI!"
    )
)
if defined REMOVED (
    set "PATH=!KEPT!"
    echo [INFO] Removed nvm/node entries from current session PATH.
) else (
    echo [INFO] No nvm/node entries found in current session PATH.
)
exit /b 0

:show_help
echo Usage: setup-node.cmd [options]
echo   --dir ^<path^>    custom install directory (default: nodejs under script dir)
echo   --no-env        do not modify PATH
echo   --dry-run       detect only, do not install
echo   --debug         isolated verification install into script dir\nodejs
echo   --help          show this help
echo   /nopause        exit without pausing the window
exit /b 0

:finish
if "%NO_PAUSE%"=="1" exit /b 0
echo.
echo Press any key to close this window...
pause >nul
exit /b 0
