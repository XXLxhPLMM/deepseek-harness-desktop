# setup-node.ps1
# 检测当前环境是否有 Node.js 22+，如果没有则自动安装，并配置环境变量。
# Windows 原生 PowerShell 脚本。
#
# 安装策略:
#   1) 若已安装 nvm (nvm-windows)，优先使用 nvm 安装 Node 22。
#   2) 否则从 nodejs.org 官方下载 zip 安装到 -Dir (默认 $HOME\nodejs)。
#
# 用法:
#   powershell -ExecutionPolicy Bypass -File setup-node.ps1
#   powershell -ExecutionPolicy Bypass -File setup-node.ps1 -Dir "D:\envs\node"
#   powershell -ExecutionPolicy Bypass -File setup-node.ps1 -NoEnv
#   powershell -ExecutionPolicy Bypass -File setup-node.ps1 -DryRun
#
# 参数:
#   -Dir <路径>   指定安装目录 (默认: $HOME\nodejs)
#   -NoEnv        不修改 PATH 环境变量
#   -DryRun       只检测, 不下载安装

param(
    [string]$Dir,
    [switch]$NoEnv,
    [switch]$DryRun,
    [switch]$Debug,
    [switch]$Help
)

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

# 安装目录: -Dir 优先; Debug 模式装到脚本启动目录; 否则默认 $HOME\nodejs
if ($Debug) {
    $Script:InstallDir = Join-Path $Script:ScriptDir "nodejs"
} elseif ($Dir) {
    $Script:InstallDir = $Dir
} else {
    $Script:InstallDir = Join-Path $HOME "nodejs"
}

# ---------- 帮助 ----------
function Show-Usage {
    Write-Host "用法: powershell -ExecutionPolicy Bypass -File setup-node.ps1 [选项]"
    Write-Host "  -Dir <路径>   指定安装目录 (默认: $HOME\nodejs)"
    Write-Host "  -NoEnv        不修改 PATH 环境变量"
    Write-Host "  -DryRun       只检测, 不下载安装"
    Write-Host "  -Debug        调试模式: 从当前会话 PATH 移除 nvm/node 相关项, 安装到脚本目录"
    Write-Host "  -Help         显示帮助"
    exit 0
}

if ($Help) { Show-Usage }

# ---------- 颜色输出 ----------
$C_Info  = "Cyan"
$C_Ok    = "Green"
$C_Warn  = "Yellow"
$C_Err   = "Red"

function Write-Info  { Write-Host "[INFO]  $args" -ForegroundColor $C_Info }
function Write-Ok    { Write-Host "[OK]    $args" -ForegroundColor $C_Ok }
function Write-Warn  { Write-Host "[WARN]  $args" -ForegroundColor $C_Warn }
function Write-Fail  { Write-Host "[ERROR] $args" -ForegroundColor $C_Err }

