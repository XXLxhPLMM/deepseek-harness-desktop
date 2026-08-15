# start-harness.ps1
# 检测/安装 deepseek harness (dsh): 确保 Node.js 就绪、全局安装 @deepseek-ai/dsh、
# 启动 dsh 服务，并用浏览器 app 模式打开 http://localhost:<port>。
# Windows 原生 PowerShell 脚本。
#
# 用法:
#   powershell -ExecutionPolicy Bypass -File start-harness.ps1
#   powershell -ExecutionPolicy Bypass -File start-harness.ps1 -Port 3080
#   powershell -ExecutionPolicy Bypass -File start-harness.ps1 -Debug
#   powershell -ExecutionPolicy Bypass -File start-harness.ps1 -Help
#
# 多语言: 与 setup 共用 locales/, 键前缀 sh_。

# ---------- 控制台 UTF-8 (确保中文在 cmd/PowerShell 窗口正常显示) ----------
try {
    $OutputEncoding = [System.Text.Encoding]::UTF8
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
} catch { }

# ---------- 默认配置 ----------
$Script:ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$Script:DefaultPort = 3080
$Script:Port = $Script:DefaultPort
if ($env:DSH_PORT) { $Script:Port = [int]$env:DSH_PORT }
$Script:DshPkg = "@deepseek-ai/dsh"

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
# 其余/未知 -> 保持默认中文

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
    if (-not (Test-Path $file)) {
        Write-Warn "语言文件缺失: $file (使用中文)"
        $Script:Lang = "zh"
        $file = Join-Path $Script:ScriptDir "locales\zh.lang"
    }
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
            if ($i + 1 -lt $args.Count) { $ArgPort = [int]$args[$i + 1]; $i++ }
        }
        { $_ -in "-debug","--debug","/debug" } { $ArgDebug = $true }
        { $_ -in "-help","--help","/help","-h","-?" } { $ArgHelp = $true }
        default {
            Write-Host "[WARN] $(msg sh_unknown $a)" -ForegroundColor Yellow
        }
    }
}

if ($ArgPort) { $Script:Port = $ArgPort }

# ---------- 帮助 ----------
function Show-Usage {
    Write-Host (msg sh_usage "powershell -ExecutionPolicy Bypass -File start-harness.ps1")
    Write-Host "  --port <port>    dsh service port (default: $($Script:DefaultPort))"
    Write-Host (msg sh_usage_debug)
    Write-Host (msg sh_usage_help)
    exit 0
}

if ($ArgHelp) { Show-Usage }

# ---------- 检测 Node.js (>= 22) ----------
function Test-Node {
    $nodeCmd = Get-Command node -ErrorAction SilentlyContinue
    if ($nodeCmd) {
        try {
            $version = (node --version 2>$null).TrimStart("v")
            if ($version) {
                $major = ($version -split "\.")[0]
                if ([int]$major -ge 22) {
                    Write-Ok (msg node_ok $version "22")
                    return $true
                }
            }
        } catch { }
    }
    return $false
}

# ---------- 确保 Node.js 就绪 ----------
function Ensure-Node {
    if ($ArgDebug) {
        $localNode = Join-Path $Script:ScriptDir "nodejs"
        if (Test-Path (Join-Path $localNode "node.exe")) {
            $env:Path = "$localNode;$env:Path"
            Write-Ok (msg sh_node_local $localNode)
            if (Test-Node) { return }
        }
        Write-Info (msg sh_node_missing)
        & (Join-Path $Script:ScriptDir "setup.ps1") -Debug
        if ($LASTEXITCODE -ne 0) { Write-Fail (msg sh_node_fail); exit 1 }
        $env:Path = "$localNode;$env:Path"
        if (Test-Node) { return }
        Write-Fail (msg sh_node_fail); exit 1
    }
    if (Test-Node) { return }
    Write-Info (msg sh_node_missing)
    & (Join-Path $Script:ScriptDir "setup.ps1")
    if ($LASTEXITCODE -ne 0) { Write-Fail (msg sh_node_fail); exit 1 }
    if (-not (Test-Node)) { Write-Fail (msg sh_node_fail); exit 1 }
}

# ---------- 确保 dsh 已全局安装 ----------
function Ensure-Dsh {
    if (Get-Command dsh -ErrorAction SilentlyContinue) {
        Write-Ok (msg sh_dsh_ok)
        return
    }
    Write-Info (msg sh_dsh_missing)
    Write-Info (msg sh_dsh_install)
    & npm install -g $Script:DshPkg
    if ($LASTEXITCODE -ne 0) { Write-Fail (msg sh_dsh_fail $Script:DshPkg); exit 1 }
    # npm 全局 bin 可能不在当前 PATH, 尝试补全
    if (-not (Get-Command dsh -ErrorAction SilentlyContinue)) {
        try {
            $prefix = npm prefix -g 2>$null
            if ($prefix) {
                $env:Path = "$prefix;$env:Path"
            }
        } catch { }
    }
    if (-not (Get-Command dsh -ErrorAction SilentlyContinue)) {
        Write-Fail (msg sh_dsh_fail $Script:DshPkg); exit 1
    }
    Write-Ok (msg sh_dsh_done)
}

# ---------- 检查服务是否已运行 ----------
function Test-Service {
    try {
        $resp = Invoke-WebRequest -Uri "http://127.0.0.1:$($Script:Port)/" -UseBasicParsing -TimeoutSec 3 -ErrorAction Stop
        if ($resp.StatusCode -ge 100 -and $resp.StatusCode -le 599) { return $true }
    } catch { }
    return $false
}

# ---------- 后台启动 dsh web (绑定指定端口) ----------
function Start-DshService {
    Start-Process -FilePath "dsh" -ArgumentList @("web", "--port", "$($Script:Port)") -WindowStyle Hidden -ErrorAction SilentlyContinue
}

# ---------- 用浏览器 app 模式打开 URL ----------
function Open-Browser {
    param([string]$url)
    Write-Info (msg sh_browser $url)
    $launched = $false
    foreach ($br in @("msedge", "chrome", "msedge.exe", "chrome.exe")) {
        $cmd = Get-Command $br -ErrorAction SilentlyContinue
        if ($cmd) {
            try {
                Start-Process $cmd.Source -ArgumentList "--app=$url" -ErrorAction Stop
                $launched = $true
                break
            } catch { }
        }
    }
    if (-not $launched) {
        try {
            Start-Process $url -ErrorAction Stop
            $launched = $true
        } catch { }
    }
    if (-not $launched) {
        Write-Warn (msg sh_browser_fail $url)
    }
}

# ---------- 主流程 ----------
function Main {
    Write-Info (msg sh_title)

    Ensure-Node
    Ensure-Dsh

    $url = "http://localhost:$($Script:Port)"
    if (Test-Service) {
        Write-Ok (msg sh_service_running $url)
        Open-Browser -url $url
        return
    }

    Write-Info (msg sh_service_start)
    Start-DshService
    Write-Info (msg sh_service_wait)
    for ($i = 0; $i -lt 30; $i++) {
        if (Test-Service) { break }
        Start-Sleep -Seconds 1
    }
    if (Test-Service) {
        Write-Ok (msg sh_service_ready $url)
        Open-Browser -url $url
    } else {
        # 服务未启动成功: 只提示, 不打开浏览器
        Write-Warn (msg sh_service_fail $url)
    }
}

Main
