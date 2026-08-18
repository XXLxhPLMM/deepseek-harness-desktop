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
  <img src="../img/use.png" alt="harness-start 스크린샷" />
</p>

**webview** 기반의 **DeepSeek Harness 데스크톱 런처**로, 크로스 플랫폼(Windows / macOS / Linux)입니다.

더블 클릭 또는 한 줄 명령으로:

- **도구 체인 자동 준비**: `node → npm 타오바오 미러 + nrm → dsh`를 단계별로 감지/설치하고 중복 설치를 거부합니다.
- **서비스 자동 시작**: `dsh web`을 시스템 서비스로 등록하여 부팅 시 자동 실행합니다.
- **데스크톱 창**: 시스템 내장 Edge / Chrome을 **app 모드**(주소 표시줄, 북마크 바가 없는 독립 창, 데스크톱 앱처럼 보임)로 열어 DeepSeek Harness를 실행합니다.

## 작동 방식

```
start 런처
   │ ① setup 실행(누락된 도구 체인 자동 보충)
   │ ② 포트 해석: --port 인수 > 서비스 설정 > DSH_PORT > 기본 3080
   │ ③ dsh 서비스 실행 여부 확인, 실행 중이 아니면 자동 시작
   ▼
webview(Edge / Chrome --app) ──►  http://localhost:<port>
```

서비스는 내부적으로 `node <dsh cli> web --port 3080 --host 127.0.0.1`로 실행되며 로컬 루프백 주소만 수신합니다.

## 빠른 시작

### Windows(권장)

`start.cmd`를 더블 클릭하거나 명령줄에서:

```bat
start.cmd
```

PowerShell 버전도 사용할 수 있습니다:

```powershell
powershell -ExecutionPolicy Bypass -File start.ps1
```

### macOS / Linux

```bash
bash start.sh
```

첫 실행 시 누락된 도구 체인을 자동으로 보충합니다(네트워크 필요). 이후 실행은 즉시 열립니다.

> **첫 시작 전에 dsh 서비스를 먼저 설치해야 합니다**(한 번만 하면 되고 부팅 시 자동 시작됩니다):
>
> ```bat
> rem Windows(관리자 권한)
> server\install-server-service.cmd
> ```
>
> ```bash
> # macOS / Linux(sudo)
> sudo bash server/install-server-service.sh
> ```
>
> PowerShell로도 가능: `powershell -ExecutionPolicy Bypass -File server\install-server-service.ps1`.
>
> 서비스가 아직 설치되지 않았다면 `start.cmd` / `start.ps1` / `start.sh`는 감지/시작만 시도하고 미설치임을 안내합니다. 먼저 위 install을 실행하세요.

## 스크립트 개요

프로젝트는 세 그룹의 스크립트로 구성되며 플랫폼 간 로직은 동일합니다.

### 1. 런처(진입점) — `start.cmd` / `start.ps1` / `start.sh`

일상적으로는 이것만 사용합니다. 도구 체인 감지(**dsh가 준비되면 setup 건너뜀**) → dsh 서비스 감지/시작 → webview로 데스크톱 창 열기까지 자동으로 수행합니다.

| 인수(cmd) | 인수(ps1) | 인수(sh) | 설명 |
| --- | --- | --- | --- |
| `--port <포트>` | `-Port <포트>` | `--port <포트>` | 서비스 포트(기본 3080) |
| `--debug` | `-Debug` | `--debug` | setup을 디버그 모드로 실행(스크립트 디렉터리에 격리 설치) |
| `--help` | `-Help` | `--help` | 도움말 표시 |
| `/nopause` | - | - | 호환 인수(더 이상 일시 정지하지 않음) |

```bash
# Windows
start.cmd --port 8080
# macOS / Linux
bash start.sh --port 8080
```

### 2. 도구 체인 설치 — `setup.cmd` / `setup.ps1` / `setup.sh`

**한 가지만 합니다**: `nvm → node → (npm 타오바오 미러 + nrm) → dsh`를 단계별로 감지/설치하고, 각 단계가 준비되면 건너뛰며 절대 중복 설치하지 않습니다.

