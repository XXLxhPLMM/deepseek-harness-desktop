#!/usr/bin/env bash
#
# setup.sh
# 检测/安装整条工具链: nvm → node → npm 淘宝镜像 + nrm → dsh。逐级检查, 拒绝重复安装。
# 只做一件事: 检测当前环境缺什么, 补装什么。
#
# 用法:
#   ./setup.sh                       # 检测/安装 nvm → node → dsh (含 npm 淘宝镜像 + nrm)
#   ./setup.sh --dir /path           # 指定 node 安装目录 (默认: 脚本目录下的 nodejs)
#   ./setup.sh --no-env              # 不修改环境变量(PATH)
#   ./setup.sh --dry-run             # 只检测, 不安装
#   ./setup.sh --debug               # 调试模式: 只清当前会话环境, 隔离安装到脚本目录, 不写全局
#   ./setup.sh --help
#
# 兼容: Windows(git-bash/MSYS2) / macOS / Linux
#
# 多语言: 提示/日志根据系统语言自动加载 locales/{zh,en,...}.lang,
#         消息以 msg <键> [参数...] 查找, {1}/{2} 为占位符按序替换。

# 激活当前会话: 被 source 时 (bash), 脚本对当前 shell 的环境修改在脚本
# 结束后保留 (debug 模式把脚本目录 node 前置进 PATH 等)。用法:
#   source setup.sh --debug          # 激活当前 bash 会话 (环境保持)
#   ./setup.sh --debug               # 隔离模式 (脚本进程内生效)
if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
    ACTIVATE_MODE=1
    _SETUP_SAVED_SET="$(set +o)"
else
    ACTIVATE_MODE=0
fi
if [[ "$ACTIVATE_MODE" -eq 1 ]]; then
    # 激活模式不使用 -e: 避免脚本内未预期的错误把用户 shell 一并退出
    set -u -o pipefail
else
    set -euo pipefail
fi

# 脚本退出点 (仅用于顶层): 普通模式 exit, source 激活模式 return 回调用 shell
# 并恢复调用者原有的 shell 选项。函数内部请直接用 return N。
setup_exit() {
    local rc="${1:-0}"
    if [[ "$ACTIVATE_MODE" -eq 1 ]]; then
        eval "$_SETUP_SAVED_SET"
        return "$rc"
    fi
    exit "$rc"
}

# ---------- 默认配置 ----------
VERSION="v22.23.2"                 # Node.js 22 LTS 最新版
MIN_MAJOR=22
BASE_URL="https://nodejs.org/dist"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="${NODE_INSTALL_DIR:-$SCRIPT_DIR/nodejs}"
DSH_PKG="@deepseek-ai/dsh"
NPM_REGISTRY="https://registry.npmmirror.com"   # 淘宝 npm 镜像
NRM_PKG="nrm"
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
            key=${key%$'\r'}
            val=${val%$'\r'}
            [[ -z "$key" || "$key" == \#* ]] && continue
            printf -v "MSG_$key" '%s' "$val"
        done < "$file"
    else
        warn "语言文件缺失: $file (使用中文)"   # 提示: 语言文件缺失，回退中文
        DETECTED_LANG="zh"
        file="$SCRIPT_DIR/locales/zh.lang"
        local key2 val2
        while IFS='=' read -r key2 val2; do
            key2=${key2%$'\r'}
            val2=${val2%$'\r'}
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
    return 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dir)     INSTALL_DIR="$2"; shift 2 ;;
        --no-env)  DO_ENV=0; shift ;;
        --dry-run) DRY_RUN=1; shift ;;
        --debug)   DEBUG_MODE=1; shift ;;
        --help|-h) usage; setup_exit 0 ;;
        *) echo "$(msg unknown_arg "$1")" >&2; usage; setup_exit 0 ;;
    esac
done

is_mingw() { [[ "$(uname -s)" == MINGW* || "$(uname -s)" == MSYS* ]]; }

# ---------- 逐级检查: nvm → node → dsh (拒绝重复安装) ----------

