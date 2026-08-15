# setup.ps1
# 检测/安装整条工具链: nvm → node → npm 淘宝镜像 + nrm → dsh。逐级检查, 拒绝重复安装。
# 只做一件事: 检测当前环境缺什么, 补装什么。
# Windows 原生 PowerShell 脚本。
#
# 安装策略:
#   1) nvm 只检测/使用 (不安装), 有则优先用 nvm 安装 Node 22。
#   2) 否则从 nodejs.org 官方下载 zip 安装到 -Dir (默认脚本目录下的 nodejs)。
#   3) node 就绪后: npm 源设为淘宝镜像, 全局安装 nrm。
#   4) dsh 缺失则 npm install -g @deepseek-ai/dsh (调试模式装到脚本目录)。
#
# 用法:
#   powershell -ExecutionPolicy Bypass -File setup.ps1
#   powershell -ExecutionPolicy Bypass -File setup.ps1 -Dir "D:\envs\node"
#   powershell -ExecutionPolicy Bypass -File setup.ps1 -NoEnv
#   powershell -ExecutionPolicy Bypass -File setup.ps1 -DryRun
#   powershell -ExecutionPolicy Bypass -File setup.ps1 -Debug
#
# 参数:
#   -Dir <路径>   指定 node 安装目录 (默认: 脚本目录下的 nodejs)
#   -NoEnv        不修改 PATH 环境变量
#   -DryRun       只检测, 不下载安装
#   -Debug        调试模式: 只清当前会话环境, 隔离安装到脚本目录, 不写全局
#
# 多语言: 提示/日志根据系统语言自动加载 locales/{zh,en,...}.lang,
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
$Script:DshPkg    = "@deepseek-ai/dsh"
$Script:NpmRegistry = "https://registry.npmmirror.com"   # 淘宝 npm 镜像
$Script:NrmPkg      = "nrm"

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
    Write-Host (msg usage_usage "powershell -ExecutionPolicy Bypass -File setup.ps1")
    Write-Host (msg usage_dir)
    Write-Host (msg usage_noenv)
    Write-Host (msg usage_dryrun)
    Write-Host (msg usage_debug)
    Write-Host (msg usage_help)
    Write-Host (msg usage_prefix)
    exit 0
}

if ($ArgHelp) { Show-Usage }

# ---------- 第 1 级: 检测 nvm (只检测/使用, 不安装) ----------
function Test-Nvm {
    # 调试模式: 只检查脚本目录, 判定无 nvm
    if ($ArgDebug) { return $false }
    $nvmCmd = Get-Command nvm -ErrorAction SilentlyContinue
    if ($nvmCmd) { return $true }
    if ($env:NVM_HOME) { return $true }
    if (Test-Path (Join-Path $env:NVM_HOME "nvm.exe")) { return $true }
    return $false
}