1. **nvm**: 감지/사용만(셸 함수 / nvm-windows), **절대 설치하지 않음**.
2. **node**: 주 버전이 ≥22인지 확인. 부족하면 먼저 nvm으로 Node 22를 설치. nvm을 쓸 수 없거나 실패하면 `nodejs.org` 공식 빌드를 지정 디렉터리(기본은 스크립트 디렉터리 아래 `nodejs/`)로 다운로드.
3. **npm 타오바오 미러 + nrm**: npm 레지스트리를 `https://registry.npmmirror.com`으로 설정(이미 설정됐으면 건너뜀), `nrm`을 전역 설치(실패는 경고일 뿐 중단하지 않음).
4. **dsh**: 없으면 `npm install -g @deepseek-ai/dsh`(이 시점에는 타오바오 미러 사용).

| 인수(sh) | 인수(ps1) | 인수(cmd) | 설명 |
| --- | --- | --- | --- |
| `--dir <경로>` | `-Dir <경로>` | `--dir <경로>` | Node 설치 디렉터리(기본: 스크립트 디렉터리 아래 `nodejs/`) |
| `--no-env` | `-NoEnv` | `--no-env` | PATH 환경 변수 변경 안 함 |
| `--dry-run` | `-DryRun` | `--dry-run` | 감지만, 다운로드/설치 안 함 |
| `--debug` | `-Debug` | `--debug` | 디버그 모드(아래 참조) |
| `--help` | `-Help` | `--help` | 도움말 표시 |
| - | - | `/nopause` | 호환 인수(더 이상 일시 정지하지 않음) |

```bash
bash setup.sh --dry-run        # 현재 환경만 감지
bash setup.sh --dir /opt/node  # 설치 디렉터리 지정
bash setup.sh --debug          # 격리 검증 설치
```

### 3. 서비스 관리 — `server/` 디렉터리

`dsh web`을 **부팅 시 자동 시작**되는 시스템 서비스로 설치합니다. 플랫폼마다 메인 스크립트 `server-service.<ext>` 하나와 `install` / `start` / `stop` / `uninstall` 네 개의 편리한 래퍼가 있습니다.

| 플랫폼 | 서비스 메커니즘 | 스크립트 |
| --- | --- | --- |
| Windows | 예약 작업 `dsh-web`(`schtasks /sc onstart`, SYSTEM 사용자, 부팅 시 자동 시작) | `server-service.cmd` / `server-service.ps1` |
| Linux | systemd `dsh-web.service` | `server-service.sh` |
| macOS | launchd `com.deepseek-harness.dsh-web.plist` | `server-service.sh` |

통일된 사용법(`server-service.<ext>`):

| 명령 | 설명 |
| --- | --- |
| `install` | 서비스 등록 및 시작 |
| `uninstall` | 서비스 제거 |
| `start` / `stop` | 서비스 시작 / 중지 |
| `status` | 서비스 상태 표시 |

서비스는 SYSTEM / root 계정으로 실행되며 `homedir()`가 데스크톱 사용자와 달라 수동 시작으로 만들어진 세션을 볼 수 없습니다. 따라서 등록 명령은 서비스에 `DSH_HOME=<사용자 home>\.dsh`(dsh가 공식 지원하는 최우선 데이터 루트 오버라이드)를 명시적으로 설정하여, 서비스와 수동 시작이 **동일한 세션 데이터를 공유**하도록 합니다.

래퍼는 인수를 그대로 전달합니다:

| 인수 | 설명 |
| --- | --- |
| `--port <포트>` | 포트(기본 3080) |
| `--host <호스트>` | 바인딩 주소(기본 127.0.0.1) |
| `--debug` | 스크립트 디렉터리 아래 nodejs/dsh 사용 |

예:

```bat
server\install-server-service.cmd --port 8080
bash server/install-server-service.sh
```

> Windows의 `install` / `uninstall`은 관리자 권한, Linux / macOS는 root / sudo가 필요합니다.

