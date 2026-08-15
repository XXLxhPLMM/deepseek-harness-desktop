#!/usr/bin/env bash
#
# setup-node.sh
# 检测当前环境是否有 Node.js 22+，如果没有则自动下载安装，并配置环境变量。
#
# 用法:
#   ./setup-node.sh                 # 使用默认安装目录 (脚本目录下的 nodejs)
#   ./setup-node.sh --dir /path     # 指定安装目录
#   ./setup-node.sh --no-env        # 不修改环境变量(PATH)
#   ./setup-node.sh --dry-run       # 只检测, 不下载
#
# 兼容: Windows(git-bash/MSYS2) / macOS / Linux
#
# 多语言: 提示/日志根据系统语言自动加载 locales/{zh,en}.lang,
#         消息以 msg <键> [参数...] 查找, {1}/{2} 为占位符按序替换。

set -euo pipefail

# ---------- 默认配置 ----------
VERSION="v22.23.2"                 # Node.js 22 LTS 最新版
MIN_MAJOR=22
BASE_URL="https://nodejs.org/dist"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="${NODE_INSTALL_DIR:-$SCRIPT_DIR/nodejs}"
DO_ENV=1
DRY_RUN=0
DEBUG_MODE=0

# ---------- 语言检测 (决定提示/日志语言: zh/zh-TW/en/ja/ko/fr/de/es, 检测不到默认中文) ----------
# 统一转小写再匹配 (兼容 macOS bash 3.2, 不用 ${var,,}); zh-TW/HK/MO -> 繁体(台湾)包。
# Windows 分支用 InstalledUICulture (系统安装 UI 语言, 不受 chcp 影响; CurrentUICulture
# 在 chcp 65001 下会错误回退为 en-US)。
DETECTED_LANG="zh"
detect_lang() {
    local lc
    lc=""
    if [[ -n "${SETUP_LANG:-}" ]]; then
        lc="$SETUP_LANG"  # 环境变量 SETUP_LANG 覆盖系统检测 (测试/强制语言用)
    elif [[ "$(uname -s)" == MINGW* || "$(uname -s)" == MSYS* ]]; then
        lc="$(powershell -NoProfile -Command '[System.Globalization.CultureInfo]::InstalledUICulture.Name' 2>/dev/null)"
    else
        lc="${LC_ALL:-${LANG:-}}"
    fi
    lc="$(printf '%s' "$lc" | tr '[:upper:]' '[:lower:]')"
    case "$lc" in
        zh*tw*|zh*hk*|zh*mo*|zh*hant*) DETECTED_LANG="zh-TW" ;;  # 台湾/香港/澳门 -> 繁体
        zh*)   DETECTED_LANG="zh" ;;
        ja*)   DETECTED_LANG="ja" ;;
        ko*)   DETECTED_LANG="ko" ;;
        fr*)   DETECTED_LANG="fr" ;;
        de*)   DETECTED_LANG="de" ;;
        es*)   DETECTED_LANG="es" ;;
        en*)   DETECTED_LANG="en" ;;
        *)     DETECTED_LANG="zh" ;;  # 检测不到或未知语言 -> 默认中文
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

# ---------- 语言文件加载 + 消息查找 ----------
# 从 locales/$DETECTED_LANG.lang 读取 KEY=message 到 MSG_<KEY> 变量。
# msg <键> [参数...]: 返回该键消息, {1}/{2} 占位符按传入顺序替换。
load_lang() {
    local file="$SCRIPT_DIR/locales/$DETECTED_LANG.lang"
    if [[ -f "$file" ]]; then
        local key val
        while IFS='=' read -r key val; do
            [[ -z "$key" || "$key" == \#* ]] && continue
            printf -v "MSG_$key" '%s' "$val"
        done < "$file"
    else
        warn "语言文件缺失: $file (使用中文)"   # 提示: 语言文件缺失，回退中文
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
    # 提示: 用法 / --dir / --no-env / --dry-run / --debug / --help
    echo "$(msg usage_usage "$0")"
    echo "$(msg usage_dir)"
    echo "$(msg usage_noenv)"
    echo "$(msg usage_dryrun)"
    echo "$(msg usage_debug)"
    echo "$(msg usage_help)"
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dir)     INSTALL_DIR="$2"; shift 2 ;;
        --no-env)  DO_ENV=0; shift ;;
        --dry-run) DRY_RUN=1; shift ;;
        --debug)   DEBUG_MODE=1; shift ;;
        --help|-h) usage ;;
        *) echo "$(msg unknown_arg "$1")" >&2; usage ;;
    esac
