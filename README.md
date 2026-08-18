<h1 align="center">harness-start</h1>

<p align="center">
  <img alt="License" src="https://img.shields.io/badge/license-MIT-green" />
  <img alt="Platform" src="https://img.shields.io/badge/platform-Windows%20%7C%20macOS%20%7C%20Linux-blue" />
  <img alt="Node" src="https://img.shields.io/badge/node-%3E%3D%2022-339933" />
</p>

<p align="center">
  <a href="readme/README.zh.md">简体中文</a> |
  <a href="readme/README.zh-TW.md">繁體中文</a> |
  <a href="readme/README.en.md">English</a> |
  <a href="readme/README.ja.md">日本語</a> |
  <a href="readme/README.ko.md">한국어</a> |
  <a href="readme/README.fr.md">Français</a> |
  <a href="readme/README.de.md">Deutsch</a> |
  <a href="readme/README.es.md">Español</a>
</p>

<p align="center">
  <img src="img/use.png" alt="harness-start 界面截图" />
</p>

基于 **webview** 的 **DeepSeek Harness 桌面端启动器**，跨平台（Windows / macOS / Linux）。

双击或一行命令即可：

- **自动就绪工具链**：逐级检测/安装 `node → npm 淘宝镜像 + nrm → dsh`，拒绝重复安装；
- **服务开机自启**：把 `dsh web` 注册为系统服务，随系统启动自动运行；
- **桌面化窗口**：用系统自带的 Edge / Chrome 以 **app 模式**（无地址栏、无书签栏的独立窗口，形如桌面应用）打开 DeepSeek Harness。

## 工作方式

```
start 启动器
   │ ① 运行 setup（工具链缺失则自动补齐）
   │ ② 解析端口：--port 参数 > 服务配置 > DSH_PORT > 默认 3080
   │ ③ 检测 dsh 服务是否在运行；未运行则自动启动
   ▼
webview（Edge / Chrome --app）──►  http://localhost:<port>
```

服务内部以 `node <dsh cli> web --port 3080 --host 127.0.0.1` 运行，仅监听本机回环地址。

## 快速开始

### Windows（推荐）

双击 `start.cmd`，或在命令行：

```bat
start.cmd
```

也可用 PowerShell 版本：

```powershell
powershell -ExecutionPolicy Bypass -File start.ps1
```

### macOS / Linux

```bash
bash start.sh
```

首次运行会自动补齐缺失的工具链（需网络）；之后再次运行秒开。

> **首次启动前，需要先安装 dsh 服务**（一次即可，服务随开机自启）：
>
> ```bat
> rem Windows（管理员权限）
> server\install-server-service.cmd
> ```
>
> ```bash
> # macOS / Linux（sudo）
> sudo bash server/install-server-service.sh
> ```
>
> 也可以用 PowerShell：`powershell -ExecutionPolicy Bypass -File server\install-server-service.ps1`。
>
> 若服务尚未安装，`start.cmd` / `start.ps1` / `start.sh` 只能检测/尝试启动，会提示服务未安装，需先执行上面的 install。

## 脚本一览

项目分三组脚本，各平台之间逻辑一致。

### 1. 启动器（入口）—— `start.cmd` / `start.ps1` / `start.sh`

日常使用只用这一个。自动完成：检测工具链（**dsh 已就绪则直接跳过 setup**）→ 检测/启动 dsh 服务 → 用 webview 打开桌面窗口。

| 参数（cmd） | 参数（ps1） | 参数（sh） | 说明 |
| --- | --- | --- | --- |
| `--port <端口>` | `-Port <端口>` | `--port <端口>` | 指定服务端口（默认 3080） |
| `--debug` | `-Debug` | `--debug` | 以调试模式运行 setup（隔离安装到脚本目录） |
| `--help` | `-Help` | `--help` | 显示帮助 |
| `/nopause` | - | - | 兼容参数（已无暂停行为） |

```bash
# Windows
start.cmd --port 8080
# macOS / Linux
bash start.sh --port 8080
```

### 2. 工具链安装 —— `setup.cmd` / `setup.ps1` / `setup.sh`

**只做一件事**：逐级检测/安装 `nvm → node → (npm 淘宝镜像 + nrm) → dsh`，每一级已就绪即跳过，绝不重复安装。

1. **nvm**：只检测/使用（shell 函数 / nvm-windows），**从不安装**；
2. **node**：检测主版本是否 ≥22，不足时优先用 nvm 安装 Node 22；nvm 不可用或失败时，从 `nodejs.org` 官方下载到指定目录（默认脚本目录下 `nodejs/`）；
3. **npm 淘宝镜像 + nrm**：npm 源设为 `https://registry.npmmirror.com`（已设则跳过），并全局安装 `nrm`（失败仅警告，不中断）；
4. **dsh**：缺失则 `npm install -g @deepseek-ai/dsh`（此时已走淘宝镜像）。

| 参数（sh） | 参数（ps1） | 参数（cmd） | 说明 |
| --- | --- | --- | --- |
| `--dir <路径>` | `-Dir <路径>` | `--dir <路径>` | 指定 node 安装目录（默认：脚本目录下 `nodejs/`） |
| `--no-env` | `-NoEnv` | `--no-env` | 不修改 PATH 环境变量 |
| `--dry-run` | `-DryRun` | `--dry-run` | 只检测，不下载安装 |
| `--debug` | `-Debug` | `--debug` | 调试模式（见下方说明） |
| `--help` | `-Help` | `--help` | 显示帮助 |
| - | - | `/nopause` | 兼容参数（已无暂停行为） |

