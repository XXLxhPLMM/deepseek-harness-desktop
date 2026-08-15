# setup-node.ps1
# 检测当前环境是否有 Node.js 22+，如果没有则自动安装，并配置环境变量。
# Windows 原生 PowerShell 脚本。
#
# 安装策略:
#   1) 若已安装 nvm (nvm-windows)，优先使用 nvm 安装 Node 22。
#   2) 否则从 nodejs.org 官方下载 zip 安装到 -Dir (默认脚本目录下的 nodejs)。
#
# 用法:
#   powershell -ExecutionPolicy Bypass -File setup-node.ps1
#   powershell -ExecutionPolicy Bypass -File setup-node.ps1 -Dir "D:\envs\node"
#   powershell -ExecutionPolicy Bypass -File setup-node.ps1 -NoEnv
#   powershell -ExecutionPolicy Bypass -File setup-node.ps1 -DryRun
#
# 参数:
#   -Dir <路径>   指定安装目录 (默认: 脚本目录下的 nodejs)
#   -NoEnv        不修改 PATH 环境变量
#   -DryRun       只检测, 不下载安装
#
# 多语言: 提示/日志根据系统语言自动加载 locales/{zh,en}.lang,
#         消息以 msg <键> [参数...] 查找, {1}/{2} 为占位符按序替换。

# ---------- 控制台 UTF-8 (确保中文在 cmd/PowerShell 窗口正常显示) ----------
try {
    $OutputEncoding = [System.Text.Encoding]::UTF8
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
} catch { }

