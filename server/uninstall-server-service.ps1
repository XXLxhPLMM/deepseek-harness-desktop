# uninstall-server-service.ps1
# 卸载 dsh web 系统服务 (thin wrapper)。实际动作由 server-service.ps1 uninstall 完成。
#
# 用法:
#   powershell -ExecutionPolicy Bypass -File uninstall-server-service.ps1
#   powershell -ExecutionPolicy Bypass -File uninstall-server-service.ps1 -Help

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Target = Join-Path $ScriptDir "server-service.ps1"

$isHelp = $false
foreach ($a in $args) {
    $low = "$a".ToLower().TrimStart("-", "/")
    if ($low -eq "help" -or $low -eq "h") { $isHelp = $true; break }
}

if ($isHelp) {
    $LASTEXITCODE = 0
    & $Target -Help
    exit $LASTEXITCODE
}

$LASTEXITCODE = 0
& $Target uninstall
exit $LASTEXITCODE
