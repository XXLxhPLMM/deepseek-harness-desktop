<h1 align="center">harness-start</h1>

<p align="center">
  <img alt="License" src="https://img.shields.io/badge/license-MIT-green" />
  <img alt="Platform" src="https://img.shields.io/badge/platform-Windows%20%7C%20macOS%20%7C%20Linux-blue" />
  <img alt="Node" src="https://img.shields.io/badge/node-%3E%3D%2022-339933" />
</p>

<p align="center">
  <a href="README.zh.md">简体中文</a> |
  <a href="README.zh-TW.md">繁體中文</a> |
  <a href="README.en.md">English</a> |
  <a href="README.ja.md">日本語</a> |
  <a href="README.ko.md">한국어</a> |
  <a href="README.fr.md">Français</a> |
  <a href="README.de.md">Deutsch</a> |
  <a href="README.es.md">Español</a>
</p>

<p align="center">
  <img src="../img/use.png" alt="harness-start 介面截圖" />
</p>

基於 **webview** 的 **DeepSeek Harness 桌面端啟動器**，跨平台（Windows / macOS / Linux）。

雙擊或一行命令即可：

- **自動就緒工具鏈**：逐級偵測/安裝 `node → npm 淘寶鏡像 + nrm → dsh`，拒絕重複安裝；
- **服務開機自啟**：把 `dsh web` 註冊為系統服務，隨系統啟動自動運行；
- **桌面化視窗**：用系統自帶的 Edge / Chrome 以 **app 模式**（無網址列、無書籤列的獨立視窗，形如桌面應用）開啟 DeepSeek Harness。

## 工作方式

```
start 啟動器
   │ ① 運行 setup（工具鏈缺失則自動補齊）
   │ ② 解析連接埠：--port 參數 > 服務設定 > DSH_PORT > 預設 3080
   │ ③ 偵測 dsh 服務是否在執行；未執行則自動啟動
   ▼
webview（Edge / Chrome --app）──►  http://localhost:<port>
```

服務內部以 `node <dsh cli> web --port 3080 --host 127.0.0.1` 執行，僅監聽本機回環位址。

## 快速開始

### Windows（推薦）

雙擊 `start.cmd`，或在命令列：

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

首次執行會自動補齊缺失的工具鏈（需網路）；之後再次執行秒開。

> **首次啟動前，需要先安裝 dsh 服務**（一次即可，服務隨開機自啟）：
>
> ```bat
> rem Windows（系統管理員權限）
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
> 若服務尚未安裝，`start.cmd` / `start.ps1` / `start.sh` 只能偵測/嘗試啟動，會提示服務未安裝，需先執行上面的 install。

## 指令碼一覽

專案分三組指令碼，各平台之間邏輯一致。

### 1. 啟動器（入口）—— `start.cmd` / `start.ps1` / `start.sh`

日常使用只用這一個。自動完成：偵測工具鏈（**dsh 已就緒則直接跳過 setup**）→ 偵測/啟動 dsh 服務 → 用 webview 開啟桌面視窗。

| 參數（cmd） | 參數（ps1） | 參數（sh） | 說明 |
| --- | --- | --- | --- |
| `--port <連接埠>` | `-Port <連接埠>` | `--port <連接埠>` | 指定服務連接埠（預設 3080） |
| `--debug` | `-Debug` | `--debug` | 以除錯模式執行 setup（隔離安裝到指令碼目錄） |
| `--help` | `-Help` | `--help` | 顯示說明 |
| `/nopause` | - | - | 相容參數（已無暫停行為） |

```bash
# Windows
start.cmd --port 8080
# macOS / Linux
bash start.sh --port 8080
```

### 2. 工具鏈安裝 —— `setup.cmd` / `setup.ps1` / `setup.sh`

**只做一件事**：逐級偵測/安裝 `nvm → node → (npm 淘寶鏡像 + nrm) → dsh`，每一級已就緒即跳過，絕不重複安裝。

1. **nvm**：只偵測/使用（shell 函式 / nvm-windows），**從不安裝**；
2. **node**：偵測主版本是否 ≥22，不足時優先使用 nvm 安裝 Node 22；nvm 不可用或失敗時，從 `nodejs.org` 官方下載到指定目錄（預設指令碼目錄下 `nodejs/`）；
3. **npm 淘寶鏡像 + nrm**：npm 來源設為 `https://registry.npmmirror.com`（已設則跳過），並全域安裝 `nrm`（失敗僅警告，不中斷）；
4. **dsh**：缺失則 `npm install -g @deepseek-ai/dsh`（此時已走淘寶鏡像）。

| 參數（sh） | 參數（ps1） | 參數（cmd） | 說明 |
| --- | --- | --- | --- |
| `--dir <路徑>` | `-Dir <路徑>` | `--dir <路徑>` | 指定 node 安裝目錄（預設：指令碼目錄下 `nodejs/`） |
| `--no-env` | `-NoEnv` | `--no-env` | 不修改 PATH 環境變數 |
| `--dry-run` | `-DryRun` | `--dry-run` | 只偵測，不下載安裝 |
| `--debug` | `-Debug` | `--debug` | 除錯模式（見下方說明） |
| `--help` | `-Help` | `--help` | 顯示說明 |
| - | - | `/nopause` | 相容參數（已無暫停行為） |

