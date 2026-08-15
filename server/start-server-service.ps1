# start-server-service.ps1
# 启动 dsh web 系统服务 (thin wrapper)。实际动作由 server-service.ps1 start 完成。
#
# 用法:
#   powershell -ExecutionPolicy Bypass -File start-server-service.ps1
#   powershell -ExecutionPolicy Bypass -File start-server-service.ps1 -Help

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

& $Target start
exit $LASTEXITCODE
