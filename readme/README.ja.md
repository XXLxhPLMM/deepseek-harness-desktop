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
  <img src="../img/use.png" alt="harness-start スクリーンショット" />
</p>

# harness-start

**webview** ベースの **DeepSeek Harness デスクトップ ランチャー**。クロスプラットフォーム（Windows / macOS / Linux）。

ダブルクリックまたは 1 コマンドで:

- **ツールチェーン自動セットアップ**: `node → npm 淘宝ミラー + nrm → dsh` を段階的に検出/インストール。重複インストールはしません。
- **サービス自動起動**: `dsh web` をシステム サービスとして登録し、起動時に自動実行。
- **デスクトップ ウィンドウ**: システム標準の Edge / Chrome を **app モード**（アドレス バーやブックマーク バーのない独立ウィンドウ、デスクトップ アプリ風）で開いて DeepSeek Harness を起動。

## 動作の仕組み

```
start ランチャー
   │ ① setup を実行（不足ツールチェーンを自動補完）
   │ ② ポート解決: --port 引数 > サービス設定 > DSH_PORT > 既定 3080
   │ ③ dsh サービスが動作中か確認、未実行なら自動起動
   ▼
webview（Edge / Chrome --app）──►  http://localhost:<port>
```

サービスは内部で `node <dsh cli> web --port 3080 --host 127.0.0.1` として実行され、ローカル ループバック アドレスのみをリッスンします。

## クイック スタート

### Windows（推奨）

`start.cmd` をダブルクリックするか、コマンド ラインで:

```bat
start.cmd
```

PowerShell 版も使えます:

```powershell
powershell -ExecutionPolicy Bypass -File start.ps1
```

### macOS / Linux

```bash
bash start.sh
```

初回実行時に不足ツールチェーンを自動補完します（ネットワーク必須）。以降は即座に開きます。

> **初回起動前に dsh サービスをインストールしてください**（1 回だけで、起動時に自動起動します）:
>
> ```bat
> rem Windows（管理者権限）
> server\install-server-service.cmd
> ```
>
> ```bash
> # macOS / Linux（sudo）
> sudo bash server/install-server-service.sh
> ```
>
> PowerShell でも可能: `powershell -ExecutionPolicy Bypass -File server\install-server-service.ps1`。
>
> サービスが未インストールの場合、`start.cmd` / `start.ps1` / `start.sh` は検出/起動を試みるだけで、未インストールと警告します。先に上記の install を実行してください。

## スクリプト一覧

プロジェクトは 3 グループのスクリプトで構成され、各プラットフォーム間でロジックは同じです。

### 1. ランチャー（入口）— `start.cmd` / `start.ps1` / `start.sh`

日常的にはこれだけを使います。ツールチェーン検出（**dsh が準備済みなら setup をスキップ**）→ dsh サービスの検出/起動 → webview でデスクトップ ウィンドウを開く、まで自動で行います。

| 引数（cmd） | 引数（ps1） | 引数（sh） | 説明 |
| --- | --- | --- | --- |
| `--port <ポート>` | `-Port <ポート>` | `--port <ポート>` | サービス ポート（既定 3080） |
| `--debug` | `-Debug` | `--debug` | setup をデバッグ モードで実行（スクリプト ディレクトリへ隔離インストール） |
| `--help` | `-Help` | `--help` | ヘルプ表示 |
| `/nopause` | - | - | 互換引数（もはや一時停止しません） |

```bash
# Windows
start.cmd --port 8080
# macOS / Linux
bash start.sh --port 8080
```

### 2. ツールチェーン インストール — `setup.cmd` / `setup.ps1` / `setup.sh`

**1 つのことだけ**を行います: `nvm → node → (npm 淘宝ミラー + nrm) → dsh` を段階的に検出/インストール。各段階が準備済みならスキップし、再インストールはしません。

1. **nvm**: 検出/使用のみ（シェル関数 / nvm-windows）、**インストールはしない**。
2. **node**: メジャー バージョンが ≥22 か確認。不足ならまず nvm で Node 22 をインストール。nvm が使えないか失敗したら `nodejs.org` の公式ビルドを指定ディレクトリ（既定はスクリプト ディレクトリ配下 `nodejs/`）へダウンロード。
3. **npm 淘宝ミラー + nrm**: npm レジストリを `https://registry.npmmirror.com` に設定（設定済みならスキップ）、`nrm` をグローバル インストール（失敗は警告のみ、中断しない）。
4. **dsh**: 無ければ `npm install -g @deepseek-ai/dsh`（この時点で淘宝ミラーを使用）。

| 引数（sh） | 引数（ps1） | 引数（cmd） | 説明 |
| --- | --- | --- | --- |
| `--dir <パス>` | `-Dir <パス>` | `--dir <パス>` | Node インストール ディレクトリ（既定: スクリプト ディレクトリ配下 `nodejs/`） |
| `--no-env` | `-NoEnv` | `--no-env` | PATH 環境変数を変更しない |
| `--dry-run` | `-DryRun` | `--dry-run` | 検出のみ、ダウンロード/インストールしない |
| `--debug` | `-Debug` | `--debug` | デバッグ モード（下記参照） |
| `--help` | `-Help` | `--help` | ヘルプ表示 |
| - | - | `/nopause` | 互換引数（もはや一時停止しません） |

```bash
bash setup.sh --dry-run        # 現在の環境を検出のみ
bash setup.sh --dir /opt/node  # インストール ディレクトリ指定
bash setup.sh --debug          # 隔離検証インストール
```

### 3. サービス管理 — `server/` ディレクトリ

