# start.ps1
# deepseek harness 启动器: 先运行 setup 确保工具链就绪, 检测 dsh 服务是否在运行,
# 解析服务端口, 用 webview/浏览器 app 模式打开 http://localhost:<port>。
# Windows 原生 PowerShell 脚本。
#
# 用法:
#   powershell -ExecutionPolicy Bypass -File start.ps1
#   powershell -ExecutionPolicy Bypass -File start.ps1 -Port 3080
#   powershell -ExecutionPolicy Bypass -File start.ps1 -Debug
#   powershell -ExecutionPolicy Bypass -File start.ps1 -Help
#
# 多语言: 与 setup 共用 locales/, 键前缀 sh_。

# ---------- 控制台 UTF-8 (确保中文在 cmd/PowerShell 窗口正常显示) ----------
try {
    $OutputEncoding = [System.Text.Encoding]::UTF8
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
} catch { }

# ---------- 默认配置 ----------
$Script:ScriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$Script:DefaultPort = 3080
$Script:Port        = $Script:DefaultPort
if ($env:DSH_PORT) { try { $Script:Port = [int]$env:DSH_PORT } catch { } }
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
    $file = Join-Path $Script:ScriptDir "locales\$Script:Lang.lang"
    if (-not (Test-Path $file)) { $Script:Lang = "zh"; $file = Join-Path $Script:ScriptDir "locales\zh.lang" }
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

# ---------- 解析参数 (支持 -, --, / 三种前缀) ----------
$ArgPort  = $null
$ArgDebug = $false
$ArgHelp  = $false
for ($i = 0; $i -lt $args.Count; $i++) {
    $a = $args[$i]
    switch ($a) {
        { $_ -in "-port","--port","/port" } {
            if ($i + 1 -lt $args.Count) { try { $ArgPort = [int]$args[$i + 1] } catch { }; $i++ }
        }
        { $_ -in "-debug","--debug","/debug" } { $ArgDebug = $true }
        { $_ -in "-help","--help","/help","-h","-?" } { $ArgHelp = $true }
        default { Write-Host "[WARN] $(msg sh_unknown $a)" -ForegroundColor Yellow }
    }
}

# ---------- 帮助 ----------
function Show-Usage {
    Write-Host (msg sh_usage "powershell -ExecutionPolicy Bypass -File start.ps1")
    Write-Host "  --port <port>    dsh service port (default: $($Script:DefaultPort))"
    Write-Host (msg sh_usage_debug)
    Write-Host (msg sh_usage_help)
    exit 0
}

if ($ArgHelp) { Show-Usage }

# ---------- 1) 检测 dsh 是否已就绪; 未就绪才跑 setup ----------
# 普通模式检查 PATH; 调试模式只认脚本目录 node 的全局 dsh。
function Test-DshReady {
    if ($ArgDebug) {
        return (Test-Path (Join-Path $Script:ScriptDir "nodejs\dsh.cmd"))
    }
    return [bool](Get-Command dsh -ErrorAction SilentlyContinue)
}

function Ensure-Toolchain {
    if (Test-DshReady) {
        Write-Ok (msg sh_dsh_ok)
        return
    }
    Write-Info (msg sh_setup_run)
    if ($ArgDebug) {
        & (Join-Path $Script:ScriptDir "setup.ps1") -Debug
    } else {
        & (Join-Path $Script:ScriptDir "setup.ps1")
    }
    if ($LASTEXITCODE -ne 0) { Write-Fail (msg sh_setup_fail); exit 1 }
}

# ---------- 2) 解析 dsh 服务端口 ----------
# 优先级: --port 参数 > 计划任务 dsh-web 配置里的 --port > DSH_PORT > 默认 3080
function Get-DshPort {
    if ($ArgPort) { return $ArgPort }
    try {
        $t = Get-ScheduledTask -TaskName $Script:SvcName -ErrorAction SilentlyContinue
        if ($t -and $t.Actions.Arguments) {
            $m = [regex]::Match($t.Actions.Arguments, "--port\s+(\d+)")
            if ($m.Success) { return [int]$m.Groups[1].Value }
        }
    } catch { }
    return $Script:Port
}

# ---------- 3) 检测 dsh 服务是否在运行 ----------
function Test-DshRunning {
    # 计划任务 dsh-web 状态 (State 为英文枚举, 不受系统语言影响)
    try {
        $t = Get-ScheduledTask -TaskName $Script:SvcName -ErrorAction SilentlyContinue
        if ($t -and $t.State -eq "Running") { return $true }
    } catch { }
    # 端口探测兜底
    try {
        $r = Invoke-WebRequest -Uri "http://127.0.0.1:$($Script:Port)/" -UseBasicParsing -TimeoutSec 2 -ErrorAction Stop
        if ($r.StatusCode -ge 100 -and $r.StatusCode -le 599) { return $true }
    } catch { }
    return $false
}

# ---------- 端口就绪探测 (HTTP) ----------
function Test-PortUp {
    try {
        $r = Invoke-WebRequest -Uri "http://127.0.0.1:$($Script:Port)/" -UseBasicParsing -TimeoutSec 2 -ErrorAction Stop
        if ($r.StatusCode -ge 100 -and $r.StatusCode -le 599) { return $true }
    } catch { }
    return $false
}

# ---------- 启动 dsh 服务 (已注册的计划任务; 未注册则等待超时提示) ----------
function Start-DshService {
    Write-Info (msg sh_service_start)
    $svcScript = Join-Path $Script:ScriptDir "server\server-service.ps1"
    if (Test-Path $svcScript) {
        & $svcScript start 2>$null | Out-Null
    }
    Write-Info (msg sh_service_wait)
    for ($i = 0; $i -lt 30; $i++) {
        if (Test-PortUp) { return $true }
        Start-Sleep -Seconds 1
    }
    return $false
}

# ---------- 用 webview/浏览器 app 模式打开 URL ----------
function Open-Browser {
    param([string]$url)
    Write-Info (msg sh_browser $url)
    $candidates = @(
        "$env:ProgramFiles(x86)\Microsoft\Edge\Application\msedge.exe",
        "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe",
        "$env:LOCALAPPDATA\Microsoft\Edge\Application\msedge.exe",
        "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
        "$env:ProgramFiles(x86)\Google\Chrome\Application\chrome.exe",
        "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe"
    )
    foreach ($c in $candidates) {
        if (Test-Path $c) {
            try { Start-Process $c -ArgumentList "--app=$url" -ErrorAction Stop; return } catch { }
        }
    }
    try { Start-Process $url -ErrorAction Stop; return } catch { }
    Write-Warn (msg sh_browser_fail $url)
}

# ---------- 主流程 ----------
Write-Info (msg sh_title)

Ensure-Toolchain

$Script:Port = Get-DshPort
Write-Info (msg sh_port_using $Script:Port)

$url = "http://localhost:$($Script:Port)"
if (Test-DshRunning) {
    Write-Ok (msg sh_service_running $url)
    Open-Browser -url $url
    exit 0
}

if (Start-DshService) {
    Write-Ok (msg sh_service_ready $url)
    Open-Browser -url $url
} else {
    Write-Warn (msg sh_service_fail $url)
}
