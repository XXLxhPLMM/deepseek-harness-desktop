#!/usr/bin/env bash
#
# server-service.sh
# 把 deepseek harness 的 `dsh web` 安装/管理为系统服务（开机自启）。
#   - Linux  -> systemd  (dsh-web.service)
#   - macOS  -> launchd  (/Library/LaunchDaemons/com.deepseek-harness.dsh-web.plist)
#
# 服务名固定为 dsh-web。运行 node <dsh cli.js> web --port <port>。
#
# 用法:
#   ./server-service.sh install   注册并启动服务 (默认端口 3080)
#   ./server-service.sh uninstall 卸载服务
#   ./server-service.sh status    查看服务状态
#   ./server-service.sh start     启动服务
#   ./server-service.sh stop      停止服务
#   ./server-service.sh --port 8080 install  指定端口 (Linux/macOS)
#   ./server-service.sh --host 127.0.0.1 install  指定绑定地址
#   ./server-service.sh --debug install  调试: 使用脚本目录下的 nodejs/dsh
#   ./server-service.sh --help
#
# 兼容: macOS / Linux。Windows 请用 server-service.ps1 / server-service.cmd。
#
# 多语言: 与 setup/start-harness 共用 locales/, 键前缀 srvc_。
# 注意: install/uninstall 需要 root/sudo 权限。

set -euo pipefail

# ---------- 默认配置 ----------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DEFAULT_PORT=3080
PORT="${DSH_PORT:-$DEFAULT_PORT}"
HOST="127.0.0.1"
DEBUG_MODE=0
SVC_NAME="dsh-web"
MACOS_LABEL="com.deepseek-harness.dsh-web"
# systemd unit 文件路径
SVC_UNIT="/etc/systemd/system/${SVC_NAME}.service"
# macOS LaunchDaemon plist
MACOS_PLIST="/Library/LaunchDaemons/${MACOS_LABEL}.plist"

# ---------- 语言检测 (与 setup.sh 一致) ----------
DETECTED_LANG="zh"
detect_lang() {
    local lc
    lc=""
    if [[ -n "${SETUP_LANG:-}" ]]; then
        lc="$SETUP_LANG"
    elif [[ "$(uname -s)" == MINGW* || "$(uname -s)" == MSYS* ]]; then
        lc="$(powershell -NoProfile -Command '[System.Globalization.CultureInfo]::InstalledUICulture.Name' 2>/dev/null)"
    else
        lc="${LC_ALL:-${LANG:-}}"
    fi
    lc="$(printf '%s' "$lc" | tr '[:upper:]' '[:lower:]')"
    case "$lc" in
        zh*tw*|zh*hk*|zh*mo*|zh*hant*) DETECTED_LANG="zh-TW" ;;
        zh*)   DETECTED_LANG="zh" ;;
        ja*)   DETECTED_LANG="ja" ;;
        ko*)   DETECTED_LANG="ko" ;;
        fr*)   DETECTED_LANG="fr" ;;
        de*)   DETECTED_LANG="de" ;;
        es*)   DETECTED_LANG="es" ;;
        en*)   DETECTED_LANG="en" ;;
        *)     DETECTED_LANG="zh" ;;
    esac
}
detect_lang

# ---------- 颜色输出 ----------
if [[ -t 1 ]]; then
    C_GREEN=$'\033[0;32m'; C_YELLOW=$'\033[0;33m'; C_RED=$'\033[0;31m'; C_CYAN=$'\033[0;36m'; C_RESET=$'\033[0m'
else
    C_GREEN=""; C_YELLOW=""; C_RED=""; C_CYAN=""; C_RESET=""
fi
info()  { echo "${C_CYAN}[INFO]${C_RESET} $*"; }
ok()    { echo "${C_GREEN}[OK]${C_RESET} $*"; }
warn()  { echo "${C_YELLOW}[WARN]${C_RESET} $*"; }
fail()  { echo "${C_RED}[ERROR]${C_RESET} $*" >&2; }

# ---------- 语言文件加载 + 消息查找 (与 setup.sh 一致) ----------
load_lang() {
    local file="$ROOT_DIR/locales/$DETECTED_LANG.lang"
    if [[ ! -f "$file" ]]; then
        DETECTED_LANG="zh"
        file="$ROOT_DIR/locales/zh.lang"
    fi
    if [[ -f "$file" ]]; then
        local key val
        while IFS='=' read -r key val; do
            [[ -z "$key" || "$key" == \#* ]] && continue
            printf -v "MSG_$key" '%s' "$val"
        done < "$file"
    fi
}
msg() {
    local key="$1" var s i
    shift
    var="MSG_$key"
    s="${!var}"
    if [[ -z "$s" ]]; then
        printf '%s' "[missing:$key]"
        return
    fi
    i=1
    for arg in "$@"; do
        s="${s//\{$i\}/$arg}"
        i=$((i+1))
    done
    printf '%s' "$s"
}
load_lang

# ---------- 平台探测 ----------
# macOS / Linux -> systemd / launchd。Windows (MINGW/MSYS/CYGWIN) 直接提示用对应脚本。
detect_os() {
    local os
    case "$(uname -s)" in
        Darwin) os=macos ;;
        Linux)  os=linux ;;
        MINGW*|MSYS*|CYGWIN*)
            fail "$(msg srvc_win_hint)"
            exit 1
            ;;
        *) fail "$(msg os_unsupported "$(uname -s)")"; exit 1 ;;
    esac
    echo "$os"
}

