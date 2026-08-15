#!/usr/bin/env bash
#
# start-harness.sh
# 检测/安装 deepseek harness (dsh): 确保 Node.js 就绪、全局安装 @deepseek-ai/dsh、
# 启动 dsh 服务，并用浏览器 app 模式打开 http://localhost:<port>。
#
# 用法:
#   ./start-harness.sh                 # 检测/安装并启动
#   ./start-harness.sh --port 3080     # 指定服务端口 (默认 3080)
#   ./start-harness.sh --debug         # 调试模式: 使用脚本目录下的 nodejs
#   ./start-harness.sh --help
#
# 兼容: Windows(git-bash/MSYS2) / macOS / Linux
#
# 多语言: 与 setup 共用 locales/, 键前缀 sh_。

set -euo pipefail

# ---------- 默认配置 ----------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_PORT=3080
PORT="${DSH_PORT:-$DEFAULT_PORT}"
DEBUG_MODE=0
DSH_PKG="@deepseek-ai/dsh"

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
        --port)   PORT="${2:-$DEFAULT_PORT}"; shift 2 ;;
        --debug)  DEBUG_MODE=1; shift ;;
        --help|-h) usage ;;
        *) echo "$(msg sh_unknown "$1")" >&2; usage ;;
    esac
done

is_mingw() { [[ "$(uname -s)" == MINGW* || "$(uname -s)" == MSYS* ]]; }

# ---------- 检测 Node.js (>= 22) ----------
node_ok() {
    local version major
    if command -v node >/dev/null 2>&1; then
        version="$(node --version 2>/dev/null | sed 's/^v//')"
        major="${version%%.*}"
        if [[ "$major" =~ ^[0-9]+$ ]] && (( major >= 22 )); then
            ok "$(msg node_ok "$version" "22")"
            return 0
        fi
    fi
    return 1
}

# ---------- 确保 Node.js 就绪 ----------
# 调试模式: 优先使用脚本目录下的 nodejs/; 不存在则调用 setup --debug 安装。
# 普通模式: 检测 PATH 上的 node; 缺失则调用 setup。
ensure_node() {
    if [[ "$DEBUG_MODE" -eq 1 ]]; then
        local local_node="$SCRIPT_DIR/nodejs"
        local bin_dir="$local_node/bin"
        if is_mingw; then bin_dir="$local_node"; fi
        if [[ -x "$bin_dir/node" || -x "$bin_dir/node.exe" ]]; then
            export PATH="$bin_dir:$PATH"
            ok "$(msg sh_node_local "$local_node")"
            if node_ok; then return 0; fi
        fi
        info "$(msg sh_node_missing)"
        bash "$SCRIPT_DIR/setup.sh" --debug || { fail "$(msg sh_node_fail)"; exit 1; }
        export PATH="$bin_dir:$PATH"
        if node_ok; then return 0; fi
        fail "$(msg sh_node_fail)"; exit 1
    fi
    if node_ok; then return 0; fi
    info "$(msg sh_node_missing)"
    bash "$SCRIPT_DIR/setup.sh" || { fail "$(msg sh_node_fail)"; exit 1; }
    node_ok || { fail "$(msg sh_node_fail)"; exit 1; }
}

# ---------- 确保 dsh 已全局安装 ----------
ensure_dsh() {
    if command -v dsh >/dev/null 2>&1; then
        ok "$(msg sh_dsh_ok)"
        return 0
    fi
    info "$(msg sh_dsh_missing)"
    info "$(msg sh_dsh_install)"
    npm install -g "$DSH_PKG" || { fail "$(msg sh_dsh_fail "$DSH_PKG")"; exit 1; }
    # npm 全局 bin 可能不在当前 PATH, 尝试补全
    if ! command -v dsh >/dev/null 2>&1 && command -v npm >/dev/null 2>&1; then
        local prefix gbin
        prefix="$(npm prefix -g 2>/dev/null)"
        if [[ -n "$prefix" ]]; then
            gbin="$prefix/bin"
            if is_mingw; then gbin="$prefix"; fi
            export PATH="$gbin:$PATH"
        fi
    fi
    command -v dsh >/dev/null 2>&1 || { fail "$(msg sh_dsh_fail "$DSH_PKG")"; exit 1; }
    ok "$(msg sh_dsh_done)"
}

# ---------- 检查服务是否已运行 ----------
service_up() {
    curl -s -o /dev/null -w "%{http_code}" --connect-timeout 2 --max-time 3 "http://127.0.0.1:$PORT/" 2>/dev/null | grep -qE '^[1-9][0-9][0-9]$'
}

# ---------- 后台启动 dsh web (绑定指定端口, 完全脱离当前会话) ----------
start_service() {
    local port="$1"
    # nohup + 全 fd 重定向 + disown: 服务独立运行, 脚本结束后不阻塞、不被 SIGHUP 杀掉
    nohup dsh web --port "$port" >/dev/null 2>&1 &
    disown 2>/dev/null || true
}

# ---------- 用浏览器 app 模式打开 URL ----------
open_browser() {
    local url="$1"
    info "$(msg sh_browser "$url")"
    if is_mingw; then
        # Windows: 用 PowerShell Start-Process 启动 Edge/Chrome 的 --app 模式,
        # 回退默认浏览器。避免 cmd start 的引号/路径转义问题。
        local ps edge chrome
        edge="C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe"
        [[ -f "$edge" ]] || edge="C:\\Program Files\\Microsoft\\Edge\\Application\\msedge.exe"
        chrome="C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe"
        [[ -f "$chrome" ]] || chrome="C:\\Program Files (x86)\\Google\\Chrome\\Application\\chrome.exe"
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
        # 兜底: cmd start 默认浏览器
        cmd //c "start \"\" \"$url\"" >/dev/null 2>&1 && return 0
    elif [[ "$(uname -s)" == "Darwin" ]]; then
        # macOS: 尝试 Chrome/Edge 的 app 模式, 回退默认浏览器
        open -a "Google Chrome" --args "--app=$url" 2>/dev/null && return 0
        open -a "Microsoft Edge" --args "--app=$url" 2>/dev/null && return 0
        open "$url" 2>/dev/null && return 0
    else
        # Linux: 尝试各浏览器 app 模式, 回退 xdg-open
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
    if [[ "$DEBUG_MODE" -eq 1 ]]; then
        info "$(msg sh_node_local "$SCRIPT_DIR/nodejs")"
    fi

    ensure_node
    ensure_dsh

    local url="http://localhost:$PORT"
    if service_up; then
        ok "$(msg sh_service_running "$url")"
        open_browser "$url"
        return 0
    fi

    info "$(msg sh_service_start)"
    start_service "$PORT"
    info "$(msg sh_service_wait)"
    local i
    for i in $(seq 1 30); do
        if service_up; then break; fi
        sleep 1
    done
    if service_up; then
        ok "$(msg sh_service_ready "$url")"
        open_browser "$url"
    else
        # 服务未启动成功: 只提示, 不打开浏览器
        warn "$(msg sh_service_fail "$url")"
    fi
}

# 服务已在后台独立运行, 本脚本完成使命后自动退出 (不等待服务进程)
main "$@"
exit 0
