#!/usr/bin/env bash
#
# stop-server-service.sh
# 停止 dsh web 系统服务（thin wrapper，实际动作由 server-service.sh stop 完成）。
#
# 用法:
#   ./stop-server-service.sh           停止 dsh-web 服务
#   ./stop-server-service.sh --help    显示帮助
#   ./stop-server-service.sh --debug   透传（无实际影响，stop 不依赖 node/dsh 路径）
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

exec bash "$SCRIPT_DIR/server-service.sh" stop "$@"
