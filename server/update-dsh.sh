#!/usr/bin/env bash
#
# update-dsh.sh
# 把 @deepseek-ai/dsh 更新到最新版，若 dsh-web 服务已安装则重启使其生效。
# 兼容: macOS / Linux（Windows 请用 update-dsh.cmd / update-dsh.ps1）。
#
# 用法:
#   ./update-dsh.sh            更新 dsh 到最新版
#   ./update-dsh.sh --dry-run  只显示当前/最新版本，不更新
#   ./update-dsh.sh --debug    更新脚本目录 node 下的 dsh
#   ./update-dsh.sh --help
#
# 多语言: 与 setup/start 共用 locales/, 键前缀 ud_。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SVC_NAME="dsh-web"
MACOS_LABEL="com.deepseek-harness.dsh-web"
MACOS_PLIST="/Library/LaunchDaemons/${MACOS_LABEL}.plist"
DSH_PKG="@deepseek-ai/dsh"
DRY_RUN=0
DEBUG_MODE=0

# ---------- 语言检测 (与 server-service.sh 一致) ----------
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

# ---------- 语言文件加载 + 消息查找 (与 server-service.sh 一致) ----------
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
        i=$((i + 1))
    done
    printf '%s' "$s"
}
load_lang

# ---------- 服务是否已安装 ----------
svc_installed() {
    local os
    os="$(uname -s)"
    if [[ "$os" == Linux ]]; then
        systemctl list-unit-files "$SVC_NAME.service" >/dev/null 2>&1
    elif [[ "$os" == Darwin ]]; then
        [[ -f "$MACOS_PLIST" ]]
    else
        MSYS_NO_PATHCONV=1 schtasks /query /tn "$SVC_NAME" >/dev/null 2>&1
    fi
}

show_usage() {
    echo "$(msg ud_usage "$(basename "$0")")"
    echo "$(msg ud_usage_dryrun)"
    echo "$(msg ud_usage_debug)"
    echo "$(msg ud_usage_help)"
}

# ---------- 解析参数 ----------
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        --debug)   DEBUG_MODE=1 ;;
        -h|--help) show_usage; exit 0 ;;
        *) echo "$(msg unknown_arg "$arg")" >&2 ;;
    esac
done

info "$(msg ud_title)"

# ---------- 定位 dsh: debug 模式只认脚本目录 node 的全局 dsh ----------
if [[ "$DEBUG_MODE" -eq 1 ]]; then
    # POSIX npm 全局 bin 在 nodejs/bin, win32 布局在 nodejs/ 下 (dsh / dsh.cmd)
    if [[ ! -x "$ROOT_DIR/nodejs/dsh" && ! -x "$ROOT_DIR/nodejs/dsh.cmd" && ! -x "$ROOT_DIR/nodejs/bin/dsh" ]]; then
        fail "$(msg ud_no_dsh)"
        exit 1
    fi
    export PATH="$ROOT_DIR/nodejs/bin:$ROOT_DIR/nodejs:$PATH"
    export npm_config_prefix="$ROOT_DIR/nodejs"
else
    if ! command -v dsh >/dev/null 2>&1; then
        fail "$(msg ud_no_dsh)"
        exit 1
    fi
fi

# ---------- 当前版本 ----------
cur_ver="$(dsh --version 2>/dev/null | head -n1)"
info "$(msg ud_current "${cur_ver:-unknown}")"

if [[ "$DRY_RUN" -eq 1 ]]; then
    latest="$(npm view "$DSH_PKG" version 2>/dev/null | head -n1)"
    info "$(msg ud_latest "${latest:-unknown}")"
    if [[ -n "$cur_ver" && "$cur_ver" == "$latest" ]]; then
        ok "$(msg ud_up_to_date)"
    fi
    exit 0
fi

# ---------- 更新 ----------
info "$(msg ud_updating)"
if ! npm install -g "$DSH_PKG@latest" >/dev/null 2>&1; then
    fail "$(msg ud_fail "$DSH_PKG")"
    exit 1
fi

new_ver="$(dsh --version 2>/dev/null | head -n1)"
ok "$(msg ud_done "${new_ver:-unknown}")"

# ---------- 服务已安装则重启使其生效 ----------
if svc_installed; then
    info "$(msg ud_restarting)"
    bash "$SCRIPT_DIR/server-service.sh" stop >/dev/null 2>&1 || true
    bash "$SCRIPT_DIR/server-service.sh" start >/dev/null 2>&1 || true
    ok "$(msg ud_restart_done)"
fi