is_root() { [[ "$(id -u)" -eq 0 ]]; }

# ---------- 解析参数 ----------
ACTION=""
usage() {
    echo "$(msg srvc_usage "$0")"
    echo "$(msg srvc_usage_action)"
    echo "$(msg srvc_usage_uninstall)"
    echo "$(msg srvc_usage_status)"
    echo "$(msg srvc_usage_start)"
    echo "$(msg srvc_usage_stop)"
    echo "  $(msg srvc_usage_port "$DEFAULT_PORT")"
    echo "  $(msg srvc_usage_host)"
    echo "$(msg srvc_usage_debug)"
    echo "$(msg srvc_usage_help)"
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        install|uninstall|status|start|stop)
            ACTION="$1"; shift ;;
        --port)   PORT="${2:-$DEFAULT_PORT}"; shift 2 ;;
        --host)   HOST="${2:-127.0.0.1}"; shift 2 ;;
        --debug)  DEBUG_MODE=1; shift ;;
        --help|-h) usage ./server-service.sh ;;
        *) fail "$(msg srvc_unknown_action "$1")"; usage ./server-service.sh ;;
    esac
done
if [[ -z "$ACTION" ]]; then
    fail "$(msg srvc_unknown_action "")"
    usage ./server-service.sh
fi

# ---------- 解析 node 与 dsh cli 的绝对路径 (服务运行在干净环境下, 依赖 PATH 不可靠) ----------
NODE_PATH=""
DSH_CLI=""
resolve_runtime() {
    if [[ "$DEBUG_MODE" -eq 1 ]]; then
        local node_dir="$ROOT_DIR/nodejs"
        if [[ -x "$node_dir/bin/node" ]]; then
            NODE_PATH="$node_dir/bin/node"
        elif [[ -x "$node_dir/node" ]]; then
            NODE_PATH="$node_dir/node"
        fi
        # 调试模式 dsh 装到 ROOT_DIR (npm --prefix ROOT_DIR)
        local cand
        cand="$ROOT_DIR/node_modules/@deepseek-ai/dsh"
        if [[ -f "$cand/package.json" ]]; then
            DSH_CLI="$(node -e "const p=require('$cand/package.json'); const b=p.bin&&p.bin.dsh||p.bin; process.stdout.write(require('path').join('$cand', typeof b==='string'?b:b.dsh))" 2>/dev/null || echo "")"
        fi
    else
        if command -v node >/dev/null 2>&1; then
            NODE_PATH="$(command -v node)"
        fi
        if command -v npm >/dev/null 2>&1; then
            local root pj binval
            root="$(npm root -g 2>/dev/null || true)"
            pj="$root/@deepseek-ai/dsh/package.json"
            if [[ -f "$pj" ]]; then
                binval="$(node -e "const p=require('$pj'); const b=p.bin&&p.bin.dsh||p.bin; process.stdout.write(require('path').join('$root/@deepseek-ai/dsh', typeof b==='string'?b:(b&&b.dsh)||''))" 2>/dev/null || echo "")"
                if [[ -n "$binval" && -f "$binval" ]]; then
                    DSH_CLI="$binval"
                fi
            fi
        fi
    fi

    if [[ -z "$NODE_PATH" || ! -x "$NODE_PATH" ]]; then
        fail "$(msg srvc_node_fail)"
        exit 1
    fi
    if [[ -z "$DSH_CLI" || ! -f "$DSH_CLI" ]]; then
        fail "$(msg srvc_dsh_fail)"
        exit 1
    fi
}

# ---------- systemd: 检查服务是否已注册 ----------
svc_installed() {
    [[ -f "$SVC_UNIT" ]]
}

svc_active() {
    systemctl is-active --quiet "$SVC_NAME" 2>/dev/null
}

# ---------- systemd: 安装 ----------
install_systemd() {
    resolve_runtime
    if svc_installed; then
        info "$(msg srvc_exists "$SVC_NAME")"
    else
        info "$(msg srvc_install "$PORT")"
        cat > "$SVC_UNIT" <<EOF
[Unit]
Description=DeepSeek Harness Web (dsh web)
After=network.target

[Service]
Type=simple
ExecStart=$NODE_PATH "$DSH_CLI" web --port "$PORT" --host "$HOST"
Restart=always
RestartSec=3
# 继承运行环境, 让 dsh 能找到 DSH_HOME 等
EnvironmentFile=-/etc/environment

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl enable --now "$SVC_NAME"
    fi
    systemctl restart "$SVC_NAME"
    systemctl --no-pager status "$SVC_NAME" 2>&1 | head -n 8
    ok "$(msg srvc_installed "$SVC_NAME")"
}