# ---- 第 1 级: nvm (只检测/使用, 不安装) ----
# 调试模式下只检查脚本目录, 直接判定无 nvm。
detect_nvm() {
    if [[ "$DEBUG_MODE" -eq 1 ]]; then
        return 1
    fi
    # nvm 是 shell 函数, 需要先加载
    if [[ -n "${NVM_DIR:-}" && -s "$NVM_DIR/nvm.sh" ]]; then
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

# ---- 第 2 级: node (>= MIN_MAJOR) ----
# 普通模式: 检测 PATH 上的 node。调试模式: 只检查脚本目录下的 INSTALL_DIR。
detect_node() {
    local version="" major=""
    if [[ "$DEBUG_MODE" -eq 1 ]]; then
        # 调试模式: 只检查脚本目录 (INSTALL_DIR 已被强制为 SCRIPT_DIR/nodejs)
        local bin_dir="$INSTALL_DIR"
        if ! is_mingw; then bin_dir="$INSTALL_DIR/bin"; fi
        if [[ -x "$bin_dir/node" || -x "$bin_dir/node.exe" ]]; then
            export PATH="$bin_dir:$PATH"
            version="$(node --version 2>/dev/null | sed 's/^v//')"
        fi
    else
        if command -v node >/dev/null 2>&1; then
            version="$(node --version 2>/dev/null | sed 's/^v//')"
        fi
    fi
    if [[ -n "$version" ]]; then
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
    fi
    # 提示: 未检测到 Node.js，开始安装...
    info "$(msg node_not_found)"
    return 1
}

# ---- 使用 nvm 安装 Node ----
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

# ---- 平台探测 ----
detect_platform() {
    local os arch
    case "$(uname -s)" in
        Darwin) os=darwin ;;
        Linux)  os=linux ;;
        MINGW*|MSYS*|CYGWIN*)
            os=win
            # 32 位 git-bash 的 uname -m 会误报 i686/386, 用 PowerShell 查真实
            # 系统架构 (Is64BitOperatingSystem + PROCESSOR_ARCHITEW6432)
            local ps_arch
            ps_arch="$(powershell -NoProfile -Command "
                if (-not [Environment]::Is64BitOperatingSystem) { Write-Output 'x86'; exit }
                \$a = if (\$env:PROCESSOR_ARCHITEW6432) { \$env:PROCESSOR_ARCHITEW6432 } else { \$env:PROCESSOR_ARCHITECTURE }
                if (\$a -eq 'ARM64') { Write-Output 'arm64' } else { Write-Output 'x64' }" 2>/dev/null)"
            arch="${ps_arch:-x64}"
            echo "$os $arch"
            return 0
            ;;
        *) fail "$(msg os_unsupported "$(uname -s)")"; return 1 ;;  # 提示: 不支持的操作系统: <name>
    esac

    case "$(uname -m)" in
        x86_64|amd64) arch=x64 ;;
        aarch64|arm64) arch=arm64 ;;
        i686|i386)     arch=x86 ;;
        *) fail "$(msg arch_unsupported "$(uname -m)")"; return 1 ;;  # 提示: 不支持的架构: <arch>
    esac
    echo "$os $arch"
}

# ---- 下载文件: 优先 curl, 回退 wget (精简 Linux/macOS 可能只有 wget) ----
download_file() {
    local url="$1" out="$2"
    if command -v curl >/dev/null 2>&1; then
        curl -L --fail --progress-bar -o "$out" "$url" && return 0
    fi
    if command -v wget >/dev/null 2>&1; then
        # 提示: curl 不可用/失败，回退 wget 下载
        warn "$(msg download_wget_fallback "$url")"
        wget -O "$out" "$url" && return 0
    fi
    return 1
}

# ---- 下载并解压 ----
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
    if ! download_file "$dist_url" "$tmpfile"; then
        rm -f "$tmpfile"
        fail "$(msg download_fail "$dist_url")"   # 提示: 下载失败: <url>
        return 1
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

