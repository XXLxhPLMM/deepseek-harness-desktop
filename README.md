# harness-start

一个帮助最终用户**检测并安装 Node.js 开发环境**的跨平台脚本工具库，后续将扩展 deepseek harness 的安装。

只需运行一个脚本，即可自动检测当前环境是否有 Node.js 22+，没有则自动下载安装，并配置好环境变量（PATH）。

## 特性

- **跨平台**：Windows（PowerShell / cmd）、macOS、Linux 全覆盖。
- **智能安装策略**：
  1. 检测 `node` 主版本是否 ≥22，是则跳过；
  2. 用户已装 **nvm** 时，优先用 nvm 安装 Node 22；
  3. nvm 不可用或失败时，回退到 `nodejs.org` 官方下载安装。
- **自动配置 PATH**：写入 shell profile（macOS/Linux）或 Windows 用户环境变量。
- **调试模式** `--debug`：从当前会话 PATH 中移除 nvm/node 相关项，隔离验证独立安装，安装到脚本目录。

## 文件结构

| 文件 | 平台 | 说明 |
| --- | --- | --- |
| `setup-node.sh` | macOS / Linux | bash 脚本 |
| `setup-node.ps1` | Windows | PowerShell 主脚本 |
| `setup-node.cmd` | Windows | cmd 启动器，双击即用 |

## 快速开始

### Windows

直接双击 `setup-node.cmd`，或在命令行中运行：

```bat
setup-node.cmd
```

也可以直接调用 PowerShell 脚本：

```powershell
powershell -ExecutionPolicy Bypass -File setup-node.ps1
```

### macOS / Linux

```bash
bash setup-node.sh
```

## 参数说明

| 参数（sh） | 参数（ps1） | 说明 |
| --- | --- | --- |
| `--dir <路径>` | `-Dir <路径>` | 指定安装目录（默认：脚本目录下的 `nodejs`） |
| `--no-env` | `-NoEnv` | 不修改 PATH 环境变量 |
| `--dry-run` | `-DryRun` | 只检测，不下载安装 |
| `--debug` | `-Debug` | 调试模式：移除当前会话 PATH 中的 nvm/node，安装到脚本目录 |
| `--help` | `-Help` | 显示帮助 |

`setup-node.cmd` 会透传参数给 `setup-node.ps1`（如 `setup-node.cmd --debug`）；默认跑完会暂停窗口，加 `/nopause` 可静默退出。

### 示例

```bash
# 指定安装目录
bash setup-node.sh --dir /opt/nodejs

# 仅检测
bash setup-node.sh --dry-run

# 调试模式（隔离验证，安装到脚本目录）
bash setup-node.sh --debug
```

## 调试模式说明

调试模式用于**隔离验证**安装流程，不受用户已有 nvm/node 环境影响：

1. 从**当前会话** PATH 中移除所有含 `nvm` / `node` 的路径项；
2. 安装目录改为**脚本启动目录**下的 `nodejs/`（已加入 `.gitignore`）；
3. **跳过 nvm**，强制走官方下载方式；
4. 只更新当前会话 PATH，**不写**用户持久化 PATH。

## 版本维护

脚本顶部集中维护 Node.js 22 LTS 最新版号，升级时只需更新一处：

- `setup-node.sh`: `VERSION="v22.23.2"`
- `setup-node.ps1`: `$Script:Version = "22.23.2"` + `$Script:VVersion = "v22.23.2"`

## 后续规划

- [ ] 集成 deepseek harness 安装步骤，复用本脚本的环境检测结果。

## License

MIT