# ---------- 第 2 级: 检测 Node (>= MinMajor) ----------
# 普通模式: 检测 PATH 上的 node。调试模式: 只检查脚本目录下的 InstallDir。
function Test-Node {
    $nodeCmd = $null
    if ($ArgDebug) {
        $nodePath = Join-Path $Script:InstallDir "node.exe"
        if (Test-Path $nodePath) {
            $nodeCmd = $nodePath
            $env:Path = "$($Script:InstallDir);$env:Path"
        }
    } else {
        $nodeCmd = Get-Command node -ErrorAction SilentlyContinue
    }
    if ($nodeCmd) {
        try {
            $version = (& $nodeCmd --version 2>$null).TrimStart("v")
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
    # 32 位 PowerShell 里 $env:PROCESSOR_ARCHITECTURE 会误报 x86 (系统可能
    # 是 64 位); 用 Is64BitOperatingSystem + PROCESSOR_ARCHITEW6432 判断真实架构。
    $arch = if ([Environment]::Is64BitOperatingSystem) {
        $a = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
        if ($a -eq "ARM64") { "arm64" } else { "x64" }
    } else { "x86" }
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

# ---------- 第 3 级: 检测/安装 dsh ----------
# 检测 PATH 上的 dsh (调试模式下 PATH 已指向脚本目录 node 的全局, 视角一致)。
function Test-Dsh {
    if (Get-Command dsh -ErrorAction SilentlyContinue) {
        Write-Ok (msg dsh_ok)
        return $true
    }
    return $false
}

function Install-Dsh {
    # 提示: 未检测到 dsh，开始全局安装 @deepseek-ai/dsh ...
    Write-Info (msg dsh_not_found)
    Write-Info (msg dsh_install)
    & npm install -g $Script:DshPkg
    if ($LASTEXITCODE -ne 0) {
        Write-Fail (msg dsh_fail $Script:DshPkg)
        return $false
    }
    # npm 全局 bin 可能不在当前 PATH, 尝试补全
    if (-not (Get-Command dsh -ErrorAction SilentlyContinue)) {
        try {
            $prefix = npm prefix -g 2>$null
            if ($prefix) {
                $env:Path = "$prefix;$env:Path"
            }
        } catch { }
    }
    if (Get-Command dsh -ErrorAction SilentlyContinue) {
        Write-Ok (msg dsh_done)
        return $true
    }
    Write-Fail (msg dsh_fail $Script:DshPkg)
    return $false
}

# ---------- npm 淘宝镜像 + nrm 全局安装 (第 2.5 级, 需 node/npm 就绪) ----------
# 调试模式仅以会话级 npm_config_registry 隔离源, 安装逻辑与普通模式一致。
# nrm 安装失败不致命 (警告即可), 不影响核心工具链。
function Ensure-NpmMirror {
    # 确保当前会话 npm 可用 (直接下载安装 node 后 PATH 尚未更新)
    if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
        $npmCand = Join-Path $Script:InstallDir "npm.cmd"
        if (Test-Path $npmCand) { $env:Path = "$($Script:InstallDir);$env:Path" }
    }
    # 调试模式: 用会话级环境变量设置源/全局前缀, 不写用户 ~/.npmrc。
    # 全局前缀必须一并覆盖, 否则 ~/.npmrc 里的 prefix= 会把 npm install -g
    # 导向用户全局 (如 nvm 管理的系统 node), 破坏隔离。
    if ($ArgDebug) {
        $env:npm_config_registry = $Script:NpmRegistry
        $env:npm_config_prefix = $Script:InstallDir
    }

    if ($ArgDryRun) {
        if (Get-Command nrm -ErrorAction SilentlyContinue) { Write-Ok (msg nrm_ok) }
        else { Write-Info (msg dryrun_skip) }
        $cur = (npm config get registry 2>$null)
        if ($cur -match "npmmirror") { Write-Ok (msg registry_already $cur) }
        else { Write-Info (msg dryrun_skip) }
        return
    }

    if ($ArgDebug) {
        Write-Ok (msg registry_set $Script:NpmRegistry)
    } else {
        $cur = (npm config get registry 2>$null)
        if ($cur -match "npmmirror") {
            Write-Ok (msg registry_already $cur)
        } else {
            npm config set registry $Script:NpmRegistry 2>$null
            if ($LASTEXITCODE -ne 0) { Write-Warn (msg registry_fail $Script:NpmRegistry) }
            else { Write-Ok (msg registry_set $Script:NpmRegistry) }
        }
    }

    if (Get-Command nrm -ErrorAction SilentlyContinue) {
        Write-Ok (msg nrm_ok)
        return
    }
    Write-Info (msg nrm_install)
    & npm install -g $Script:NrmPkg 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Warn (msg nrm_fail $Script:NrmPkg)
    } else {
        Write-Ok (msg nrm_done)
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
        # report each unique removed path once (PATH may hold duplicates)
        foreach ($r in ($removed | Select-Object -Unique)) {
            Write-Warn ("  " + (msg removing $r))
        }
        # 提示: 已从当前会话 PATH 移除 nvm/node 相关项
        Write-Info (msg removed)
        $env:Path = $kept -join ";"
    } else {
        # 提示: 当前会话 PATH 中未发现 nvm / node 相关项。
        Write-Info (msg nothing_removed)
    }
}

# ---------- 主流程 ----------
function Main {
    # 提示: === 环境检测与安装 ===
    Write-Info (msg main_title)

    if ($ArgDebug) {
        # 提示: === 调试模式启用: 安装目录 = <dir> ===
        Write-Info (msg debug_title $Script:InstallDir)
        Remove-NodeFromPath
        # 调试模式: 强制安装到脚本目录, 只检查脚本目录
        $Script:InstallDir = Join-Path $Script:ScriptDir "nodejs"
    }

    # ---- 第 1 级: nvm (只检测, 不安装) ----
    $nvmFound = Test-Nvm
    if ($nvmFound) {
        Write-Ok (msg nvm_found)
    }

    # ---- 第 2 级: node (已就绪则跳过, 拒绝重复安装) ----
    $nodeInstalled = $false
    if (-not (Test-Node)) {
        if ($ArgDryRun) {
            # 提示: --dry-run 模式，跳过安装
            Write-Info (msg dryrun_skip)
            exit 1
        }

        $nodeDone = $false
        if ($ArgDebug) {
            # 调试模式不走 nvm, 强制官方下载以隔离验证
            # 提示: 调试模式: 跳过 nvm，直接官方下载...
            Write-Info (msg debug_skip_nvm)
            $nodeDone = Install-Node-Direct
        } elseif ($nvmFound) {
            $nodeDone = Install-Node-With-Nvm
            if (-not $nodeDone) {
                # 提示: nvm 安装失败，回退到官方下载方式...
                Write-Warn (msg nvm_fail_fallback)
                $nodeDone = Install-Node-Direct
            }
        } else {
            # 提示: 未检测到 nvm，使用官方下载方式...
            Write-Info (msg no_nvm)
            $nodeDone = Install-Node-Direct
        }

        if (-not $nodeDone) {
            # 提示: Node.js 安装失败，请检查网络后重试。
            Write-Fail (msg install_failed)
            exit 1
        }
        $nodeInstalled = $true
    }

    # ---- 第 2.5 级: npm 淘宝镜像 + nrm 全局安装 (需 node 就绪) ----
    Ensure-NpmMirror

    # ---- 第 3 级: dsh (已就绪则跳过, 拒绝重复安装) ----
    if (-not (Test-Dsh)) {
        if ($ArgDryRun) {
            # 提示: --dry-run 模式，跳过安装
            Write-Info (msg dryrun_skip)
            exit 1
        }
        if (-not (Install-Dsh)) {
            exit 1
        }
    }

    # ---- 环境变量 (仅当实际安装了 node 时才需要配置) ----
    if ($nodeInstalled) {
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
    } elseif ($ArgDebug -and (Test-Path "$Script:InstallDir\node.exe")) {
        # 脚本目录 node 已存在 (本次未安装): 调试模式仍需把脚本目录 node
        # 前置进会话 PATH, 否则 Remove-NodeFromPath 清掉系统 node 后会话无 node
        Write-Info (msg debug_session_only)
        $env:Path = "$Script:InstallDir;$env:Path"
    }

    Write-Host ""
    # 提示: 完成! 请重新打开终端使配置生效。
    Write-Ok (msg done)
    # 提示: 当前 Node 版本: <版本>
    $ver = (node --version 2>$null)
    if ($ver) { Write-Info (msg node_version $ver) } else { Write-Info (msg node_version "unknown") }
}

Main