done

# ---------- 检测 Node ----------
detect_node() {
    local version major
    if command -v node >/dev/null 2>&1; then
        version="$(node --version 2>/dev/null | sed 's/^v//')"
        major="${version%%.*}"
        if [[ "$major" =~ ^[0-9]+$ ]] && (( major >= MIN_MAJOR )); then
            # 提示: 已检测到 Node.js <版本> (>= 22)，无需安装
            ok "$(msg node_ok "$version" "$MIN_MAJOR")"
            return 0
        else
            # 提示: 检测到 Node.js <版本>，但版本低于 22，需要安装新版本
            warn "$(msg node_low "$version" "$MIN_MAJOR")"
            return 1
        fi
    else
        # 提示: 未检测到 Node.js，开始安装...
        info "$(msg node_not_found)"
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
    # 提示: 检测到 nvm，使用 nvm 安装 Node.js 22.23.2 ...
    info "$(msg nvm_using "${VERSION#v}")"
    if nvm ls 2>/dev/null | grep -q "${VERSION#v}"; then
        # 提示: nvm 中已安装 22.23.2，直接切换...
        info "$(msg nvm_installed "${VERSION#v}")"
    else
        # 提示: nvm install 22.23.2 ...
        info "$(msg nvm_install_run "${VERSION#v}")"
        nvm install "${VERSION#v}"
    fi
    nvm use "${VERSION#v}" || {
        # 提示: nvm use 可能需要管理员权限。请手动运行: nvm use 22.23.2
        warn "$(msg nvm_use_fail "${VERSION#v}")"
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
        *) fail "$(msg os_unsupported "$(uname -s)")"; exit 1 ;;  # 提示: 不支持的操作系统: <name>
    esac

    case "$(uname -m)" in
        x86_64|amd64) arch=x64 ;;
        aarch64|arm64) arch=arm64 ;;
        i686|i386)     arch=x86 ;;
        *) fail "$(msg arch_unsupported "$(uname -m)")"; exit 1 ;;  # 提示: 不支持的架构: <arch>
    esac
    echo "$os $arch"
}

# ---------- 下载并解压 ----------
install_node() {
    local os arch dist_url tmpfile
    read -r os arch <<<"$(detect_platform)"
    # 提示: 平台: <os> / <arch>
    info "$(msg platform "$os" "$arch")"

    case "$os" in
        win)
            dist_url="$BASE_URL/$VERSION/node-$VERSION-win-$arch.zip"
            tmpfile="$SCRIPT_DIR/node-$VERSION-win-$arch.zip"
            ;;
        *)
            dist_url="$BASE_URL/$VERSION/node-$VERSION-$os-$arch.tar.gz"
            tmpfile="$SCRIPT_DIR/node-$VERSION-$os-$arch.tar.gz"
            ;;
    esac

    # 提示: 下载 <url> ...
    info "$(msg downloading "$dist_url")"
    if ! curl -L --fail --progress-bar -o "$tmpfile" "$dist_url"; then
        rm -f "$tmpfile"
        fail "$(msg download_fail "$dist_url")"   # 提示: 下载失败: <url>
        exit 1
    fi

    # 提示: 创建安装目录: <dir>
    info "$(msg mkdir "$INSTALL_DIR")"
    mkdir -p "$INSTALL_DIR"

    # 提示: 解压中...
    info "$(msg extracting)"
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
        # 提示: Node.js 已安装到 <dir>
        ok "$(msg installed "$INSTALL_DIR")"
    else
        # 提示: 解压完成，但未找到可执行文件，请检查 <dir>
        warn "$(msg exe_not_found "$INSTALL_DIR")"
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

    # 提示: 写入环境变量配置...
    info "$(msg env_writing)"

    # 1) 当前会话
    eval "$export_line"
    # 提示: 当前会话已生效: <export_line>
    ok "$(msg env_session_ok "$export_line")"

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
            # 提示: 已写入 <file>
            ok "$(msg profile_written "$pf")"
        else
            # 提示: <file> 已包含配置，跳过
            info "$(msg profile_skip "$pf")"
        fi
    done

    # 3) Windows 用户 PATH (setx)，让 cmd/PowerShell 也能用
    #    注意: 不能用 bash 的 $PATH (MSYS 风格, 含 /e/... 与 ':' 分隔) 直接 setx,
    #    否则会写入损坏的 Windows PATH。用 PowerShell 读写用户 PATH (正确处理 UTF-16,
    #    避免非 ASCII 条目在 reg/setx 控制台代码页下被写坏)。
    if [[ "$(uname -s)" == MINGW* || "$(uname -s)" == MSYS* ]] && command -v powershell >/dev/null 2>&1; then
        local winpath ps_script
        winpath="$(cygpath -w "$INSTALL_DIR")"
        ps_script="\$p=[Environment]::GetEnvironmentVariable('Path','User'); if(\$p -and (\$p.Split(';') -contains '$winpath')){ exit 2 } elseif(\$p){ [Environment]::SetEnvironmentVariable('Path', '$winpath;'+\$p, 'User') } else { [Environment]::SetEnvironmentVariable('Path', '$winpath', 'User') }"
        powershell -NoProfile -Command "$ps_script"
        case $? in
            0) ok "$(msg winpath_updated "$winpath")" ;;       # 提示: 已更新 Windows 用户 PATH (添加 <path>)
            2) info "$(msg winpath_already "$winpath")" ;;     # 提示: Windows 用户 PATH 已包含 <path>，跳过
            *) warn "$(msg winpath_fail "$winpath")" ;;        # 提示: 更新 Windows 用户 PATH 失败，请手动添加 <path>
        esac
    fi
}

