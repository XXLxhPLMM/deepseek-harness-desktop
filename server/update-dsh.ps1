# update-dsh.ps1 - update @deepseek-ai/dsh to the latest version and restart the dsh-web service
# Usage:
#   .\update-dsh.ps1               update dsh to the latest version
#   .\update-dsh.ps1 -DryRun       show current/latest version only, no update
#   .\update-dsh.ps1 -Debug        update dsh under the script-dir node
#   .\update-dsh.ps1 -Help         show help
# Requires Windows PowerShell 5.1+. File must stay UTF-8 with BOM.

try {
    $OutputEncoding = [System.Text.Encoding]::UTF8
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
} catch { }

# ---------- 默认配置 ----------
$Script:ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Script:RootDir   = Split-Path -Parent $Script:ScriptDir
$Script:SvcName   = "dsh-web"
$Script:DshPkg    = "@deepseek-ai/dsh"
$Script:DryRun    = $false
$Script:Debug     = $false

# ---------- 语言检测 (与 server-service.ps1 一致) ----------
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

# ---------- 语言文件加载 + 消息查找 (与 server-service.ps1 一致) ----------
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
    Write-Host (msg ud_usage "update-dsh.ps1")
    Write-Host (msg ud_usage_dryrun)
    Write-Host (msg ud_usage_debug)
    Write-Host (msg ud_usage_help)
}

# ---------- 解析参数 (支持 -, --, / 三种前缀) ----------
foreach ($a in $args) {
    switch ($a) {
        { $_ -in "-dryrun","--dry-run","/dry-run" } { $Script:DryRun = $true }
        { $_ -in "-debug","--debug","/debug" }       { $Script:Debug  = $true }
        { $_ -in "-help","--help","/help","-h","-?" } { Show-Usage; exit 0 }
        default { Write-Warn (msg unknown_arg $a) }
    }
}

# ---------- 主流程 ----------
Write-Info (msg ud_title)

# 定位 dsh: debug 模式只认脚本目录 node 的全局 dsh
$dshFound = $false
if ($Script:Debug) {
    $nodeDir = Join-Path $Script:RootDir "nodejs"
    if (Test-Path (Join-Path $nodeDir "dsh.cmd") -or (Test-Path (Join-Path $nodeDir "dsh"))) {
        $dshFound = $true
        $env:Path = "$nodeDir;$env:Path"
        $env:npm_config_prefix = $nodeDir
    }
} else {
    $dshFound = [bool](Get-Command dsh -ErrorAction SilentlyContinue)
}
if (-not $dshFound) { Write-Fail (msg ud_no_dsh); exit 1 }

# 当前版本
$curVer = [string]((& dsh --version 2>$null) | Select-Object -First 1)
$curVer = $curVer.Trim()
Write-Info (msg ud_current $(if ($curVer) { $curVer } else { "unknown" }))

if ($Script:DryRun) {
    $latest = [string]((& npm.cmd view $Script:DshPkg version 2>$null) | Select-Object -First 1)
    $latest = $latest.Trim()
    Write-Info (msg ud_latest $(if ($latest) { $latest } else { "unknown" }))
    if ($curVer -and $latest -and $curVer -eq $latest) { Write-Ok (msg ud_up_to_date) }
    exit 0
}

# 服务已安装则先停掉
$svcRunning = $false
if (Get-ScheduledTask -TaskName $Script:SvcName -ErrorAction SilentlyContinue) {
    Write-Info (msg ud_stopping)
    & (Join-Path $Script:ScriptDir "server-service.ps1") stop | Out-Null
    $svcRunning = $true
}

# 更新
Write-Info (msg ud_updating)
& npm.cmd install -g "$($Script:DshPkg)@latest" 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) { Write-Fail (msg ud_fail $Script:DshPkg); exit 1 }

$newVer = [string]((& dsh --version 2>$null) | Select-Object -First 1)
$newVer = $newVer.Trim()
Write-Ok (msg ud_done $(if ($newVer) { $newVer } else { "unknown" }))

# 服务原已安装则重启使其生效
if ($svcRunning) {
    Write-Info (msg ud_restarting)
    & (Join-Path $Script:ScriptDir "server-service.ps1") start | Out-Null
    Write-Ok (msg ud_restart_done)
}