`dsh web` を**起動時に自動起動**するシステム サービスとしてインストールします。プラットフォームごとにメイン スクリプト `server-service.<ext>` が 1 つ、さらに `install` / `start` / `stop` / `uninstall` の 4 つの便利なラッパーがあります。

| プラットフォーム | サービス機構 | スクリプト |
| --- | --- | --- |
| Windows | スケジュール タスク `dsh-web`（`schtasks /sc onstart`、SYSTEM ユーザー、起動時自動起動） | `server-service.cmd` / `server-service.ps1` |
| Linux | systemd `dsh-web.service` | `server-service.sh` |
| macOS | launchd `com.deepseek-harness.dsh-web.plist` | `server-service.sh` |

統一の使い方（`server-service.<ext>`）:

| コマンド | 説明 |
| --- | --- |
| `install` | サービスを登録して起動 |
| `uninstall` | サービスをアンインストール |
| `start` / `stop` | サービスの起動 / 停止 |
| `status` | サービスの状態を表示 |

サービスは SYSTEM / root アカウントで実行され、`homedir()` がデスクトップ ユーザーと異なるため、手動起動で作られたセッションが見えません。そこで登録コマンドはサービスに `DSH_HOME=<ユーザー home>\.dsh`（dsh が公式にサポートする最優先データ ルート オーバーライド）を明示的に設定し、サービスと手動起動で**同じセッション データを共有**させます。

ラッパーは引数をそのまま透過します:

| 引数 | 説明 |
| --- | --- |
| `--port <ポート>` | ポート（既定 3080） |
| `--host <ホスト>` | バインド アドレス（既定 127.0.0.1） |
| `--debug` | スクリプト ディレクトリ配下の nodejs/dsh を使う |

例:

```bat
install-server-service.cmd --port 8080
bash install-server-service.sh
```

> Windows の `install` / `uninstall` は管理者権限、Linux / macOS は root / sudo が必要です。

**dsh の更新** — `update-dsh.<ext>`: `@deepseek-ai/dsh` を最新版へ更新し、サービスがインストール済みなら再起動して反映します:

```bat
server\update-dsh.cmd            # dsh を更新してサービスを再起動
server\update-dsh.cmd --dry-run  # 現在/最新バージョンのみ表示、更新しない
server\update-dsh.cmd --debug    # スクリプト ディレクトリ node 配下の dsh を更新
```

```bash
bash server/update-dsh.sh         # macOS / Linux、同じ引数
```

## ポート解決

ランチャーは `dsh web` のポートを次の優先順位で解決します:

1. `--port` / `-Port` コマンドライン引数
2. サービス設定で登録された `--port`
3. 環境変数 `DSH_PORT`
4. 既定 `3080`

## デバッグ モード（`--debug` / `-Debug`）

ユーザーの既存 nvm/node 環境の影響を受けない**隔離検証**用のインストールです:

1. **現在のセッション**の PATH から `nvm` / `node` を含むエントリのみを削除。システム環境変数は変更しません。
2. インストール ディレクトリをスクリプト ディレクトリ配下 `nodejs/` に強制（既に gitignore）。
3. **nvm をスキップ**し、公式ダウンロードを強制。
4. 以降の nrm/dsh は通常モードと同じロジック（`npm install -g`）: PATH がすでにスクリプト ディレクトリ node を指し、そのグローバル プレフィックスは自然に隔離されます。さらにセッション単位の `npm_config_registry` / `npm_config_prefix` で npm レジストリとグローバル ディレクトリを隔離し、ユーザーの `~/.npmrc` は**書きません**。
5. 現在のセッション PATH のみ更新し、ユーザーの永続 PATH は**書きません**。

### 現在のセッションを有効化（debug 環境を維持）

`setup.cmd` / `setup.sh` / `setup.ps1` を直接実行すると、スクリプトの環境変更は自プロセス内のみで有効（終了時に復元）です。**現在のターミナル セッション**もデバッグ環境（`node` がスクリプト ディレクトリ `nodejs/` を指す、npm は淘宝ミラー）に切り替えたい場合は、有効化式の呼び出しを使います:

| shell | 有効化コマンド | 説明 |
| --- | --- | --- |
| cmd | `call setup.cmd --debug` | `call` は同じ cmd インスタンス内で実行、環境は保持 |
| git-bash / bash | `source setup.sh --debug` | `source` は現在のシェル内で実行、環境は保持 |
| PowerShell | `.\setup.ps1 -Debug` | `$env:` の変更は自然に保持、そのまま実行で可 |

有効化後、現在のセッションはデバッグ環境に切り替わります（`node -v` がスクリプト ディレクトリ版を表示）。ユーザーの永続 PATH は書きません。新しいターミナルには影響しません。

## 多言語（i18n）

プロンプト/ログはシステム言語に基づき `locales/<lang>.lang` を自動ロードします。**8 言語**: `zh`、`zh-TW`、`en`、`ja`、`ko`、`fr`、`de`、`es`。検出できない場合や不明な言語は既定で中国語。

環境変数 `SETUP_LANG` で言語を強制できます（最優先）。例: `SETUP_LANG=en start.cmd`。

## バージョン管理

Node.js 22 LTS の最新版番号はスクリプト上部に集約して管理され、アップグレードは 1 箇所の変更で済みます:

- `setup.sh`: `VERSION="v22.23.2"`
- `setup.ps1`: `$Script:Version = "22.23.2"` + `$Script:VVersion = "v22.23.2"`
- `setup.cmd`: `VERSION=v22.23.2` + `NVM_VERSION=22.23.2`

## License

MIT