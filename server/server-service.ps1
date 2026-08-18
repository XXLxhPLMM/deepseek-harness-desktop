# server-service.ps1
# 把 deepseek harness 的 `dsh web` 安装/管理为开机自启任务（开机自动启动）。
# 采用 计划任务 (schtasks) + 运行包装脚本 (run-dsh-web.cmd) 的方式，任务命令
# 很短（cmd /c 包装脚本），真实命令在包装脚本里；非 debug 模式直接调用 PATH
# 中的 `dsh web`，debug 模式才用脚本目录 nodejs 的绝对路径：
#     dsh web [--patch <overlay>] --port <port> --host <host>
# 默认（不带 --service）注册为交互任务 (/it)，经 wscript 隐藏启动（不弹 cmd
# 窗口）在已登录用户会话里运行、原生文件夹弹窗可用；VBScript 不可用时（自
# Windows 11 24H2 起为按需功能）自动回退为 PowerShell 隐藏启动。--service
# 则注册为 SYSTEM 任务（未登录也开机自启，目录选择固定为网页内嵌浏览）。
#
# 任务名固定为 dsh-web。
#
# 用法:
#   powershell -ExecutionPolicy Bypass -File server-service.ps1 install
#   powershell -ExecutionPolicy Bypass -File server-service.ps1 uninstall
#   powershell -ExecutionPolicy Bypass -File server-service.ps1 status
#   powershell -ExecutionPolicy Bypass -File server-service.ps1 start
#   powershell -ExecutionPolicy Bypass -File server-service.ps1 stop
#   powershell -ExecutionPolicy Bypass -File server-service.ps1 --port 8080 install
#   powershell -ExecutionPolicy Bypass -File server-service.ps1 --host 127.0.0.1 install
#   powershell -ExecutionPolicy Bypass -File server-service.ps1 -Debug install
#   powershell -ExecutionPolicy Bypass -File server-service.ps1 service install
#
# 注意: install/uninstall 需要管理员权限 (schtasks /create / /delete)。
#
# 多语言: 与 setup/start 共用 locales/, 键前缀 srvc_。

# ---------- 控制台 UTF-8 ----------
try {
    $OutputEncoding = [System.Text.Encoding]::UTF8
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
} catch { }

# ---------- 默认配置 ----------
$Script:ScriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$Script:RootDir     = Split-Path -Parent $Script:ScriptDir
$Script:DefaultPort = 3080
$Script:Port        = $Script:DefaultPort
if ($env:DSH_PORT) {
    try { $Script:Port = [int]$env:DSH_PORT }
    catch { Write-Host "[WARN] DSH_PORT is not a number, using default $($Script:DefaultPort): $env:DSH_PORT" -ForegroundColor Yellow }
}
$Script:BindHost    = "127.0.0.1"
$Script:Debug       = $false
$Script:ServiceMode = $false
$Script:SvcName     = "dsh-web"

# ---------- 语言检测 (与 setup.ps1 一致) ----------
$Script:Lang = "zh"
if ($env:SETUP_LANG) {
    $lc = $env:SETUP_LANG.ToLower()
} else {
    $lc = [System.Globalization.CultureInfo]::InstalledUICulture.Name.ToLower()
}
if ($lc -match "^zh[-_]?(tw|hk|mo)") { $Script:Lang = "zh-TW" }
elseif ($lc -match "^zh") { $Script:Lang = "zh" }
elseif ($lc -match "^ja") { $Script:Lang = "ja" }
elseif ($lc -match "^ko") { $Script:Lang = "ko" }
elseif ($lc -match "^fr") { $Script:Lang = "fr" }
elseif ($lc -match "^de") { $Script:Lang = "de" }
elseif ($lc -match "^es") { $Script:Lang = "es" }
elseif ($lc -match "^en") { $Script:Lang = "en" }

# ---------- 颜色输出 ----------
$C_Info  = "Cyan"
$C_Ok    = "Green"
$C_Warn  = "Yellow"
$C_Err   = "Red"

