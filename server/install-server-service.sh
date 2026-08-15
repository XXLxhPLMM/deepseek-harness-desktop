#!/usr/bin/env bash
#
# install-server-service.sh
# 安装并启动 dsh web 系统服务（thin wrapper，实际动作由 server-service.sh install 完成）。
#
# 用法:
#   ./install-server-service.sh           安装并启动 dsh-web 服务
#   ./install-server-service.sh -h|--help 显示帮助
#   ./install-server-service.sh --debug   调试模式（使用脚本目录下的 nodejs/dsh）
#   ./install-server-service.sh --port 8080  指定监听端口
#   ./install-server-service.sh --host 0.0.0.0  指定绑定地址
#
# 注意: install 在 Linux 需要 root（sudo）；macOS 需要写 /Library/LaunchDaemons。
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

exec bash "$SCRIPT_DIR/server-service.sh" install "$@"