# ---------- 检测 Node ----------
function Test-Node {
    $nodeCmd = Get-Command node -ErrorAction SilentlyContinue
    if ($nodeCmd) {
        try {
            $version = (node --version 2>$null).TrimStart("v")
            if ($version) {
                $major = ($version -split "\.")[0]
                if ([int]$major -ge $Script:MinMajor) {
                    Write-Ok "已检测到 Node.js $version (>= $($Script:MinMajor))，无需安装"
                    return $true
                } else {
                    Write-Warn "检测到 Node.js $version，但版本低于 $($Script:MinMajor)，需要安装新版本"
                    return $false
                }
            }
        } catch { }
    }
    Write-Info "未检测到 Node.js，开始安装..."
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
    Write-Info "检测到 nvm，使用 nvm 安装 Node.js $($Script:Version) ..."

    # nvm use 需要管理员权限; 尝试当前会话先看是否已安装该版本
    $installed = (& nvm list 2>$null) -match [regex]::Escape($Script:Version)
    if ($installed) {
        Write-Info "nvm 中已安装 $($Script:Version)，直接切换..."
    } else {
        Write-Info "nvm install $($Script:Version) ..."
        & nvm install $Script:Version
        if ($LASTEXITCODE -ne 0) {
            Write-Fail "nvm install 失败，请检查网络或 nvm 配置。"
            return $false
        }
    }

    Write-Info "nvm use $($Script:Version) ..."
    & nvm use $Script:Version
    if ($LASTEXITCODE -ne 0) {
        Write-Warn "nvm use 可能需要管理员权限。请以管理员身份打开终端，运行: nvm use $($Script:Version)"
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
    Write-Info "平台: win / $arch"

    $distUrl = "$($Script:BaseUrl)/$($Script:VVersion)/node-$($Script:VVersion)-win-$arch.zip"
    $tmpDir  = Join-Path $env:TEMP "node-setup-$PID"
    $zipPath = Join-Path $tmpDir "node.zip"
    New-Item -ItemType Directory -Force -Path $tmpDir | Out-Null

    Write-Info "下载 $distUrl ..."
    try {
        Invoke-WebRequest -Uri $distUrl -OutFile $zipPath -UseBasicParsing
    } catch {
        Write-Fail "下载失败: $($_.Exception.Message)"
        Remove-Item -Recurse -Force $tmpDir -ErrorAction SilentlyContinue
        return $false
    }

    Write-Info "创建安装目录: $Script:InstallDir"
    New-Item -ItemType Directory -Force -Path $Script:InstallDir | Out-Null

    Write-Info "解压中..."
    try {
        Expand-Archive -Path $zipPath -DestinationPath $tmpDir -Force
        $extractRoot = Get-ChildItem -Path $tmpDir -Directory -Filter "node-$($Script:VVersion)-win-$arch"
        if ($extractRoot) {
            Copy-Item -Path (Join-Path $extractRoot.FullName "*") -Destination $Script:InstallDir -Recurse -Force
        } else {
            Copy-Item -Path (Join-Path $tmpDir "*") -Destination $Script:InstallDir -Recurse -Force
        }
    } catch {
        Write-Fail "解压失败: $($_.Exception.Message)"
        Remove-Item -Recurse -Force $tmpDir -ErrorAction SilentlyContinue
        return $false
    }

    Remove-Item -Recurse -Force $tmpDir -ErrorAction SilentlyContinue

    if (Test-Path (Join-Path $Script:InstallDir "node.exe")) {
        Write-Ok "Node.js 已安装到 $Script:InstallDir"
        return $true
    } else {
        Write-Warn "解压完成，但未找到 node.exe，请检查 $Script:InstallDir"
        return $false
    }
}

# ---------- 配置环境变量 (Windows 用户 PATH) ----------
function Set-NodeEnv {
    Write-Info "写入环境变量配置..."

    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $installDir = $Script:InstallDir

    if ($userPath -and $userPath.Split(";") -contains $installDir) {
        Write-Info "用户 PATH 已包含 $installDir，跳过"
    } else {
        $newPath = if ([string]::IsNullOrEmpty($userPath)) { $installDir } else { "$installDir;$userPath" }
        [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
        Write-Ok "已添加 $installDir 到 Windows 用户 PATH"
    }

    $env:Path = "$installDir;$env:Path"
    Write-Ok "当前会话 PATH 已更新"
}

# ---------- 调试模式: 从当前会话 PATH 移除 nvm/node 相关项 ----------
function Remove-NodeFromPath {
    Write-Info "调试模式: 检测当前 PATH 中的 nvm / node 相关路径..."
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
        Write-Warn "已从当前会话 PATH 移除:"
        foreach ($r in $removed) { Write-Warn "  - $r" }
        $env:Path = $kept -join ";"
    } else {
        Write-Info "当前会话 PATH 中未发现 nvm / node 相关项。"
    }
}

# ---------- 主流程 ----------
function Main {
    Write-Info "=== Node.js 环境检测与安装 ==="

    if ($Debug) {
        Write-Info "=== 调试模式启用: 安装目录 = $Script:InstallDir ==="
        Remove-NodeFromPath
    }

    if (Test-Node) { exit 0 }

    if ($DryRun) {
        Write-Info "-DryRun 模式，跳过安装"
        exit 1
    }

    $ok = $false
    if ($Debug) {
        # 调试模式不走 nvm, 强制官方下载以隔离验证
        Write-Info "调试模式: 跳过 nvm，直接官方下载..."
        $ok = Install-Node-Direct
    } elseif (Test-Nvm) {
        $ok = Install-Node-With-Nvm
        if (-not $ok) {
            Write-Warn "nvm 安装失败，回退到官方下载方式..."
            $ok = Install-Node-Direct
        }
    } else {
        Write-Info "未检测到 nvm，使用官方下载方式..."
        $ok = Install-Node-Direct
    }

    if (-not $ok) {
        Write-Fail "Node.js 安装失败，请检查网络后重试。"
        exit 1
    }

    if ($NoEnv -or $Debug) {
        if ($Debug) {
            Write-Info "调试模式: 仅更新当前会话 PATH，不写用户持久化 PATH"
            $env:Path = "$Script:InstallDir;$env:Path"
        } else {
            Write-Info "-NoEnv 已指定，跳过环境变量配置"
            Write-Warn "请手动将 $Script:InstallDir 加入 PATH"
        }
    } else {
        Set-NodeEnv
    }

    Write-Host ""
    Write-Ok "完成! 请重新打开终端使配置生效。"
    $ver = (node --version 2>$null)
    if ($ver) { Write-Info "当前 Node 版本: $ver" } else { Write-Info "当前 Node 版本: 未知" }
}

Main