**dsh 업데이트** — `update-dsh.<ext>`: `@deepseek-ai/dsh`를 최신 버전으로 업데이트하고, 서비스가 설치되어 있으면 재시작하여 적용합니다:

```bat
server\update-dsh.cmd            # dsh 업데이트 및 서비스 재시작
server\update-dsh.cmd --dry-run  # 현재/최신 버전만 표시, 업데이트 안 함
server\update-dsh.cmd --debug    # 스크립트 디렉터리 node 아래 dsh 업데이트
```

```bash
bash server/update-dsh.sh         # macOS / Linux, 동일한 인수
```

## 포트 해석

런처는 `dsh web` 포트를 다음 우선순위로 해석합니다:

1. `--port` / `-Port` 명령줄 인수
2. 서비스 설정에 등록된 `--port`
3. 환경 변수 `DSH_PORT`
4. 기본 `3080`

## 디버그 모드(`--debug` / `-Debug`)

사용자의 기존 nvm/node 환경의 영향을 받지 않는 **격리 검증**용 설치입니다:

1. **현재 세션** PATH에서 `nvm` / `node`를 포함한 항목만 제거합니다. 시스템 환경 변수는 건드리지 않습니다.
2. 설치 디렉터리를 스크립트 디렉터리 아래 `nodejs/`로 강제합니다(이미 gitignore).
3. **nvm을 건너뛰고** 공식 다운로드를 강제합니다.
4. 이후 nrm/dsh는 일반 모드와 동일한 로직(`npm install -g`): PATH가 이미 스크립트 디렉터리 node를 가리키며 그 전역 접두사는 자연히 격리됩니다. 또한 세션 단위 `npm_config_registry` / `npm_config_prefix`로 npm 레지스트리와 전역 디렉터리를 격리하고, 사용자 `~/.npmrc`는 **쓰지 않습니다**.
5. 현재 세션 PATH만 업데이트하고 사용자의 영구 PATH는 **쓰지 않습니다**.

### 현재 세션 활성화(debug 환경 유지)

`setup.cmd` / `setup.sh` / `setup.ps1`을 직접 실행하면 스크립트의 환경 변경은 자체 프로세스 내에서만 유효합니다(스크립트 종료 시 복원). **현재 터미널 세션**도 디버그 환경(`node`가 스크립트 디렉터리 `nodejs/`를 가리키고 npm은 타오바오 미러)으로 전환하려면 활성화 방식 호출을 사용하세요:

| shell | 활성화 명령 | 설명 |
| --- | --- | --- |
| cmd | `call setup.cmd --debug` | `call`은 같은 cmd 인스턴스에서 실행, 환경 유지 |
| git-bash / bash | `source setup.sh --debug` | `source`는 현재 셸에서 실행, 환경 유지 |
| PowerShell | `.\setup.ps1 -Debug` | `$env:` 변경은 자연히 유지, 그냥 실행하면 됨 |

활성화 후 현재 세션은 디버그 환경으로 전환됩니다(`node -v`가 스크립트 디렉터리 버전을 표시). 사용자의 영구 PATH는 쓰지 않으며 새 터미널에는 영향을 주지 않습니다.

## 다국어(i18n)

프롬프트/로그는 시스템 언어에 따라 `locales/<lang>.lang`을 자동 로드합니다. **8개 언어**: `zh`, `zh-TW`, `en`, `ja`, `ko`, `fr`, `de`, `es`. 감지할 수 없거나 알 수 없는 언어면 기본 중국어.

환경 변수 `SETUP_LANG`으로 언어를 강제할 수 있습니다(최우선). 예: `SETUP_LANG=en start.cmd`.

## 버전 관리

Node.js 22 LTS 최신 버전 번호는 스크립트 상단에 집중 관리되며, 업그레이드는 한 곳만 변경하면 됩니다:

- `setup.sh`: `VERSION="v22.23.2"`
- `setup.ps1`: `$Script:Version = "22.23.2"` + `$Script:VVersion = "v22.23.2"`
- `setup.cmd`: `VERSION=v22.23.2` + `NVM_VERSION=22.23.2`

## License

MIT