# ---- 第 2.5 级: npm 淘宝镜像 + nrm 全局安装 (需 node/npm 就绪) ----
# 调试模式仅以会话级 npm_config_registry 隔离源, 安装逻辑与普通模式一致。
# nrm 安装失败不致命 (警告即可), 不影响核心工具链。
ensure_npm_mirror() {
    # 确保当前会话 npm 可用 (直接下载安装 node 后 PATH 尚未更新)
    if ! command -v npm >/dev/null 2>&1; then
        local npm_cand="$INSTALL_DIR"
        if ! is_mingw; then npm_cand="$INSTALL_DIR/bin"; fi
        if [[ -x "$npm_cand/npm" || -x "$npm_cand/npm.cmd" ]]; then
            export PATH="$npm_cand:$PATH"
        fi
    fi
    # 调试模式: 用会话级环境变量设置源/全局前缀, 不写用户 ~/.npmrc。
    # 全局前缀必须一并覆盖, 否则 ~/.npmrc 里的 prefix= 会把 npm install -g
    # 导向用户全局 (如 nvm 管理的系统 node), 破坏隔离。
    if [[ "$DEBUG_MODE" -eq 1 ]]; then
        export npm_config_registry="$NPM_REGISTRY"
        export npm_config_prefix="$INSTALL_DIR"
    fi

    if [[ "$DRY_RUN" -eq 1 ]]; then
        if command -v nrm >/dev/null 2>&1; then ok "$(msg nrm_ok)"; else info "$(msg dryrun_skip)"; fi
        local cur
        cur="$(npm config get registry 2>/dev/null || true)"
        if [[ "$cur" == *npmmirror* ]]; then ok "$(msg registry_already "$cur")"; else info "$(msg dryrun_skip)"; fi
        return 0
    fi

    if [[ "$DEBUG_MODE" -eq 1 ]]; then
        info "$(msg registry_set_session "$NPM_REGISTRY")"
    else
        local cur
        cur="$(npm config get registry 2>/dev/null || true)"
        if [[ "$cur" == *npmmirror* ]]; then
            ok "$(msg registry_already "$cur")"
        else
            if npm config set registry "$NPM_REGISTRY" 2>/dev/null; then
                ok "$(msg registry_set "$NPM_REGISTRY")"
            else
                warn "$(msg registry_fail "$NPM_REGISTRY")"
            fi
        fi
    fi

    if command -v nrm >/dev/null 2>&1; then
        ok "$(msg nrm_ok)"
        return 0
    fi
    info "$(msg nrm_install)"
    if npm install -g "$NRM_PKG" >/dev/null 2>&1; then
        ok "$(msg nrm_done)"
    else
        warn "$(msg nrm_fail "$NRM_PKG")"
    fi
    return 0
}

# ---- 第 3 级: dsh (全局安装 @deepseek-ai/dsh) ----
# 检测 PATH 上的 dsh (调试模式下 PATH 已指向脚本目录 node 的全局, 视角一致)。
detect_dsh() {
    if command -v dsh >/dev/null 2>&1; then
        ok "$(msg dsh_ok)"
        return 0
    fi
    return 1
}

install_dsh() {
    # 提示: 未检测到 dsh，开始全局安装 @deepseek-ai/dsh ...
    info "$(msg dsh_not_found)"
    info "$(msg dsh_install)"
    npm install -g "$DSH_PKG" || {
        fail "$(msg dsh_fail "$DSH_PKG")"
        return 1
    }
    # npm 全局 bin 可能不在当前 PATH, 尝试补全
    if ! command -v dsh >/dev/null 2>&1; then
        local prefix gbin
        prefix="$(npm prefix -g 2>/dev/null)"
        if [[ -n "$prefix" ]]; then
            gbin="$prefix/bin"
            if is_mingw; then gbin="$prefix"; fi
            export PATH="$gbin:$PATH"
        fi
    fi
    if command -v dsh >/dev/null 2>&1; then
        ok "$(msg dsh_done)"
        return 0
    fi
    fail "$(msg dsh_fail "$DSH_PKG")"
    return 1
}

