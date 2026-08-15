#!/usr/bin/env bash
#
# start.sh
# deepseek harness 启动器: 先运行 setup 确保工具链就绪, 检测 dsh 服务是否在运行,
# 解析服务端口, 用 webview/浏览器 app 模式打开 http://localhost:<port>。
#
# 用法:
#   ./start.sh                 # 启动 deepseek harness
#   ./start.sh --port 3080     # 指定服务端口 (默认 3080)
#   ./start.sh --debug         # 调试模式: setup --debug
#   ./start.sh --help
#
# 兼容: Windows(git-bash/MSYS2) / macOS / Linux
#
# 多语言: 与 setup 共用 locales/, 键前缀 sh_。

set -euo pipefail

# ---------- 默认配置 ----------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_PORT=3080
PORT="${DSH_PORT:-$DEFAULT_PORT}"
CLI_PORT=""
DEBUG_MODE=0
SVC_NAME="dsh-web"
MACOS_LABEL="com.deepseek-harness.dsh-web"

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
    local file="$SCRIPT_DIR/locales/$DETECTED_LANG.lang"
    if [[ -f "$file" ]]; then
        local key val
        while IFS='=' read -r key val; do
            [[ -z "$key" || "$key" == \#* ]] && continue
            printf -v "MSG_$key" '%s' "$val"
        done < "$file"
    else
        warn "语言文件缺失: $file (使用中文)"
        DETECTED_LANG="zh"
        file="$SCRIPT_DIR/locales/zh.lang"
        local key2 val2
        while IFS='=' read -r key2 val2; do
            [[ -z "$key2" || "$key2" == \#* ]] && continue
            printf -v "MSG_$key2" '%s' "$val2"
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

# ---------- 解析参数 ----------
usage() {
    echo "$(msg sh_usage "$0")"
    echo "  --port <port>    dsh service port (default: $DEFAULT_PORT)"
    echo "$(msg sh_usage_debug)"
    echo "$(msg sh_usage_help)"
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --port)   PORT="${2:-$DEFAULT_PORT}"; CLI_PORT="$PORT"; shift 2 ;;
        --debug)  DEBUG_MODE=1; shift ;;
        --help|-h) usage ;;
        *) echo "$(msg sh_unknown "$1")" >&2; usage ;;
    esac
done

is_mingw() { [[ "$(uname -s)" == MINGW* || "$(uname -s)" == MSYS* ]]; }

# ---------- 1) 运行 setup 确保工具链就绪 (node + 淘宝镜像 + nrm + dsh) ----------
ensure_toolchain() {
    info "$(msg sh_setup_run)"
    if [[ "$DEBUG_MODE" -eq 1 ]]; then
        bash "$SCRIPT_DIR/setup.sh" --debug || { fail "$(msg sh_setup_fail)"; exit 1; }
    else
        bash "$SCRIPT_DIR/setup.sh" || { fail "$(msg sh_setup_fail)"; exit 1; }
    fi
}

# ---------- 2) 解析 dsh 服务端口 ----------
# 优先级: --port 参数 > 服务配置里的 --port > DSH_PORT > 默认 3080
get_dsh_port() {
    local arg_port="$1" port_file port
    if [[ -n "$arg_port" ]]; then echo "$arg_port"; return; fi
    # 从服务配置文件提取 --port
    if [[ "$(uname -s)" == Linux && -f /etc/systemd/system/$SVC_NAME.service ]]; then
        port_file="$(grep -o -- '--port [0-9]*' /etc/systemd/system/$SVC_NAME.service 2>/dev/null | grep -o '[0-9]*' | head -n1)"
        if [[ -n "$port_file" ]]; then echo "$port_file"; return; fi
    elif [[ "$(uname -s)" == Darwin && -f "/Library/LaunchDaemons/$MACOS_LABEL.plist" ]]; then
        port="$(grep -A1 '<key>--port</key>' "/Library/LaunchDaemons/$MACOS_LABEL.plist" 2>/dev/null | grep -o '[0-9]*' | head -n1)"
        if [[ -n "$port" ]]; then echo "$port"; return; fi
    fi
    echo "$PORT"
}

# ---------- 端口就绪探测 (HTTP) ----------
service_up() {
    curl -s -o /dev/null -w "%{http_code}" --connect-timeout 2 --max-time 3 "http://127.0.0.1:$PORT/" 2>/dev/null | grep -qE '^[1-9][0-9][0-9]$'
}

# ---------- 3) 检测 dsh 服务是否在运行 ----------
service_running() {
    local os
    os="$(uname -s)"
    if [[ "$os" == "Linux" ]]; then
        systemctl is-active --quiet "$SVC_NAME" 2>/dev/null && return 0
    elif [[ "$os" == "Darwin" ]]; then
        launchctl print "system/$MACOS_LABEL" >/dev/null 2>&1 && return 0
    fi
    service_up && return 0
    return 1
}

# ---------- 启动 dsh 服务 (优先用已注册的服务, 无则后台直连) ----------
start_service() {
    info "$(msg sh_service_start)"
    local svc_script="$SCRIPT_DIR/server/server-service.sh"
    local os
    os="$(uname -s)"
    if [[ -f "$svc_script" && ( "$os" == Linux || "$os" == Darwin ) ]]; then
        bash "$svc_script" start >/dev/null 2>&1 || true
    fi
    # 服务未注册或启动失败 -> 兜底: 后台直连 dsh web (脱离当前会话)
    if ! service_up; then
        if command -v dsh >/dev/null 2>&1; then
            nohup dsh web --port "$PORT" >/dev/null 2>&1 &
            disown 2>/dev/null || true
        fi
    fi
    info "$(msg sh_service_wait)"
    local i
    for i in $(seq 1 30); do
        if service_up; then return 0; fi
        sleep 1
    done
    return 1
}

# ---------- 用 webview/浏览器 app 模式打开 URL ----------
open_browser() {
    local url="$1"
    info "$(msg sh_browser "$url")"
    if is_mingw; then
        local ps edge chrome
        edge="C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe"
        [[ -f "$edge" ]] || edge="C:\\Program Files\\Microsoft\\Edge\\Application\\msedge.exe"
        [[ -f "$edge" ]] || edge="$LOCALAPPDATA\\Microsoft\\Edge\\Application\\msedge.exe"
        chrome="C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe"
        [[ -f "$chrome" ]] || chrome="C:\\Program Files (x86)\\Google\\Chrome\\Application\\chrome.exe"
        [[ -f "$chrome" ]] || chrome="$LOCALAPPDATA\\Google\\Chrome\\Application\\chrome.exe"
        if [[ -f "$edge" ]]; then
            ps="Start-Process -FilePath '$edge' -ArgumentList '--app=$url'"
        elif [[ -f "$chrome" ]]; then
            ps="Start-Process -FilePath '$chrome' -ArgumentList '--app=$url'"
        else
            ps="Start-Process '$url'"
        fi
        if powershell -NoProfile -Command "$ps" >/dev/null 2>&1; then
            return 0
        fi
        cmd //c "start \"\" \"$url\"" >/dev/null 2>&1 && return 0
    elif [[ "$(uname -s)" == "Darwin" ]]; then
        open -a "Google Chrome" --args "--app=$url" 2>/dev/null && return 0
        open -a "Microsoft Edge" --args "--app=$url" 2>/dev/null && return 0
        open "$url" 2>/dev/null && return 0
    else
        for br in google-chrome google-chrome-stable chromium chromium-browser microsoft-edge; do
            command -v "$br" >/dev/null 2>&1 && { "$br" "--app=$url" >/dev/null 2>&1 & return 0; }
        done
        command -v xdg-open >/dev/null 2>&1 && { xdg-open "$url" >/dev/null 2>&1 & return 0; }
    fi
    warn "$(msg sh_browser_fail "$url")"
}

# ---------- 主流程 ----------
main() {
    info "$(msg sh_title)"

    ensure_toolchain

    PORT="$(get_dsh_port "$CLI_PORT")"
    info "$(msg sh_port_using "$PORT")"

    local url="http://localhost:$PORT"
    if service_running; then
        ok "$(msg sh_service_running "$url")"
        open_browser "$url"
        return 0
    fi

    if start_service; then
        ok "$(msg sh_service_ready "$url")"
        open_browser "$url"
    else
        warn "$(msg sh_service_fail "$url")"
    fi
}

main "$@"
exit 0
