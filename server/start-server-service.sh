#!/usr/bin/env bash
#
# start-server-service.sh
# 启动 dsh web 系统服务（thin wrapper，实际动作由 server-service.sh start 完成）。
#
# 用法:
#   ./start-server-service.sh           启动 dsh-web 服务
#   ./start-server-service.sh -h|--help 显示帮助
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

exec bash "$SCRIPT_DIR/server-service.sh" start "$@"