function Write-Info  { Write-Host "[INFO]  $args" -ForegroundColor $C_Info }
function Write-Ok    { Write-Host "[OK]    $args" -ForegroundColor $C_Ok }
function Write-Warn  { Write-Host "[WARN]  $args" -ForegroundColor $C_Warn }
function Write-Fail  { Write-Host "[ERROR] $args" -ForegroundColor $C_Err }

# ---------- 语言文件加载 + 消息查找 ----------
$Script:Msg = @{}
function Load-Lang {
    $file = Join-Path $Script:RootDir "locales\$Script:Lang.lang"
    if (-not (Test-Path $file)) { $Script:Lang = "zh"; $file = Join-Path $Script:RootDir "locales\zh.lang" }
    if (Test-Path $file) {
        Get-Content -Path $file -Encoding UTF8 | ForEach-Object {
            if ($_ -and -not ($_ -match "^\s*#")) {
                $idx = $_.IndexOf("=")
                if ($idx -gt 0) {
                    $k = $_.Substring(0, $idx).Trim()
                    $v = $_.Substring($idx + 1)
                    $Script:Msg[$k] = $v
                }
            }
        }
    }
}
function msg {
    param([string]$key)
    if (-not $Script:Msg.ContainsKey($key)) { return "[missing:$key]" }
    $tpl = $Script:Msg[$key]
    for ($i = 1; $i -le $args.Count; $i++) {
        $tpl = $tpl.Replace("{$i}", [string]$args[$i - 1])
    }
    return $tpl
}
Load-Lang

# ---------- 帮助 ----------
function Show-Usage {
    Write-Host (msg srvc_usage "powershell -ExecutionPolicy Bypass -File server-service.ps1")
    Write-Host (msg srvc_usage_action)
    Write-Host (msg srvc_usage_uninstall)
    Write-Host (msg srvc_usage_status)
    Write-Host (msg srvc_usage_start)
    Write-Host (msg srvc_usage_stop)
    Write-Host "  $((msg srvc_usage_port $Script:DefaultPort))"
    Write-Host "  $((msg srvc_usage_host))"
    Write-Host (msg srvc_usage_debug)
    Write-Host (msg srvc_usage_service)
    Write-Host (msg srvc_usage_help)
    Write-Host (msg srvc_usage_nopause)
}

# ---------- 解析参数 (支持 -, --, / 三种前缀) ----------
$Action = $null
for ($i = 0; $i -lt $args.Count; $i++) {
    $a = $args[$i]
    $low = $a.ToLower().TrimStart("-", "/")
    switch ($low) {
        "install"  { $Action = "install" }
        "uninstall"{ $Action = "uninstall" }
        "status"   { $Action = "status" }
        "start"    { $Action = "start" }
        "stop"     { $Action = "stop" }
        "port"     { if ($i + 1 -lt $args.Count) { try { $Script:Port = [int]$args[$i + 1] } catch { }; $i++ } }
        "host"     { if ($i + 1 -lt $args.Count) { $Script:BindHost = $args[$i + 1]; $i++ } }
        "debug"    { $Script:Debug = $true }
        "service"  { $Script:ServiceMode = $true }
        "help"     { Show-Usage; exit 0 }
        "nopause"  { }
        default    { Write-Host "[WARN] $(msg unknown_arg $a)" -ForegroundColor Yellow }
    }
}
if (-not $Action) {
    Write-Host "[ERROR] $(msg srvc_unknown_action '')" -ForegroundColor Red
    Show-Usage
    exit 1
}

