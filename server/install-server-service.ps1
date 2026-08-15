# install-server-service.ps1
# 安装并启动 dsh web 系统服务 (thin wrapper)。实际动作由 server-service.ps1 install 完成。
#
# 用法:
#   powershell -ExecutionPolicy Bypass -File install-server-service.ps1
#   powershell -ExecutionPolicy Bypass -File install-server-service.ps1 -Port 8080
#   powershell -ExecutionPolicy Bypass -File install-server-service.ps1 -Host 0.0.0.0
#   powershell -ExecutionPolicy Bypass -File install-server-service.ps1 -Debug
#   powershell -ExecutionPolicy Bypass -File install-server-service.ps1 -Help
#
# 注意: install 需要管理员权限 (sc create)。

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Target = Join-Path $ScriptDir "server-service.ps1"

$isHelp = $false
foreach ($a in $args) {
    $low = "$a".ToLower().TrimStart("-", "/")
    if ($low -eq "help" -or $low -eq "h") { $isHelp = $true; break }
}

if ($isHelp) {
    & $Target -Help
    exit $LASTEXITCODE
}

& $Target install @args
exit $LASTEXITCODE