```bash
bash setup.sh --dry-run        # 只检测当前环境
bash setup.sh --dir /opt/node  # 指定安装目录
bash setup.sh --debug          # 隔离验证安装
```

### 3. 服务管理 —— `server/` 目录

把 `dsh web` 安装为**开机自启**的系统服务。每个平台一份主脚本 `server-service.<ext>`，外加 `install` / `start` / `stop` / `uninstall` 四个便捷 wrapper。

| 平台 | 服务机制 | 脚本 |
| --- | --- | --- |
| Windows | 计划任务 `dsh-web`（`schtasks /sc onstart`，SYSTEM 用户，开机自启） | `server-service.cmd` / `server-service.ps1` |
| Linux | systemd `dsh-web.service` | `server-service.sh` |
| macOS | launchd `com.deepseek-harness.dsh-web.plist` | `server-service.sh` |

统一用法（`server-service.<ext>`）：

| 命令 | 说明 |
| --- | --- |
| `install` | 注册并启动服务 |
| `uninstall` | 卸载服务 |
| `start` / `stop` | 启动 / 停止服务 |
| `status` | 查看服务状态 |

服务以 SYSTEM / root 账户运行，`homedir()` 与桌面用户不同，会看不到手动启动时产生的会话。因此注册命令会为服务显式设置 `DSH_HOME=<用户 home>\.dsh`（dsh 官方支持的最高优先级数据根覆盖），让服务与手动启动**共享同一份会话数据**。

wrapper 直接透传参数：

| 参数 | 说明 |
| --- | --- |
| `--port <端口>` | 指定端口（默认 3080） |
| `--host <地址>` | 指定绑定地址（默认 127.0.0.1） |
| `--debug` | 使用脚本目录下的 nodejs/dsh |

例如：

```bat
server\install-server-service.cmd --port 8080
bash server/install-server-service.sh
```

> Windows 的 `install` / `uninstall` 需要管理员权限；Linux / macOS 需要 root / sudo。

**更新 dsh** —— `update-dsh.<ext>`：把 `@deepseek-ai/dsh` 更新到最新版，若服务已安装则自动重启使其生效：

```bat
server\update-dsh.cmd          # 更新 dsh 并重启服务
server\update-dsh.cmd --dry-run  # 只显示当前/最新版本，不更新
server\update-dsh.cmd --debug    # 更新脚本目录 node 下的 dsh
```

```bash
bash server/update-dsh.sh       # macOS / Linux 同参数
```

## 端口解析

启动器按以下优先级解析 `dsh web` 端口：

1. `--port` / `-Port` 命令行参数
2. 服务配置里注册的 `--port`
3. 环境变量 `DSH_PORT`
4. 默认 `3080`

## 调试模式（`--debug` / `-Debug`）

用于**隔离验证**安装，不受用户已有 nvm/node 环境影响：

1. 只从**当前会话** PATH 移除所有含 `nvm` / `node` 的路径项，不碰系统环境变量；
2. 安装目录强制为脚本目录下 `nodejs/`（已 gitignore）；
3. **跳过 nvm**，强制官方下载；
4. 后续 nrm/dsh 与普通模式逻辑一致（`npm install -g`）：PATH 已指向脚本目录 node，其全局前缀天然隔离；并用会话级 `npm_config_registry` / `npm_config_prefix` 隔离 npm 源与全局目录，**不写用户 `~/.npmrc`**；
5. 只更新当前会话 PATH，**不写**用户持久化 PATH。

### 激活当前会话（debug 环境保持）

直接运行 `setup.cmd` / `setup.sh` / `setup.ps1` 时，脚本的环境修改只在其进程内生效（脚本退出即恢复）。若想让**当前终端会话**也切到调试环境（`node` 指向脚本目录 `nodejs/`、npm 走淘宝镜像），请用激活式调用：

| shell | 激活命令 | 说明 |
| --- | --- | --- |
| cmd | `call setup.cmd --debug` | `call` 在同一 cmd 实例内执行，环境保留 |
| git-bash / bash | `source setup.sh --debug` | `source` 在当前 shell 内执行，环境保留 |
| PowerShell | `.\setup.ps1 -Debug` | `$env:` 修改天然保留，直接运行即可 |

激活后当前会话即切换到调试环境（`node -v` 显示脚本目录版本），不写用户持久化 PATH；新开终端不受影响。

## 多语言（i18n）

提示/日志按系统语言自动加载 `locales/<lang>.lang`，共 **8 种语言**：`zh`、`zh-TW`、`en`、`ja`、`ko`、`fr`、`de`、`es`；检测不到或未知语言时默认中文。

可用环境变量 `SETUP_LANG` 强制指定（优先级最高），例如 `SETUP_LANG=en start.cmd`。

## 版本维护

Node.js 22 LTS 最新版号在脚本顶部集中维护，升级只需改一处：

- `setup.sh`：`VERSION="v22.23.2"`
- `setup.ps1`：`$Script:Version = "22.23.2"` + `$Script:VVersion = "v22.23.2"`
- `setup.cmd`：`VERSION=v22.23.2` + `NVM_VERSION=22.23.2`

## License

MIT