# ---------- 默认配置 ----------
$Script:Version   = "22.23.2"      # Node.js 22 LTS 最新版 (nvm 用无 v 前缀)
$Script:VVersion  = "v22.23.2"     # 官方下载用 v 前缀
$Script:MinMajor  = 22
$Script:BaseUrl   = "https://nodejs.org/dist"
$Script:ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# ---------- 语言检测 (决定提示/日志语言: zh/zh-TW/en/ja/ko/fr/de/es, 检测不到默认中文) ----------
# 用 InstalledUICulture (系统安装的 UI 语言, 不受 chcp 影响; CurrentUICulture 在
# chcp 65001 下会错误回退为 en-US)。统一转小写再匹配; zh-TW/HK/MO -> 繁体(台湾)包。
# 环境变量 SETUP_LANG 优先, 用于测试/强制指定语言。
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
# 从 locales/$Lang.lang 读取 KEY=message 到 $Script:Msg 哈希表。
# msg <键> [参数...]: 返回该键消息, {1}/{2} 占位符按传入顺序替换。
$Script:Msg = @{}
function Load-Lang {
    $file = Join-Path $Script:ScriptDir "locales\$Script:Lang.lang"
    if (-not (Test-Path $file)) {
        Write-Warn "语言文件缺失: $file (使用中文)"   # 提示: 语言文件缺失，回退中文
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
$ArgDir   = $null
$ArgNoEnv = $false
$ArgDryRun= $false
$ArgDebug = $false
$ArgHelp  = $false
for ($i = 0; $i -lt $args.Count; $i++) {
    $a = $args[$i]
    switch ($a) {
        { $_ -in "-dir","--dir","/dir" } {
            if ($i + 1 -lt $args.Count) { $ArgDir = $args[$i + 1]; $i++ }
            else { Write-Host "[ERROR] $(msg dir_need_path $a)" -ForegroundColor Red; exit 1 }
        }
        { $_ -in "-noenv","--no-env","/no-env" } { $ArgNoEnv = $true }
        { $_ -in "-dryrun","--dry-run","/dry-run" } { $ArgDryRun = $true }
        { $_ -in "-debug","--debug","/debug" } { $ArgDebug = $true }
        { $_ -in "-help","--help","/help","-h","-?" } { $ArgHelp = $true }
        default {
            Write-Host "[WARN] $(msg unknown_arg $a)" -ForegroundColor Yellow
        }
    }
}

# 安装目录: -Dir 优先; 否则默认安装到脚本启动目录下的 nodejs
if ($ArgDir) {
    $Script:InstallDir = $ArgDir
} else {
    $Script:InstallDir = Join-Path $Script:ScriptDir "nodejs"
}

# ---------- 帮助 ----------
function Show-Usage {
    # 提示: 用法 / -Dir / -NoEnv / -DryRun / -Debug / -Help / 参数前缀说明
    Write-Host (msg usage_usage "powershell -ExecutionPolicy Bypass -File setup-node.ps1")
    Write-Host (msg usage_dir)
    Write-Host (msg usage_noenv)
    Write-Host (msg usage_dryrun)
    Write-Host (msg usage_debug)
    Write-Host (msg usage_help)
    Write-Host (msg usage_prefix)
    exit 0
}

if ($ArgHelp) { Show-Usage }

# ---------- 检测 Node ----------
function Test-Node {
    $nodeCmd = Get-Command node -ErrorAction SilentlyContinue
    if ($nodeCmd) {
        try {
            $version = (node --version 2>$null).TrimStart("v")
            if ($version) {
                $major = ($version -split "\.")[0]
                if ([int]$major -ge $Script:MinMajor) {
                    # 提示: 已检测到 Node.js <版本> (>= 22)，无需安装
                    Write-Ok (msg node_ok $version $Script:MinMajor)
                    return $true
                } else {
                    # 提示: 检测到 Node.js <版本>，但版本低于 22，需要安装新版本
                    Write-Warn (msg node_low $version $Script:MinMajor)
                    return $false
                }
            }
        } catch { }
    }
    # 提示: 未检测到 Node.js，开始安装...
    Write-Info (msg node_not_found)
    return $false
}

# ---------- 检测 nvm (nvm-windows) ----------
function Test-Nvm {
    $nvmCmd = Get-Command nvm -ErrorAction SilentlyContinue
    if ($nvmCmd) { return $true }
    if ($env:NVM_HOME) { return $true }
    if (Test-Path (Join-Path $env:NVM_HOME "nvm.exe")) { return $true }
    return $false
}

# ---------- 使用 nvm 安装 Node ----------
function Install-Node-With-Nvm {
    # 提示: 检测到 nvm，使用 nvm 安装 Node.js 22.23.2 ...
    Write-Info (msg nvm_using $Script:Version)

    # nvm use 需要管理员权限; 尝试当前会话先看是否已安装该版本
    $installed = (& nvm list 2>$null) -match [regex]::Escape($Script:Version)
    if ($installed) {
        # 提示: nvm 中已安装 22.23.2，直接切换...
        Write-Info (msg nvm_installed $Script:Version)
    } else {
        # 提示: nvm install 22.23.2 ...
        Write-Info (msg nvm_install_run $Script:Version)
        & nvm install $Script:Version
        if ($LASTEXITCODE -ne 0) {
            # 提示: nvm install 失败，请检查网络或 nvm 配置。
            Write-Fail (msg nvm_install_fail)
            return $false
        }
    }

    # 提示: nvm use 22.23.2 ...
    Write-Info (msg nvm_use_run $Script:Version)
    & nvm use $Script:Version
    if ($LASTEXITCODE -ne 0) {
        # 提示: nvm use 可能需要管理员权限。请以管理员身份打开终端，运行: nvm use 22.23.2
        Write-Warn (msg nvm_use_fail $Script:Version)
        return $false
    }
    return $true
}

# ---------- 从官方下载并解压 ----------
function Install-Node-Direct {
    $arch = switch ($env:PROCESSOR_ARCHITECTURE) {
        "AMD64" { "x64" }
        "ARM64" { "arm64" }
        "x86"   { "x86" }
        default { "x64" }
    }
    # 提示: 平台: win / <arch>
    Write-Info (msg platform "win" $arch)

    $distUrl = "$($Script:BaseUrl)/$($Script:VVersion)/node-$($Script:VVersion)-win-$arch.zip"
    $zipPath = Join-Path $Script:ScriptDir "node-$($Script:VVersion)-win-$arch.zip"
    if (Test-Path $zipPath) { Remove-Item -Force $zipPath -ErrorAction SilentlyContinue }

    # 提示: 下载 <url> ...
    Write-Info (msg downloading $distUrl)
    try {
        Invoke-WebRequest -Uri $distUrl -OutFile $zipPath -UseBasicParsing
    } catch {
        # 提示: 下载失败: <错误信息>
        Write-Fail (msg download_fail $_.Exception.Message)
        Remove-Item -Force $zipPath -ErrorAction SilentlyContinue
        return $false
    }

    # 提示: 创建安装目录: <dir>
    Write-Info (msg mkdir $Script:InstallDir)
    New-Item -ItemType Directory -Force -Path $Script:InstallDir | Out-Null

    # 提示: 解压中...
    Write-Info (msg extracting)
    $extractDir = Join-Path $Script:ScriptDir "node-extract-$PID"
    New-Item -ItemType Directory -Force -Path $extractDir | Out-Null
    try {
        Expand-Archive -Path $zipPath -DestinationPath $extractDir -Force
        $extractRoot = Get-ChildItem -Path $extractDir -Directory -Filter "node-$($Script:VVersion)-win-$arch"
        if ($extractRoot) {
            Copy-Item -Path (Join-Path $extractRoot.FullName "*") -Destination $Script:InstallDir -Recurse -Force
        } else {
            Copy-Item -Path (Join-Path $extractDir "*") -Destination $Script:InstallDir -Recurse -Force
        }
    } catch {
        # 提示: 解压失败: <错误信息>
        Write-Fail (msg extract_fail $_.Exception.Message)
        Remove-Item -Recurse -Force $extractDir -ErrorAction SilentlyContinue
        Remove-Item -Force $zipPath -ErrorAction SilentlyContinue
        return $false
    }

    Remove-Item -Recurse -Force $extractDir -ErrorAction SilentlyContinue
    Remove-Item -Force $zipPath -ErrorAction SilentlyContinue

    if (Test-Path (Join-Path $Script:InstallDir "node.exe")) {
        # 提示: Node.js 已安装到 <dir>
        Write-Ok (msg installed $Script:InstallDir)
        return $true
    } else {
        # 提示: 解压完成，但未找到 node.exe，请检查 <dir>
        Write-Warn (msg exe_not_found $Script:InstallDir)
        return $false
    }
}

# ---------- 配置环境变量 (Windows 用户 PATH) ----------
function Set-NodeEnv {
    # 提示: 写入环境变量配置...
    Write-Info (msg env_writing)

    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $installDir = $Script:InstallDir

    if ($userPath -and $userPath.Split(";") -contains $installDir) {
        # 提示: Windows 用户 PATH 已包含 <dir>，跳过
        Write-Info (msg winpath_already $installDir)
    } else {
        $newPath = if ([string]::IsNullOrEmpty($userPath)) { $installDir } else { "$installDir;$userPath" }
        [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
        # 提示: 已添加 <dir> 到 Windows 用户 PATH
        Write-Ok (msg winpath_updated $installDir)
    }

    $env:Path = "$installDir;$env:Path"
    # 提示: 当前会话 PATH 已更新
    Write-Ok (msg env_session_ok "$installDir;$env:Path")
}

# ---------- 调试模式: 从当前会话 PATH 移除 nvm/node 相关项 ----------
function Remove-NodeFromPath {
    # 提示: 调试模式: 检测当前 PATH 中的 nvm / node 相关路径...
    Write-Info (msg debug_scan)
    $items = $env:Path -split ";"
    $removed = @()
    $kept = @()
    foreach ($item in $items) {
        if ($item.Trim() -eq "") { continue }
        if ($item -match "nvm" -or $item -match "node") {
            $removed += $item
        } else {
            $kept += $item
        }
    }
    if ($removed.Count -gt 0) {
        # 提示: 已从当前会话 PATH 移除:
        Write-Warn (msg removed)
        foreach ($r in $removed) { Write-Warn "  - $r" }
        $env:Path = $kept -join ";"
    } else {
        # 提示: 当前会话 PATH 中未发现 nvm / node 相关项。
        Write-Info (msg nothing_removed)
    }
}

# ---------- 主流程 ----------
function Main {
    # 提示: === Node.js 环境检测与安装 ===
    Write-Info (msg main_title)

    if ($ArgDebug) {
        # 提示: === 调试模式启用: 安装目录 = <dir> ===
        Write-Info (msg debug_title $Script:InstallDir)
        Remove-NodeFromPath
    }

    if (Test-Node) { exit 0 }

    if ($ArgDryRun) {
        # 提示: --dry-run 模式，跳过安装
        Write-Info (msg dryrun_skip)
        exit 1
    }

    $ok = $false
    if ($ArgDebug) {
        # 调试模式不走 nvm, 强制官方下载以隔离验证
        # 提示: 调试模式: 跳过 nvm，直接官方下载...
        Write-Info (msg debug_skip_nvm)
        $ok = Install-Node-Direct
    } elseif (Test-Nvm) {
        $ok = Install-Node-With-Nvm
        if (-not $ok) {
            # 提示: nvm 安装失败，回退到官方下载方式...
            Write-Warn (msg nvm_fail_fallback)
            $ok = Install-Node-Direct
        }
    } else {
        # 提示: 未检测到 nvm，使用官方下载方式...
        Write-Info (msg no_nvm)
        $ok = Install-Node-Direct
    }

    if (-not $ok) {
        # 提示: Node.js 安装失败，请检查网络后重试。
        Write-Fail (msg install_failed)
        exit 1
    }

    if ($ArgNoEnv -or $ArgDebug) {
        if ($ArgDebug) {
            # 提示: 调试模式: 仅更新当前会话 PATH，不写用户持久化 PATH
            Write-Info (msg debug_session_only)
            $env:Path = "$Script:InstallDir;$env:Path"
        } else {
            # 提示: --no-env 已指定，跳过环境变量配置
            Write-Info (msg noenv_skip)
            # 提示: 请手动将 <dir> 加入 PATH
            Write-Warn (msg noenv_manual $Script:InstallDir)
        }
    } else {
        Set-NodeEnv
    }

    Write-Host ""
    # 提示: 完成! 请重新打开终端使配置生效。
    Write-Ok (msg done)
    # 提示: 当前 Node 版本: <版本>
    $ver = (node --version 2>$null)
    if ($ver) { Write-Info (msg node_version $ver) } else { Write-Info (msg node_version "unknown") }
}

Main
