#!/usr/bin/env bash
#
# uninstall-server-service.sh
# 卸载 dsh web 系统服务（thin wrapper，实际动作由 server-service.sh uninstall 完成）。
#
# 用法:
#   ./uninstall-server-service.sh           卸载 dsh-web 服务
#   ./uninstall-server-service.sh --help    显示帮助
#
# 复用 server-service.sh，避免逻辑重复。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

for arg in "$@"; do
    case "$arg" in
        -h|--help)
            exec bash "$SCRIPT_DIR/server-service.sh" --help
            ;;
    esac
done

exec bash "$SCRIPT_DIR/server-service.sh" uninstall "$@"