# ---------- 配置环境变量 ----------
# 返回脚本可加载的导出语句 + 向 profile 写入
configure_env() {
    local export_line
    export_line="export PATH=\"$INSTALL_DIR/bin:\$PATH\""

    # --dry-run: 只检测不修改
    if [[ "$DRY_RUN" -eq 1 ]]; then
        info "$(msg dryrun_skip)"
        return 0
    fi

    # Windows git-bash: 二进制在根目录 (node.exe, npm.cmd)
    if is_mingw; then
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

    local marker="# >>> nodejs setup.sh >>>"
    for pf in "${profile_files[@]}"; do
        if ! grep -qF "$marker" "$pf" 2>/dev/null; then
            {
                echo ""
                echo "$marker"
                echo "$export_line"
                echo "# <<< nodejs setup.sh <<<"
            } >> "$pf"
            # 提示: 已写入 <file>
            ok "$(msg profile_written "$pf")"
        else
            # 提示: <file> 已包含配置，跳过
            info "$(msg profile_skip "$pf")"
        fi
    done

    # 3) Windows 系统 PATH，让 cmd/PowerShell/SYSTEM 服务都能用
    #    注意: 不能用 bash 的 $PATH (MSYS 风格, 含 /e/... 与 ':' 分隔) 直接 setx,
    #    否则会写入损坏的 Windows PATH。用 PowerShell 读写系统 PATH (正确处理 UTF-16,
    #    避免非 ASCII 条目在 reg/setx 控制台代码页下被写坏)。写系统 PATH 需要管理员权限。
    if is_mingw && command -v powershell >/dev/null 2>&1; then
        local winpath ps_script
        winpath="$(cygpath -w "$INSTALL_DIR")"
        # 无管理员权限时警告并跳过 (当前会话仍可用, 不写用户 PATH)
        if ! net session >/dev/null 2>&1; then
            warn "$(msg env_no_admin "$winpath")"
        else
            ps_script="try { \$p=[Environment]::GetEnvironmentVariable('Path','Machine'); if(\$p -and (\$p.Split(';') -contains '$winpath')){ exit 2 }; \$n=if(\$p){'$winpath;'+\$p}else{'$winpath'}; [Environment]::SetEnvironmentVariable('Path',\$n,'Machine') } catch { exit 1 }"
            # 用 || 捕获退出码: 否则 set -e 会把 powershell 的非零返回 (如 exit 2 = 已存在)
            # 当成致命错误, 在 case 处理前就中止脚本, 导致 setup 报失败。
            local ps_rc=0
            powershell -NoProfile -Command "$ps_script" || ps_rc=$?
            case $ps_rc in
                0) ok "$(msg winpath_updated "$winpath")" ;;       # 提示: 已更新 Windows 系统 PATH (添加 <path>)
                2) info "$(msg winpath_already "$winpath")" ;;     # 提示: Windows 系统 PATH 已包含 <path>，跳过
                *) warn "$(msg winpath_fail "$winpath")" ;;        # 提示: 更新 Windows 系统 PATH 失败，请手动添加 <path>
            esac
        fi
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
            # report each unique removed path once (PATH may hold duplicates)
            if [[ ":$removed:" != *":$item:"* ]]; then
                # 提示: 移除: <item>
                warn "  $(msg removing "$item")"
            fi
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

