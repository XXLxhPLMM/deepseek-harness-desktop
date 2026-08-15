# server-service.ps1
# 把 deepseek harness 的 `dsh web` 安装/管理为 Windows 系统服务（开机自启）。
# 采用 `sc create` + node.exe 直连 的方式: 服务二进制指向 node.exe,
# 参数为 dsh 的 CLI 入口 js。
#
# 服务名固定为 dsh-web。命令为 `<node.exe> <dsh cli.js> web --port <port> --host <host>`。
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
#
# 注意: install/uninstall 需要管理员权限 (sc create / sc delete)。
#
# 多语言: 与 setup/start-harness 共用 locales/, 键前缀 srvc_。

# ---------- 控制台 UTF-8 ----------
try {
    $OutputEncoding = [System.Text.Encoding]::UTF8
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
} catch { }

# ---------- 默认配置 ----------
$Script:ScriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$Script:RootDir     = Split-Path -Parent $Script:ScriptDir
$Script:DefaultPort = 3080
$Script:Port        = if ($env:DSH_PORT) { [int]$env:DSH_PORT } else { $Script:DefaultPort }
$Script:BindHost    = "127.0.0.1"
$Script:Debug       = $false
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
    Write-Host (msg srvc_usage_help)
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
        $dshPkg = Join-Path $Script:RootDir "node_modules\@deepseek-ai\dsh"
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

# ---------- sc 查询/存在判断 ----------
function Get-SvcExists {
    sc.exe query $Script:SvcName *> $null
    return ($LASTEXITCODE -eq 0)
}
function Get-SvcRunning {
    $out = sc.exe query $Script:SvcName 2>$null
    return [bool]($out | Select-String -Quiet "RUNNING")
}

# ---------- 子命令 ----------
function Install-Service {
    Resolve-Runtime
    if (Get-SvcExists) {
        Write-Info (msg srvc_exists $Script:SvcName)
    } else {
        Write-Info (msg srvc_install $Script:Port)
        $binPath = "`"$($Script:NodePath)`" `"$($Script:DshCli)`" web --port $($Script:Port) --host $($Script:BindHost)"
        sc.exe create $Script:SvcName binPath= $binPath start= auto DisplayName= "DeepSeek Harness Web (dsh web)"
        if ($LASTEXITCODE -ne 0) { Write-Fail (msg srvc_install_fail $Script:SvcName); exit 1 }
        sc.exe failure $Script:SvcName reset= 86400 actions= restart/5000/restart/5000/restart/5000
        sc.exe start $Script:SvcName | Out-Null
    }
    Write-Ok (msg srvc_installed $Script:SvcName)
}

function Uninstall-Service {
    if (-not (Get-SvcExists)) {
        Write-Info (msg srvc_not_installed)
        exit 0
    }
    Write-Info (msg srvc_uninstall)
    if (Get-SvcRunning) { sc.exe stop $Script:SvcName | Out-Null }
    sc.exe delete $Script:SvcName
    if ($LASTEXITCODE -ne 0) { Write-Fail (msg srvc_uninstall_fail); exit 1 }
    Write-Ok (msg srvc_uninstalled)
}

function Show-Status {
    if (-not (Get-SvcExists)) { Write-Info (msg srvc_not_installed); return }
    if (Get-SvcRunning) { Write-Ok (msg srvc_running $Script:SvcName) } else { Write-Warn (msg srvc_stopped) }
}

function Start-ServiceX {
    if (-not (Get-SvcExists)) { Write-Fail (msg srvc_not_installed); exit 1 }
    Write-Info (msg srvc_starting)
    sc.exe start $Script:SvcName | Out-Null
    if ($LASTEXITCODE -ne 0 -and -not (Get-SvcRunning)) { Write-Fail (msg srvc_stopped) ; exit 1 }
    Write-Ok (msg srvc_started $Script:SvcName)
}

function Stop-ServiceX {
    if (-not (Get-SvcExists)) { Write-Fail (msg srvc_not_installed); exit 1 }
    if (Get-SvcRunning) {
        Write-Info (msg srvc_stopping)
        sc.exe stop $Script:SvcName | Out-Null
    }
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
