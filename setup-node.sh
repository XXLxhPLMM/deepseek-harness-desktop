#!/usr/bin/env bash
#
# setup-node.sh
# 检测当前环境是否有 Node.js 22+，如果没有则自动下载安装，并配置环境变量。
#
# 用法:
#   ./setup-node.sh                 # 使用默认安装目录 ($HOME/nodejs)
#   ./setup-node.sh --dir /path     # 指定安装目录
#   ./setup-node.sh --no-env        # 不修改环境变量(PATH)
#   ./setup-node.sh --dry-run       # 只检测, 不下载
#
# 兼容: Windows(git-bash/MSYS2) / macOS / Linux
#

set -euo pipefail

# ---------- 默认配置 ----------
DEFAULT_DIR="$HOME/nodejs"
VERSION="v22.23.2"                 # Node.js 22 LTS 最新版
MIN_MAJOR=22
BASE_URL="https://nodejs.org/dist"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="${NODE_INSTALL_DIR:-$DEFAULT_DIR}"
DO_ENV=1
DRY_RUN=0
DEBUG_MODE=0

# ---------- 解析参数 ----------
usage() {
    echo "用法: $0 [选项]"
    echo "  --dir <路径>   指定安装目录 (默认: $DEFAULT_DIR)"
    echo "  --no-env       不修改 PATH 环境变量"
    echo "  --dry-run      只检测, 不下载安装"
    echo "  --debug        调试模式: 从当前会话 PATH 移除 nvm/node 相关项, 安装到脚本目录"
    echo "  --help         显示帮助"
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dir)     INSTALL_DIR="$2"; shift 2 ;;
        --no-env)  DO_ENV=0; shift ;;
        --dry-run) DRY_RUN=1; shift ;;
        --debug)   DEBUG_MODE=1; shift ;;
        --help|-h) usage ;;
        *) echo "未知参数: $1" >&2; usage ;;
    esac
done

if [[ "$DEBUG_MODE" -eq 1 ]]; then
    INSTALL_DIR="$SCRIPT_DIR/nodejs"
fi

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

# ---------- 检测 Node ----------
detect_node() {
    local version major
    if command -v node >/dev/null 2>&1; then
        version="$(node --version 2>/dev/null | sed 's/^v//')"
        major="${version%%.*}"
        if [[ "$major" =~ ^[0-9]+$ ]] && (( major >= MIN_MAJOR )); then
            ok "已检测到 Node.js $version (>= $MIN_MAJOR)，无需安装"
            return 0
        else
            warn "检测到 Node.js $version，但版本低于 $MIN_MAJOR，需要安装新版本"
            return 1
        fi
    else
        info "未检测到 Node.js，开始安装..."
        return 1
    fi
}

# ---------- 检测 nvm (macOS/Linux: shell 函数; 也可为 nvm-windows) ----------
detect_nvm() {
    # nvm 是 shell 函数, 需要先加载
    if [[ -s "$NVM_DIR/nvm.sh" ]]; then
        # shellcheck disable=SC1091
        . "$NVM_DIR/nvm.sh"
    fi
    if type nvm >/dev/null 2>&1; then
        return 0
    fi
    # nvm-windows (NVM_HOME)
    if [[ -n "${NVM_HOME:-}" ]] && command -v nvm >/dev/null 2>&1; then
        return 0
    fi
    return 1
}

# ---------- 使用 nvm 安装 Node ----------
install_node_via_nvm() {
    info "检测到 nvm，使用 nvm 安装 Node.js ${VERSION#v} ..."
    if nvm ls 2>/dev/null | grep -q "${VERSION#v}"; then
        info "nvm 中已安装 ${VERSION#v}，直接切换..."
    else
        info "nvm install ${VERSION#v} ..."
        nvm install "${VERSION#v}"
    fi
    nvm use "${VERSION#v}" || {
        warn "nvm use 可能需要管理员权限。请手动运行: nvm use ${VERSION#v}"
        return 1
    }
    return 0
}

# ---------- 平台探测 ----------
detect_platform() {
    local os arch
    case "$(uname -s)" in
        Darwin) os=darwin ;;
        Linux)  os=linux ;;
        MINGW*|MSYS*|CYGWIN*) os=win ;;
        *) fail "不支持的操作系统: $(uname -s)"; exit 1 ;;
    esac

    case "$(uname -m)" in
        x86_64|amd64) arch=x64 ;;
        aarch64|arm64) arch=arm64 ;;
        i686|i386)     arch=x86 ;;
        *) fail "不支持的架构: $(uname -m)"; exit 1 ;;
    esac
    echo "$os $arch"
}

# ---------- 下载并解压 ----------
install_node() {
    local os arch dist_url tmpfile
    read -r os arch <<<"$(detect_platform)"
    info "平台: $os / $arch"

    case "$os" in
        win)
            dist_url="$BASE_URL/$VERSION/node-$VERSION-win-$arch.zip"
            tmpfile="$(mktemp -t node-XXXXXX.zip)"
            ;;
        *)
            dist_url="$BASE_URL/$VERSION/node-$VERSION-$os-$arch.tar.gz"
            tmpfile="$(mktemp -t node-XXXXXX.tar.gz)"
            ;;
    esac

    info "下载 $dist_url ..."
    if ! curl -L --fail --progress-bar -o "$tmpfile" "$dist_url"; then
        rm -f "$tmpfile"
        fail "下载失败: $dist_url"
        exit 1
    fi

    info "创建安装目录: $INSTALL_DIR"
    mkdir -p "$INSTALL_DIR"

    info "解压中..."
    case "$os" in
        win)
            unzip -q -o "$tmpfile" -d "$(dirname "$INSTALL_DIR")"
            # 将解压出的 node-xxx-win-x64 内容移动到 INSTALL_DIR
            if [[ -d "$(dirname "$INSTALL_DIR")/node-$VERSION-win-$arch" ]]; then
                cp -rf "$(dirname "$INSTALL_DIR")/node-$VERSION-win-$arch/." "$INSTALL_DIR/"
                rm -rf "$(dirname "$INSTALL_DIR")/node-$VERSION-win-$arch"
            fi
            ;;
        *)
            tar -xzf "$tmpfile" -C "$INSTALL_DIR" --strip-components=1
            ;;
    esac
    rm -f "$tmpfile"

    # 验证
    if [[ -x "$INSTALL_DIR/bin/node" ]] || [[ -x "$INSTALL_DIR/node.exe" ]]; then
        ok "Node.js 已安装到 $INSTALL_DIR"
    else
        warn "解压完成，但未找到可执行文件，请检查 $INSTALL_DIR"
    fi
}

