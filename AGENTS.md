# AGENTS.md

`harness-start` — 工具库：为最终用户检测/安装开发环境依赖（Node.js，后续将扩展 deepseek harness 安装）。

## 环境与工具链

- 开发机：**Windows**，shell 为 **git-bash**（MSYS/MINGW）。命令一律使用 bash 语法与路径风格（`/e/...`）。
- 本机已装 Node 22.22.1（位于 `/e/envs/node`，经 nvm 管理）。但这不代表用户环境有 Node——脚本必须自行检测。
- 脚本面向**跨平台**（Windows git-bash / macOS / Linux），不得依赖仅本机存在的工具。

## 平台与脚本对应

| 平台 | 脚本 |
| --- | --- |
| Windows | `setup-node.ps1` + `setup-node.cmd`（启动器） |
| macOS / Linux | `setup-node.sh`（bash） |

## 安装策略（三套脚本逻辑一致）

1. 检测 `node --version` 主版本是否 ≥22 → 是则跳过，结束。
2. 若用户已装 **nvm**（Windows 的 `nvm.exe` / macOS·Linux 的 `nvm` shell 函数），**优先用 nvm 安装 Node 22**。
3. nvm 安装失败或未装 nvm → 从 `nodejs.org/dist` 官方下载对应平台包，安装到指定目录（默认**脚本启动目录**下的 `nodejs`）→ 配置 PATH。

## 关键参数

- `setup-node.sh`: `--dir <路径>` / `--no-env` / `--dry-run` / `--debug` / `--help`
- `setup-node.ps1`: `-Dir <路径>` / `-NoEnv` / `-DryRun` / `-Debug` / `-Help`
- `setup-node.cmd`: 独立 cmd 实现（不依赖 PowerShell 执行，仅用于语言检测）；参数与 sh 一致，额外支持 `/nopause` 静默（默认跑完暂停窗口）。

## 多语言（i18n）

- 提示/日志按系统语言自动加载 `locales/<lang>.lang`，**检测不到或未知语言时默认中文（zh）**。
- **环境变量 `SETUP_LANG` 可覆盖系统检测**（测试/强制语言用），优先级最高。cmd 里 PowerShell 检测命令中的 `if`/`elseif` 关键字后必须留空格。
- 语言检测（三脚本一致，统一转小写再前缀匹配）：
  - Windows 读 `InstalledUICulture`（如 `zh-CN`）——**不要用 `CurrentUICulture`**：在 `chcp 65001` 下会错误回退为 `en-US`（cmd 的 `chcp 65001` 也会持久改控制台代码页）。
  - macOS/Linux 读 `$LANG`/`LC_ALL`。
  - 前缀匹配：`zh-TW/HK/MO`→`zh-TW`（繁体），`zh`→`zh`（简体），`ja/ko/fr/de/es/en`→对应，其余→`zh`。
  - `en` 需显式匹配，否则英文系统会落入默认中文。
- 现有语言包：`zh`（简体）`zh-TW`（繁体/台湾）`en` `ja` `ko` `fr` `de` `es`（各 52 个键，键名必须完全对齐）。
- 消息查找方式：
  - sh / ps1：`msg <键> [参数…]`；cmd：`call :msg <键> <参数1> <参数2>`，结果存 `!M!`。
  - 动态内容用 `{1}`、`{2}` 占位符，按传入顺序替换。
- 新增语言：在 `locales/` 加一个 `<code>.lang`（UTF-8 **无 BOM**，`KEY=message` 每行一个，`#` 开头为注释），并同步在三脚本的 `detect_lang` 里加前缀匹配。
- **`setup-node.cmd` 源码注释必须保持纯 ASCII**：cmd 会在 `chcp 65001` 生效前解析文件，含中文的多字节注释会导致解析错乱。
- **cmd 语言检测不能用 `for /f … (`命令`)` 捕获 PowerShell 输出**：`chcp 65001` 下会读错输出；应让 PowerShell 写临时文件再用 `set /p` 读取。
- **cmd 里禁止出现 `if(`**（`if` 直接紧跟左括号，即使位于双引号 PowerShell 字符串内）：cmd 会误判为块开始，破坏后续 `goto`/`call` 的 label 定位，导致 `:msg` 返回地址错乱、help 输出异常。必须写 `if (`。
- **cmd 语言检测不能用 `for /f … (`命令`)` 捕获 PowerShell 输出**：`chcp 65001` 下会读错输出；应让 PowerShell 写临时文件再用 `set /p` 读取。

## 调试模式（`--debug` / `-Debug`）

用于隔离验证安装，不受用户已有 nvm/node 影响：

1. 从**当前会话** PATH 移除所有含 `nvm` / `node` 的路径项。
2. 安装目录改为**脚本启动目录**下的 `nodejs/`（由 `.gitignore` 排除）。
3. **跳过 nvm**，强制走官方下载方式。
4. 只更新当前会话 PATH，**不写**用户持久化 PATH。

## 注意事项

- **Node 22 LTS 最新版号**在脚本顶部维护，需手动更新：
  - `setup-node.sh`: `VERSION="v22.23.2"`
  - `setup-node.ps1`: `$Script:Version = "22.23.2"`（nvm 用无 v 前缀）+ `$Script:VVersion = "v22.23.2"`（官方下载用 v 前缀）
- **`setup-node.ps1` 必须是 UTF-8 带 BOM**，否则 Windows PowerShell 5.1 会按 ANSI/GBK 解析中文注释/字符串导致语法错误。改写后需检查文件头 `EF BB BF`。
- nvm-windows 的 `nvm use` 可能需要管理员权限；脚本会提示并回退官方下载。
- 验证方式：
  - `bash -n setup-node.sh`（语法）
  - PowerShell 解析器 `ParseFile`（ps1 语法）
  - `bash setup-node.sh --dry-run` / `powershell -File setup-node.ps1 -DryRun` 本机走"已装"分支。
  - **测试安装流程时一律加 `--debug` / `-Debug` 参数**：隔离验证、跳过 nvm、安装到脚本目录 `nodejs/`，且只改当前会话 PATH、不写用户持久化 PATH，避免污染本机环境。

## 约定

- 脚本以单一文件分发、跨平台，不得依赖仅本机存在的工具。
- 后续 deepseek harness 安装逻辑作为新的脚本/步骤加入，复用本脚本的环境检测结果。
