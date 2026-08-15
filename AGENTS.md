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
3. nvm 安装失败或未装 nvm → 从 `nodejs.org/dist` 官方下载对应平台包，安装到指定目录（默认 `$HOME/nodejs`）→ 配置 PATH。

## 关键参数

- `setup-node.sh`: `--dir <路径>` / `--no-env` / `--dry-run` / `--debug` / `--help`
- `setup-node.ps1`: `-Dir <路径>` / `-NoEnv` / `-DryRun` / `-Debug` / `-Help`
- `setup-node.cmd`: 透传参数给 ps1（`--debug` 等均可）；默认跑完暂停窗口，`/nopause` 静默。

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

## 约定

- 脚本以单一文件分发、跨平台，不得依赖仅本机存在的工具。
- 后续 deepseek harness 安装逻辑作为新的脚本/步骤加入，复用本脚本的环境检测结果。