# ---------- 配置环境变量 ----------
# 返回脚本可加载的导出语句 + 向 profile 写入
configure_env() {
    local export_line
    export_line="export PATH=\"$INSTALL_DIR/bin:\$PATH\""

    # Windows git-bash: 二进制在根目录 (node.exe, npm.cmd)
    if [[ "$(uname -s)" == MINGW* || "$(uname -s)" == MSYS* ]]; then
        export_line="export PATH=\"$INSTALL_DIR:\$PATH\""
    fi

    info "写入环境变量配置..."

    # 1) 当前会话
    eval "$export_line"
    ok "当前会话已生效: $export_line"

    # 2) shell profile 持久化
    local profile_files=()
    if [[ -f "$HOME/.zshrc" ]]; then profile_files+=("$HOME/.zshrc"); fi
    if [[ -f "$HOME/.bashrc" ]]; then profile_files+=("$HOME/.bashrc"); fi
    if [[ -f "$HOME/.bash_profile" ]]; then profile_files+=("$HOME/.bash_profile"); fi
    if [[ ${#profile_files[@]} -eq 0 ]]; then
        profile_files+=("$HOME/.bashrc")
        touch "$HOME/.bashrc"
    fi

    local marker="# >>> nodejs setup-node.sh >>>"
    for pf in "${profile_files[@]}"; do
        if ! grep -qF "$marker" "$pf" 2>/dev/null; then
            {
                echo ""
                echo "$marker"
                echo "$export_line"
                echo "# <<< nodejs setup-node.sh <<<"
            } >> "$pf"
            ok "已写入 $pf"
        else
            info "$pf 已包含配置，跳过"
        fi
    done

    # 3) Windows 用户 PATH (setx)，让 cmd/PowerShell 也能用
    if [[ "$(uname -s)" == MINGW* || "$(uname -s)" == MSYS* ]] && command -v setx >/dev/null 2>&1; then
        local winpath
        winpath="$(cygpath -w "$INSTALL_DIR")"
        if ! echo "$PATH" | grep -qi "$INSTALL_DIR"; then
            info "将 $winpath 添加到 Windows 用户 PATH..."
            setx PATH "$winpath;$PATH" >/dev/null 2>&1 && ok "已更新 Windows 用户 PATH" || warn "setx 更新失败，请手动添加 $winpath"
        fi
    fi
}

# ---------- 调试模式: 从当前会话 PATH 移除 nvm/node 相关项 ----------
remove_node_from_path() {
    info "调试模式: 检测当前 PATH 中的 nvm / node 相关路径..."
    local kept removed item
    kept=""
    removed=""
    IFS=':' read -ra items <<<"$PATH"
    for item in "${items[@]}"; do
        [[ -z "$item" ]] && continue
        if [[ "$item" == *"nvm"* || "$item" == *"node"* ]]; then
            warn "  移除: $item"
            removed="${removed:+$removed:}$item"
        else
            kept="${kept:+$kept:}$item"
        fi
    done
    if [[ -n "$removed" ]]; then
        export PATH="$kept"
        info "已从当前会话 PATH 移除 nvm/node 相关项"
    else
        info "当前会话 PATH 中未发现 nvm / node 相关项。"
    fi
}

# ---------- 主流程 ----------
main() {
    info "=== Node.js 环境检测与安装 ==="

    if [[ "$DEBUG_MODE" -eq 1 ]]; then
        info "=== 调试模式启用: 安装目录 = $INSTALL_DIR ==="
        remove_node_from_path
    fi

    if detect_node; then
        exit 0
    fi

    if [[ "$DRY_RUN" -eq 1 ]]; then
        info "--dry-run 模式，跳过安装"
        exit 1
    fi

    local ok=1
    if [[ "$DEBUG_MODE" -eq 1 ]]; then
        info "调试模式: 跳过 nvm，直接官方下载..."
        install_node && ok=0
    elif detect_nvm; then
        if install_node_via_nvm; then
            ok=0
        else
            warn "nvm 安装失败，回退到官方下载方式..."
        fi
    else
        info "未检测到 nvm，使用官方下载方式..."
    fi

    if [[ "$ok" -ne 0 ]]; then
        install_node || exit 1
    fi

    if [[ "$DO_ENV" -eq 1 && "$DEBUG_MODE" -ne 1 ]]; then
        configure_env
    else
        if [[ "$DEBUG_MODE" -eq 1 ]]; then
            info "调试模式: 仅更新当前会话 PATH，不写用户持久化 PATH"
            export PATH="$INSTALL_DIR/bin:$PATH"
        else
            info "--no-env 已指定，跳过环境变量配置"
            warn "请手动将 $INSTALL_DIR 加入 PATH"
        fi
    fi

    echo ""
    ok "完成! 请重新打开终端使配置生效。"
    info "当前 Node 版本: $(node --version 2>/dev/null || echo '未知')"
}

main "$@"