# ---------- 迁移用户级 node/nvm 目录到系统级 PATH (需管理员, 仅 Windows) ----------
# 让 SYSTEM 账户/开机服务也能找到 node/nvm: 非 debug + 非 dry-run + 非 --no-env
# + 管理员权限时, 把用户级 PATH 中的 node/nvm 目录移到系统级 (并从用户级删除)。
promote_user_node() {
    if [[ "$DEBUG_MODE" -eq 1 || "$DRY_RUN" -eq 1 || "$DO_ENV" -ne 1 ]]; then return; fi
    if ! is_mingw; then return; fi
    if ! command -v powershell >/dev/null 2>&1; then return; fi
    # 无管理员权限时跳过 (不写用户 PATH, 保持现状)
    if ! net session >/dev/null 2>&1; then return; fi

    local cmds=() c win targets ps_script line
    command -v node >/dev/null 2>&1 && cmds+=("node")
    command -v nvm >/dev/null 2>&1 && cmds+=("nvm")
    [[ ${#cmds[@]} -eq 0 ]] && return

    targets=""
    for c in "${cmds[@]}"; do
        win="$(cygpath -w "$(command -v "$c")" 2>/dev/null || true)"
        if [[ -n "$win" ]]; then
            targets="${targets:+$targets,}'$win'"
        fi
    done
    [[ -z "$targets" ]] && return

    # 用 PowerShell 读写机器/用户 PATH (正确处理 UTF-16 与分隔符), 输出每个目录的处理结果:
    # moved:<dir> 已迁移 / clean:<dir> 清理了用户级重复 / fail:<dir> 迁移失败
    ps_script="\$targets=@($targets)
\$m=[Environment]::GetEnvironmentVariable('Path','Machine')
\$u=[Environment]::GetEnvironmentVariable('Path','User')
if (\$null -eq \$u) { exit 0 }
\$mi=@(\$m -split ';' | Where-Object { \$_ })
\$ui=@(\$u -split ';' | Where-Object { \$_ })
foreach (\$t in \$targets) {
    \$dir=Split-Path -Parent \$t
    if (-not \$dir) { continue }
    if (\$mi -contains \$dir) {
        if (\$ui -contains \$dir) {
            \$ui=@(\$ui | Where-Object { \$_ -ne \$dir })
            \$nu=(\$ui -join ';')
            if (\$nu) { [Environment]::SetEnvironmentVariable('Path',\$nu,'User') } else { [Environment]::SetEnvironmentVariable('Path',\$null,'User') }
            Write-Output ('clean:' + \$dir)
        }
        continue
    }
    if (\$ui -contains \$dir) {
        try {
            \$nm=if (\$m) { \$dir + ';' + \$m } else { \$dir }
            [Environment]::SetEnvironmentVariable('Path',\$nm,'Machine')
            \$m=\$nm
            \$mi=@(\$m -split ';' | Where-Object { \$_ })
            \$ui=@(\$ui | Where-Object { \$_ -ne \$dir })
            \$nu=(\$ui -join ';')
            if (\$nu) { [Environment]::SetEnvironmentVariable('Path',\$nu,'User') } else { [Environment]::SetEnvironmentVariable('Path',\$null,'User') }
            Write-Output ('moved:' + \$dir)
        } catch {
            Write-Output ('fail:' + \$dir)
        }
    }
}"
    # 用 || 捕获退出码: 避免 set -e 把 powershell 非零返回当成致命错误
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        case "$line" in
            moved:*) ok "$(msg env_promoted "${line#moved:}")" ;;
            clean:*) info "$(msg env_promote_clean "${line#clean:}")" ;;
            fail:*)  warn "$(msg env_promote_fail "${line#fail:}")" ;;
        esac
    done < <(powershell -NoProfile -Command "$ps_script" 2>/dev/null)
}

# ---------- 主流程 ----------
main() {
    # 提示: === 环境检测与安装 ===
    info "$(msg main_title)"

    if [[ "$DEBUG_MODE" -eq 1 ]]; then
        # 提示: === 调试模式启用: 安装目录 = <dir> ===
        info "$(msg debug_title "$INSTALL_DIR")"
        remove_node_from_path
        # 调试模式: 强制安装到脚本目录, 只检查脚本目录
        INSTALL_DIR="$SCRIPT_DIR/nodejs"
    fi

    # ---- 第 1 级: nvm (只检测, 不安装) ----
    local nvm_found=0
    if detect_nvm; then
        nvm_found=1
        ok "$(msg nvm_found)"
    fi

    # ---- 第 2 级: node (已就绪则跳过, 拒绝重复安装) ----
    local NODE_INSTALLED=0
    if detect_node; then
        : # 已检测到, 跳过安装
    else
        if [[ "$DRY_RUN" -eq 1 ]]; then
            # 提示: --dry-run 模式，跳过安装
            info "$(msg dryrun_skip)"
            return 1
        fi

        local node_done=1 node_method="direct"
        if [[ "$DEBUG_MODE" -eq 1 ]]; then
            # 提示: 调试模式: 跳过 nvm，直接官方下载...
            info "$(msg debug_skip_nvm)"
            install_node && node_done=0
        elif [[ "$nvm_found" -eq 1 ]]; then
            if install_node_via_nvm; then
                node_done=0
                node_method="nvm"
            else
                # 提示: nvm 安装失败，回退到官方下载方式...
                warn "$(msg nvm_fail_fallback)"
            fi
        else
            # 提示: 未检测到 nvm，使用官方下载方式...
            info "$(msg no_nvm)"
        fi

        if [[ "$node_done" -ne 0 ]]; then
            install_node || return 1
            node_method="direct"
        fi
        NODE_INSTALLED=1
    fi

    # ---- 第 2.5 级: 迁移用户级 node/nvm PATH 到系统级 (SYSTEM 服务可见) ----
    promote_user_node

    # ---- 第 2.6 级: npm 淘宝镜像 + nrm 全局安装 (需 node 就绪) ----
    ensure_npm_mirror

    # ---- 第 3 级: dsh (已就绪则跳过, 拒绝重复安装) ----
    if detect_dsh; then
        : # 已检测到, 跳过安装
    else
        if [[ "$DRY_RUN" -eq 1 ]]; then
            # 提示: --dry-run 模式，跳过安装
            info "$(msg dryrun_skip)"
            return 1
        fi
        install_dsh || return 1
    fi

    # ---- 环境变量 (仅当我们自己安装了 node; 系统已有 node 则不碰) ----
    if [[ "$NODE_INSTALLED" -eq 1 ]]; then
        if [[ "$DEBUG_MODE" -eq 1 ]]; then
            # 提示: 调试模式: 仅更新当前会话 PATH，不写用户持久化 PATH
            info "$(msg debug_session_only)"
            if is_mingw; then
                export PATH="$INSTALL_DIR:$PATH"
            else
                export PATH="$INSTALL_DIR/bin:$PATH"
            fi
        elif [[ "$node_method" == "nvm" ]]; then
            # 提示: node 经 nvm 安装, nvm 已管理 PATH, 不再写 INSTALL_DIR (目录并未创建)
            info "$(msg env_nvm_skip)"
        elif [[ "$DO_ENV" -eq 1 ]]; then
            configure_env
        else
            # 提示: --no-env 已指定，跳过环境变量配置
            info "$(msg noenv_skip)"
            # 提示: 请手动将 <dir> 加入 PATH
            warn "$(msg noenv_manual "$INSTALL_DIR")"
        fi
    elif [[ "$DEBUG_MODE" -eq 1 && -d "$INSTALL_DIR" ]]; then
        # 脚本目录 node 已存在 (本次未安装): 调试模式仍需把脚本目录 node
        # 前置进会话 PATH, 否则 remove_node_from_path 清掉系统 node 后会话无 node
        info "$(msg debug_session_only)"
        if is_mingw; then
            export PATH="$INSTALL_DIR:$PATH"
        else
            export PATH="$INSTALL_DIR/bin:$PATH"
        fi
    fi

    echo ""
    # 提示: 完成! 请重新打开终端使配置生效。
    ok "$(msg done)"
    # 提示: 当前 Node 版本: <版本>
    info "$(msg node_version "$(node --version 2>/dev/null || echo 'unknown')")"
}

main "$@"
rc=$?
if [[ "$ACTIVATE_MODE" -eq 1 ]]; then
    # source 激活模式: 保留环境修改, 但清掉本脚本的函数/变量, 恢复 shell 选项
    unset -f detect_lang info ok warn fail load_lang msg usage is_mingw detect_nvm \
        detect_node install_node_via_nvm detect_platform install_node ensure_npm_mirror \
        detect_dsh install_dsh configure_env remove_node_from_path promote_user_node main setup_exit 2>/dev/null
    eval "$_SETUP_SAVED_SET"
    unset ACTIVATE_MODE _SETUP_SAVED_SET 2>/dev/null
    return "$rc"
fi
exit "$rc"