# ---------- 管理员检查 ----------
function Test-Admin {
    $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object System.Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

# ---------- 解析 node 与 dsh cli 绝对路径 ----------
$Script:NodePath = $null
$Script:DshCli   = $null
function Resolve-Runtime {
    if ($Script:Debug) {
        $cand = Join-Path $Script:RootDir "nodejs\node.exe"
        if (Test-Path $cand) { $Script:NodePath = $cand }
        $dshPkg = Join-Path $Script:RootDir "nodejs\node_modules\@deepseek-ai\dsh"
        if (Test-Path (Join-Path $dshPkg "package.json")) {
            try {
                $pj = Get-Content (Join-Path $dshPkg "package.json") -Raw | ConvertFrom-Json
                $b = $pj.bin
                $rel = if ($b -is [string]) { $b } else { $b.dsh }
                $cli = Join-Path $dshPkg ($rel -replace "\\", "/")
                if (Test-Path $cli) { $Script:DshCli = $cli }
            } catch { }
        }
    } else {
        $nodeCmd = Get-Command node -ErrorAction SilentlyContinue
        if ($nodeCmd) { $Script:NodePath = $nodeCmd.Source }
        if (Get-Command npm -ErrorAction SilentlyContinue) {
            try {
                $root = npm root -g 2>$null
                $pj = Join-Path $root "@deepseek-ai\dsh\package.json"
                if (Test-Path $pj) {
                    $data = Get-Content $pj -Raw | ConvertFrom-Json
                    $b = $data.bin
                    $rel = if ($b -is [string]) { $b } else { $b.dsh }
                    $cli = Join-Path (Split-Path -Parent $pj) ($rel -replace "\\", "/")
                    if (Test-Path $cli) { $Script:DshCli = $cli }
                }
            } catch { }
        }
    }

    if (-not $Script:NodePath -or -not (Test-Path $Script:NodePath)) {
        Write-Fail (msg srvc_node_fail)
        exit 1
    }
    if (-not $Script:DshCli -or -not (Test-Path $Script:DshCli)) {
        Write-Fail (msg srvc_dsh_fail)
        exit 1
    }
}

# ---------- 计划任务 查询/存在判断 (schtasks) ----------
function Get-SvcExists {
    schtasks.exe /query /tn $Script:SvcName *> $null
    return ($LASTEXITCODE -eq 0)
}
function Get-SvcRunning {
    # 任务状态用 PowerShell 查询 (State 为英文枚举, 不受系统语言影响)
    try {
        $t = Get-ScheduledTask -TaskName $Script:SvcName -ErrorAction Stop
        return ($t.State -eq "Running")
    } catch { return $false }
}

# schtasks /end 只结束任务主进程 (交互模式为 wscript.exe)，隐藏的 cmd -> node
# 链会成孤儿继续运行，所以显式杀掉残留的 dsh web node (其包装 cmd 随之退出)。
function Stop-DshWebProcess {
    Get-CimInstance Win32_Process -Filter "Name='node.exe'" | Where-Object {
        $_.CommandLine -like '*@deepseek-ai*' -and $_.CommandLine -like '*web --port*'
    } | ForEach-Object {
        taskkill.exe /F /T /PID $_.ProcessId 2>$null | Out-Null
    }
}

# ---------- 子命令 ----------
# Generate the runtime launcher trio (run-dsh-web.cmd/.vbs/.ps1) per the current
# mode ($Script:ServiceMode / $Script:Debug). Sets $Script:Runner* so the caller
# can build the task /tr. No absolute paths are baked in where the wrapper can
# self-locate at runtime: interactive mode runs as the logged-in user, so
# DSH_HOME/USERPROFILE already resolve to that user's profile (no override
# needed); the --patch overlay self-locates via %~dp0 (the wrapper's own
# directory). Service (SYSTEM) mode must override USERPROFILE to the installing
# user so dsh uses the real user's .dsh, and also self-locates the patch overlay.
function Generate-Launchers {
    $Script:Runner    = Join-Path $Script:ScriptDir "run-dsh-web.cmd"
    $Script:RunnerVbs = Join-Path $Script:ScriptDir "run-dsh-web.vbs"
    $Script:RunnerPs1 = Join-Path $Script:ScriptDir "run-dsh-web.ps1"
    if ($Script:ServiceMode) {
        $webCmd = "set `"DSH_HOME=$env:USERPROFILE\.dsh`"`nset `"USERPROFILE=$env:USERPROFILE`""
        if ($Script:Debug) {
            $webCmd += "`n`"$($Script:NodePath)`" `"$($Script:DshCli)`" web --patch `"%~dp0service-directory-picker-browse.yml`" --port $($Script:Port) --host $($Script:BindHost)"
        } else {
            $webCmd += "`ndsh web --patch `"%~dp0service-directory-picker-browse.yml`" --port $($Script:Port) --host $($Script:BindHost)"
        }
    } else {
        if ($Script:Debug) {
            $webCmd = "`"$($Script:NodePath)`" `"$($Script:DshCli)`" web --port $($Script:Port) --host $($Script:BindHost)"
        } else {
            $webCmd = "dsh web --port $($Script:Port) --host $($Script:BindHost)"
        }
    }
    $lines = @(
        "@echo off",
        $webCmd
    )
    Set-Content -LiteralPath $Script:Runner -Value $lines -Encoding ASCII
    $vbsLines = @(
        'Set fso = CreateObject("Scripting.FileSystemObject")',
        'Set sh = CreateObject("WScript.Shell")',
        'dir = fso.GetParentFolderName(WScript.ScriptFullName)',
        'sh.Run "cmd /c """ & dir & "\run-dsh-web.cmd""", 0, True'
    )
    Set-Content -LiteralPath $Script:RunnerVbs -Value $vbsLines -Encoding ASCII
    $ps1Lines = @(
        '$runner = Join-Path $PSScriptRoot "run-dsh-web.cmd"',
        'Start-Process -FilePath $runner -WindowStyle Hidden -Wait'
    )
    Set-Content -LiteralPath $Script:RunnerPs1 -Value $ps1Lines -Encoding ASCII
}

function Install-Service {
    Resolve-Runtime
    if (Get-SvcExists) {
        Write-Info (msg srvc_exists $Script:SvcName)
    } else {
        Write-Info (msg srvc_install $Script:Port)
    }
    # Stop any running instance so the forced re-create below takes effect cleanly.
    schtasks.exe /end /tn $Script:SvcName | Out-Null
    # Re-create with /f every time so a changed command is refreshed on re-install.
    # Two run modes:
    #   --service: task runs as SYSTEM in session 0, where the native OS folder
    #     dialog (IFileOpenDialog) cannot be shown, so the browse directory
    #     picker is pinned via --patch. USERPROFILE is baked into the wrapper.
    #   default (interactive): task runs with /it in the logged-on user's session
    #     and the native folder dialog just works (no --patch needed).
    # schtasks caps the /tr value at 261 chars, so register a short run wrapper
    # (run-dsh-web.cmd) that carries the real command. Non-debug mode calls `dsh
    # web` from PATH; debug mode pins the script-dir nodejs. --patch is a dsh
    # launcher flag and must come right after `web`, before the inner app flags.
Generate-Launchers
    if ($Script:ServiceMode) {
        $taskCmd = "cmd /c \`"\`"$($Script:Runner)\`"\`""
        schtasks.exe /create /tn $Script:SvcName /tr $taskCmd /sc onstart /ru SYSTEM /rl highest /f
    } else {
        # Interactive mode: launch via a hidden wscript wrapper so no cmd window
        # pops up in the user's session. VBScript is an on-demand feature since
        # Windows 11 24H2, so probe it and fall back to a hidden PowerShell
        # launcher when the feature is not installed.
        $probeVbs = Join-Path $env:TEMP "dsh_vbs_probe.vbs"
        Set-Content -LiteralPath $probeVbs -Value 'WScript.Echo "OK"' -Encoding ASCII
        $vbOk = $false
        try {
            $out = cscript.exe //nologo $probeVbs 2>$null
            if (($out -join "`n").Trim() -eq "OK") { $vbOk = $true }
        } catch { $vbOk = $false }
        Remove-Item -LiteralPath $probeVbs -Force -ErrorAction SilentlyContinue
        if ($vbOk) {
            $taskCmd = "wscript.exe \`"$($Script:RunnerVbs)\`""
        } else {
            $taskCmd = "powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File \`"$($Script:RunnerPs1)\`""
        }
        schtasks.exe /create /tn $Script:SvcName /tr $taskCmd /sc onstart /ru $env:USERNAME /it /rl highest /f
    }
    if ($LASTEXITCODE -ne 0) { Write-Fail (msg srvc_install_fail $Script:SvcName); exit 1 }
    schtasks.exe /run /tn $Script:SvcName | Out-Null
    Write-Ok (msg srvc_installed $Script:SvcName)
}

function Uninstall-Service {
    if (-not (Get-SvcExists)) {
        Write-Info (msg srvc_not_installed)
        exit 0
    }
    Write-Info (msg srvc_uninstall)
    if (Get-SvcRunning) { schtasks.exe /end /tn $Script:SvcName | Out-Null }
    schtasks.exe /delete /tn $Script:SvcName /f
    if ($LASTEXITCODE -ne 0) { Write-Fail (msg srvc_uninstall_fail); exit 1 }
    Stop-DshWebProcess
    Write-Ok (msg srvc_uninstalled)
}

function Show-Status {
    if (-not (Get-SvcExists)) { Write-Info (msg srvc_not_installed); return }
    if (Get-SvcRunning) { Write-Ok (msg srvc_running $Script:SvcName) } else { Write-Warn (msg srvc_stopped) }
}

function Start-ServiceX {
    if (-not (Get-SvcExists)) { Write-Fail (msg srvc_not_installed); exit 1 }
    # Derive the installed mode from the task itself, then make sure the runtime
    # launcher trio exists (normally created at install; regenerate if lost so the
    # task does not fail on a missing file).
    $t = Get-ScheduledTask -TaskName $Script:SvcName
    $Script:ServiceMode = ($t.Principal.UserId -match "SYSTEM")
    $Script:Debug = $false
    $launchers = @(
        (Join-Path $Script:ScriptDir "run-dsh-web.cmd"),
        (Join-Path $Script:ScriptDir "run-dsh-web.vbs"),
        (Join-Path $Script:ScriptDir "run-dsh-web.ps1")
    )
    if (($launchers | Where-Object { -not (Test-Path -LiteralPath $_) }).Count -gt 0) {
        Generate-Launchers
    }
    Write-Info (msg srvc_starting)
    schtasks.exe /run /tn $Script:SvcName | Out-Null
    for ($i = 0; $i -lt 10; $i++) {
        if (Get-SvcRunning) { break }
        Start-Sleep -Milliseconds 500
    }
    if (-not (Get-SvcRunning)) { Write-Fail (msg srvc_stopped) ; exit 1 }
    Write-Ok (msg srvc_started $Script:SvcName)
}

function Stop-ServiceX {
    if (-not (Get-SvcExists)) { Write-Fail (msg srvc_not_installed); exit 1 }
    if (Get-SvcRunning) {
        Write-Info (msg srvc_stopping)
        schtasks.exe /end /tn $Script:SvcName | Out-Null
        for ($i = 0; $i -lt 10; $i++) {
            if (-not (Get-SvcRunning)) { break }
            Start-Sleep -Milliseconds 500
        }
    }
    Stop-DshWebProcess
    Write-Ok (msg srvc_stopped_ok)
}

# ---------- 主流程 ----------
Write-Info (msg srvc_title)
if ($Action -in @("install", "uninstall", "start", "stop")) {
    if (-not (Test-Admin)) { Write-Warn (msg srvc_no_admin $Action) }
}
switch ($Action) {
    "install"   { Install-Service }
    "uninstall" { Uninstall-Service }
    "status"    { Show-Status }
    "start"     { Start-ServiceX }
    "stop"      { Stop-ServiceX }
}