```bash
bash setup.sh --dry-run        # 只偵測目前環境
bash setup.sh --dir /opt/node  # 指定安裝目錄
bash setup.sh --debug          # 隔離驗證安裝
```

### 3. 服務管理 —— `server/` 目錄

把 `dsh web` 安裝為**開機自啟**的系統服務。每個平台一份主指令碼 `server-service.<ext>`，外加 `install` / `start` / `stop` / `uninstall` 四個便捷 wrapper。

| 平台 | 服務機制 | 指令碼 |
| --- | --- | --- |
| Windows | 排程工作 `dsh-web`（`schtasks /sc onstart`，SYSTEM 使用者，開機自啟） | `server-service.cmd` / `server-service.ps1` |
| Linux | systemd `dsh-web.service` | `server-service.sh` |
| macOS | launchd `com.deepseek-harness.dsh-web.plist` | `server-service.sh` |

統一用法（`server-service.<ext>`）：

| 命令 | 說明 |
| --- | --- |
| `install` | 註冊並啟動服務 |
| `uninstall` | 解除安裝服務 |
| `start` / `stop` | 啟動 / 停止服務 |
| `status` | 檢視服務狀態 |

服務以 SYSTEM / root 帳戶執行，`homedir()` 與桌面使用者不同，會看不到手動啟動時產生的工作階段。因此註冊命令會為服務明確設定 `DSH_HOME=<使用者 home>\.dsh`（dsh 官方支援的最高優先順序資料根覆寫），讓服務與手動啟動**共用同一份工作階段資料**。

wrapper 直接透傳參數：

| 參數 | 說明 |
| --- | --- |
| `--port <連接埠>` | 指定連接埠（預設 3080） |
| `--host <位址>` | 指定繫結位址（預設 127.0.0.1） |
| `--debug` | 使用指令碼目錄下的 nodejs/dsh |

例如：

```bat
server\install-server-service.cmd --port 8080
bash server/install-server-service.sh
```

> Windows 的 `install` / `uninstall` 需要系統管理員權限；Linux / macOS 需要 root / sudo。

**更新 dsh** —— `update-dsh.<ext>`：把 `@deepseek-ai/dsh` 更新到最新版，若服務已安裝則自動重新啟動使其生效：

```bat
server\update-dsh.cmd          # 更新 dsh 並重新啟動服務
server\update-dsh.cmd --dry-run  # 只顯示目前/最新版本，不更新
server\update-dsh.cmd --debug    # 更新指令碼目錄 node 下的 dsh
```

```bash
bash server/update-dsh.sh       # macOS / Linux 同參數
```

## 連接埠解析

啟動器按以下優先順序解析 `dsh web` 連接埠：

1. `--port` / `-Port` 命令列參數
2. 服務設定裡註冊的 `--port`
3. 環境變數 `DSH_PORT`
4. 預設 `3080`

## 除錯模式（`--debug` / `-Debug`）

用於**隔離驗證**安裝，不受使用者已有 nvm/node 環境影響：

1. 只從**目前工作階段** PATH 移除所有含 `nvm` / `node` 的路徑項，不碰系統環境變數；
2. 安裝目錄強制為指令碼目錄下 `nodejs/`（已 gitignore）；
3. **跳過 nvm**，強制官方下載；
4. 後續 nrm/dsh 與一般模式邏輯一致（`npm install -g`）：PATH 已指向指令碼目錄 node，其全域前置詞天然隔離；並用工作階段級 `npm_config_registry` / `npm_config_prefix` 隔離 npm 來源與全域目錄，**不寫使用者 `~/.npmrc`**；
5. 只更新目前工作階段 PATH，**不寫**使用者持久化 PATH。

### 啟動目前工作階段（debug 環境保持）

直接執行 `setup.cmd` / `setup.sh` / `setup.ps1` 時，指令碼的環境修改只在其程序內生效（指令碼結束即恢復）。若想讓**目前終端工作階段**也切到除錯環境（`node` 指向指令碼目錄 `nodejs/`、npm 走淘寶鏡像），請用啟動式呼叫：

| shell | 啟動命令 | 說明 |
| --- | --- | --- |
| cmd | `call setup.cmd --debug` | `call` 在同一 cmd 實例內執行，環境保留 |
| git-bash / bash | `source setup.sh --debug` | `source` 在目前 shell 內執行，環境保留 |
| PowerShell | `.\setup.ps1 -Debug` | `$env:` 修改天然保留，直接執行即可 |

啟動後目前工作階段即切換到除錯環境（`node -v` 顯示指令碼目錄版本），不寫使用者持久化 PATH；新開終端不受影響。

## 多語言（i18n）

提示/日誌按系統語言自動載入 `locales/<lang>.lang`，共 **8 種語言**：`zh`、`zh-TW`、`en`、`ja`、`ko`、`fr`、`de`、`es`；偵測不到或未知語言時預設中文。

可用環境變數 `SETUP_LANG` 強制指定（優先順序最高），例如 `SETUP_LANG=en start.cmd`。

## 版本維護

Node.js 22 LTS 最新版號在指令碼頂部集中維護，升級只需改一處：

- `setup.sh`：`VERSION="v22.23.2"`
- `setup.ps1`：`$Script:Version = "22.23.2"` + `$Script:VVersion = "v22.23.2"`
- `setup.cmd`：`VERSION=v22.23.2` + `NVM_VERSION=22.23.2`

## License

MIT