# ---------- 调试模式: 从当前会话 PATH 移除 nvm/node 相关项 ----------
remove_node_from_path() {
    # 提示: 调试模式: 检测当前 PATH 中的 nvm / node 相关路径...
    info "$(msg debug_scan)"
    local kept removed item
    kept=""
    removed=""
    IFS=':' read -ra items <<<"$PATH"
    for item in "${items[@]}"; do
        [[ -z "$item" ]] && continue
        if [[ "$item" == *"nvm"* || "$item" == *"node"* ]]; then
            # 提示: 移除: <item>
            warn "  $(msg removing "$item")"
            removed="${removed:+$removed:}$item"
        else
            kept="${kept:+$kept:}$item"
        fi
    done
    if [[ -n "$removed" ]]; then
        export PATH="$kept"
        # 提示: 已从当前会话 PATH 移除 nvm/node 相关项
        info "$(msg removed)"
    else
        # 提示: 当前会话 PATH 中未发现 nvm / node 相关项。
        info "$(msg nothing_removed)"
    fi
}

# ---------- 主流程 ----------
main() {
    # 提示: === Node.js 环境检测与安装 ===
    info "$(msg main_title)"

    if [[ "$DEBUG_MODE" -eq 1 ]]; then
        # 提示: === 调试模式启用: 安装目录 = <dir> ===
        info "$(msg debug_title "$INSTALL_DIR")"
        remove_node_from_path
    fi

    if detect_node; then
        exit 0
    fi

    if [[ "$DRY_RUN" -eq 1 ]]; then
        # 提示: --dry-run 模式，跳过安装
        info "$(msg dryrun_skip)"
        exit 1
    fi

    local ok=1
    if [[ "$DEBUG_MODE" -eq 1 ]]; then
        # 提示: 调试模式: 跳过 nvm，直接官方下载...
        info "$(msg debug_skip_nvm)"
        install_node && ok=0
    elif detect_nvm; then
        if install_node_via_nvm; then
            ok=0
        else
            # 提示: nvm 安装失败，回退到官方下载方式...
            warn "$(msg nvm_fail_fallback)"
        fi
    else
        # 提示: 未检测到 nvm，使用官方下载方式...
        info "$(msg no_nvm)"
    fi

    if [[ "$ok" -ne 0 ]]; then
        install_node || exit 1
    fi

    if [[ "$DO_ENV" -eq 1 && "$DEBUG_MODE" -ne 1 ]]; then
        configure_env
    else
        if [[ "$DEBUG_MODE" -eq 1 ]]; then
            # 提示: 调试模式: 仅更新当前会话 PATH，不写用户持久化 PATH
            info "$(msg debug_session_only)"
            if [[ "$(uname -s)" == MINGW* || "$(uname -s)" == MSYS* ]]; then
                export PATH="$INSTALL_DIR:$PATH"
            else
                export PATH="$INSTALL_DIR/bin:$PATH"
            fi
        else
            # 提示: --no-env 已指定，跳过环境变量配置
            info "$(msg noenv_skip)"
            # 提示: 请手动将 <dir> 加入 PATH
            warn "$(msg noenv_manual "$INSTALL_DIR")"
        fi
    fi

    echo ""
    # 提示: 完成! 请重新打开终端使配置生效。
    ok "$(msg done)"
    # 提示: 当前 Node 版本: <版本>
    info "$(msg node_version "$(node --version 2>/dev/null || echo 'unknown')")"
}

main "$@"