uninstall_systemd() {
    if ! svc_installed; then
        info "$(msg srvc_not_installed)"
        exit 0
    fi
    info "$(msg srvc_uninstall)"
    systemctl disable --now "$SVC_NAME" || true
    rm -f "$SVC_UNIT"
    systemctl daemon-reload
    systemctl reset-failed "$SVC_NAME" 2>/dev/null || true
    ok "$(msg srvc_uninstalled)"
}

status_systemd() {
    if ! svc_installed; then
        info "$(msg srvc_not_installed)"
        exit 0
    fi
    if svc_active; then ok "$(msg srvc_running "$SVC_NAME")"; else warn "$(msg srvc_stopped)"; fi
}

start_systemd() {
    if ! svc_installed; then fail "$(msg srvc_not_installed)"; exit 1; fi
    info "$(msg srvc_starting)"
    systemctl start "$SVC_NAME"
    ok "$(msg srvc_started "$SVC_NAME")"
}

stop_systemd() {
    if ! svc_installed; then fail "$(msg srvc_not_installed)"; exit 1; fi
    info "$(msg srvc_stopping)"
    systemctl stop "$SVC_NAME" || true
    ok "$(msg srvc_stopped_ok)"
}

# ---------- launchd: 检查 plist ----------
daemon_installed() { [[ -f "$MACOS_PLIST" ]]; }
daemon_loaded() { launchctl print "system/$MACOS_LABEL" >/dev/null 2>&1; }

install_launchd() {
    resolve_runtime
    if daemon_installed; then
        info "$(msg srvc_exists "$MACOS_LABEL")"
    else
        info "$(msg srvc_install "$PORT")"
        # HOME 继承当前用户, 让 dsh 能定位配置 (~/.config/deepseek 或 DSH_HOME)
        cat > "$MACOS_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$MACOS_LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$NODE_PATH</string>
        <string>$DSH_CLI</string>
        <string>web</string>
        <string>--port</string>
        <string>$PORT</string>
        <string>--host</string>
        <string>$HOST</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/${MACOS_LABEL}.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/${MACOS_LABEL}.log</string>
</dict>
</plist>
EOF
        chown root:wheel "$MACOS_PLIST"
        chmod 644 "$MACOS_PLIST"
        launchctl load -w "$MACOS_PLIST" 2>/dev/null || launchctl bootstrap system "$MACOS_PLIST"
    fi
    launchctl kickstart -k "system/$MACOS_LABEL" 2>/dev/null || true
    ok "$(msg srvc_installed "$MACOS_LABEL")"
}

uninstall_launchd() {
    if ! daemon_installed; then
        info "$(msg srvc_not_installed)"
        exit 0
    fi
    info "$(msg srvc_uninstall)"
    launchctl bootout "system/$MACOS_LABEL" 2>/dev/null || launchctl unload -w "$MACOS_PLIST" 2>/dev/null || true
    rm -f "$MACOS_PLIST"
    ok "$(msg srvc_uninstalled)"
}

status_launchd() {
    if ! daemon_installed; then info "$(msg srvc_not_installed)"; exit 0; fi
    if daemon_loaded; then ok "$(msg srvc_running "$MACOS_LABEL")"; else warn "$(msg srvc_stopped)"; fi
}

start_launchd() {
    if ! daemon_installed; then fail "$(msg srvc_not_installed)"; exit 1; fi
    info "$(msg srvc_starting)"
    launchctl kickstart "system/$MACOS_LABEL" 2>/dev/null || true
    ok "$(msg srvc_started "$MACOS_LABEL")"
}

stop_launchd() {
    if ! daemon_installed; then fail "$(msg srvc_not_installed)"; exit 1; fi
    info "$(msg srvc_stopping)"
    launchctl kill SIGTERM "system/$MACOS_LABEL" 2>/dev/null || true
    ok "$(msg srvc_stopped_ok)"
}

# ---------- 主流程 ----------
main() {
    info "$(msg srvc_title)"
    local os
    os="$(detect_os)"

    case "$ACTION" in
        install)
            if ! is_root; then warn "$(msg srvc_no_admin install)"; fi
            if [[ "$os" == "linux" ]]; then install_systemd; else install_launchd; fi
            ;;
        uninstall)
            if ! is_root; then warn "$(msg srvc_no_admin uninstall)"; fi
            if [[ "$os" == "linux" ]]; then uninstall_systemd; else uninstall_launchd; fi
            ;;
        status)
            if [[ "$os" == "linux" ]]; then status_systemd; else status_launchd; fi
            ;;
        start)
            if ! is_root; then warn "$(msg srvc_no_admin start)"; fi
            if [[ "$os" == "linux" ]]; then start_systemd; else start_launchd; fi
            ;;
        stop)
            if ! is_root; then warn "$(msg srvc_no_admin stop)"; fi
            if [[ "$os" == "linux" ]]; then stop_systemd; else stop_launchd; fi
            ;;
    esac
}

main
