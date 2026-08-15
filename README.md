# harness-start

一个帮助最终用户**检测并安装整条开发环境工具链**（nvm → node → dsh / deepseek harness）的跨平台脚本工具库。

只需运行一个脚本，即可逐级检测当前环境缺什么、补装什么：检测 Node.js 22+（缺失则自动安装），并确保 `dsh` 可用，全程**拒绝重复安装**。

## 特性

- **跨平台**：Windows（PowerShell / cmd）、macOS、Linux 全覆盖。
- **逐级检测安装**（nvm → node → dsh）：
  1. **nvm**：只检测/使用，从不安装。
  2. **node**：检测 `node` 主版本是否 ≥22，是则跳过；用户已装 **nvm** 时优先用 nvm 安装 Node 22；nvm 不可用或失败时，回退到 `nodejs.org` 官方下载安装。
  3. **dsh**：检测 `dsh` 命令，缺失则 `npm install -g @deepseek-ai/dsh`。
- **拒绝重复安装**：每一级已就绪即跳过，绝不重复装。
- **自动配置 PATH**：写入 shell profile（macOS/Linux）或 Windows 用户环境变量。
- **调试模式** `--debug`：清理当前会话环境变量（移除 nvm/node 相关 PATH 项）、只检查脚本目录、安装到脚本目录（node 与 dsh 均隔离），不写用户持久化 PATH。

## 文件结构

| 文件 | 平台 | 说明 |
| --- | --- | --- |
| `setup.sh` | macOS / Linux | bash 脚本 |
| `setup.ps1` | Windows | PowerShell 主脚本 |
| `setup.cmd` | Windows | cmd 启动器，双击即用 |

## 快速开始

### Windows

直接双击 `setup.cmd`，或在命令行中运行：

```bat
setup.cmd
```

也可以直接调用 PowerShell 脚本：

```powershell
powershell -ExecutionPolicy Bypass -File setup.ps1
```

### macOS / Linux

```bash
bash setup.sh
```

## 参数说明

| 参数（sh） | 参数（ps1） | 说明 |
| --- | --- | --- |
| `--dir <路径>` | `-Dir <路径>` | 指定 node 安装目录（默认：脚本目录下的 `nodejs`） |
| `--no-env` | `-NoEnv` | 不修改 PATH 环境变量 |
| `--dry-run` | `-DryRun` | 只检测，不下载安装 |
| `--debug` | `-Debug` | 调试模式：清理环境变量、只检查脚本目录、安装到脚本目录 |
| `--help` | `-Help` | 显示帮助 |

`setup.cmd` 会透传参数（如 `setup.cmd --debug`）；默认跑完会暂停窗口，加 `/nopause` 可静默退出。

### 示例

```bash
# 指定安装目录
bash setup.sh --dir /opt/nodejs

# 仅检测
bash setup.sh --dry-run

# 调试模式（隔离验证，安装到脚本目录）
bash setup.sh --debug
```

## 调试模式说明

调试模式用于**隔离验证**安装流程，不受用户已有 nvm/node 环境影响：

1. 从**当前会话** PATH 中移除所有含 `nvm` / `node` 的路径项（清理环境变量）；
2. 安装目录改为**脚本启动目录**下的 `nodejs/`（已加入 `.gitignore`）；
3. **跳过 nvm**，强制走官方下载方式；
4. dsh 也隔离安装到脚本目录（`npm install -g --prefix <脚本目录>`），不碰用户全局；
5. 只更新当前会话 PATH，**不写**用户持久化 PATH；
6. 只检查脚本目录：node 只看 `nodejs/`，dsh 只看脚本目录下的候选位置。

## 版本维护

脚本顶部集中维护 Node.js 22 LTS 最新版号，升级时只需更新一处：

- `setup.sh`: `VERSION="v22.23.2"`
- `setup.ps1`: `$Script:Version = "22.23.2"` + `$Script:VVersion = "v22.23.2"`

## License

MIT
