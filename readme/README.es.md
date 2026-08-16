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
  <img src="../img/use.png" alt="captura de pantalla de harness-start" />
</p>

# harness-start

Un **lanzador de escritorio para DeepSeek Harness** basado en **webview**, multiplataforma (Windows / macOS / Linux).

Doble clic o un solo comando:

- **Cadena de herramientas lista automáticamente**: detecta/instala `node → espejo npm taobao + nrm → dsh` nivel por nivel, sin instalaciones redundantes;
- **Servicio de autoarranque**: registra `dsh web` como servicio del sistema que se ejecuta automáticamente al arrancar;
- **Ventana de escritorio**: abre DeepSeek Harness en el Edge / Chrome del sistema en **modo app** (una ventana independiente sin barra de direcciones ni de marcadores, similar a una aplicación de escritorio).

## Cómo funciona

```
lanzador start
   │ ① ejecuta setup (completa la cadena de herramientas que falta)
   │ ② resuelve el puerto: argumento --port > configuración del servicio > DSH_PORT > predeterminado 3080
   │ ③ comprueba si el servicio dsh está en ejecución; si no, lo inicia
   ▼
webview (Edge / Chrome --app) ──►  http://localhost:<port>
```

Internamente, el servicio se ejecuta como `node <dsh cli> web --port 3080 --host 127.0.0.1`, escuchando solo en la dirección de bucle local.

## Inicio rápido

### Windows (recomendado)

Haga doble clic en `start.cmd` o en la línea de comandos:

```bat
start.cmd
```

También puede usar la versión de PowerShell:

```powershell
powershell -ExecutionPolicy Bypass -File start.ps1
```

### macOS / Linux

```bash
bash start.sh
```

La primera ejecución completa automáticamente la cadena de herramientas que falta (requiere red); las siguientes se abren al instante.

> **Antes del primer inicio, debe instalar el servicio dsh** (solo una vez; se autoarranca al arrancar):
>
> ```bat
> rem Windows (privilegios de administrador)
> server\install-server-service.cmd
> ```
>
> ```bash
> # macOS / Linux (sudo)
> sudo bash server/install-server-service.sh
> ```
>
> O con PowerShell: `powershell -ExecutionPolicy Bypass -File server\install-server-service.ps1`.
>
> Si el servicio aún no está instalado, `start.cmd` / `start.ps1` / `start.sh` solo pueden detectarlo/intentar iniciarlo y avisarán de que no está instalado; ejecute primero el install anterior.

## Resumen de scripts

El proyecto tiene tres grupos de scripts; la lógica es la misma en todas las plataformas.

### 1. Lanzador (entrada) — `start.cmd` / `start.ps1` / `start.sh`

Para uso diario, use solo este. Hace automáticamente: detectar la cadena de herramientas (**omite setup si dsh ya está listo**) → detectar/iniciar el servicio dsh → abrir la ventana de escritorio mediante webview.

| argumento (cmd) | argumento (ps1) | argumento (sh) | Descripción |
| --- | --- | --- | --- |
| `--port <puerto>` | `-Port <puerto>` | `--port <puerto>` | Puerto del servicio (predeterminado 3080) |
| `--debug` | `-Debug` | `--debug` | Ejecuta setup en modo depuración (instalación aislada en el directorio del script) |
| `--help` | `-Help` | `--help` | Muestra la ayuda |
| `/nopause` | - | - | Argumento de compatibilidad (ya no pausa) |

```bash
# Windows
start.cmd --port 8080
# macOS / Linux
bash start.sh --port 8080
```

### 2. Instalación de la cadena de herramientas — `setup.cmd` / `setup.ps1` / `setup.sh`

**Hace solo una cosa**: detecta/instala `nvm → node → (espejo npm taobao + nrm) → dsh` nivel por nivel, omitiendo cualquier nivel ya listo, sin reinstalar nunca.

1. **nvm**: solo detectar/usar (función de shell / nvm-windows), **nunca instalar**;
2. **node**: comprueba que la versión principal sea ≥22; si no, instala preferentemente Node 22 mediante nvm; si nvm no está disponible o falla, descarga el build oficial de `nodejs.org` en el directorio de destino (predeterminado `nodejs/` bajo el directorio del script);
3. **espejo npm taobao + nrm**: establece el registro npm en `https://registry.npmmirror.com` (omite si ya está establecido) e instala `nrm` globalmente (un error es solo una advertencia, no fatal);
4. **dsh**: si falta, `npm install -g @deepseek-ai/dsh` (en ese momento ya usa el espejo taobao).

| argumento (sh) | argumento (ps1) | argumento (cmd) | Descripción |
| --- | --- | --- | --- |
| `--dir <ruta>` | `-Dir <ruta>` | `--dir <ruta>` | Directorio de instalación de node (predeterminado: `nodejs/` bajo el directorio del script) |
| `--no-env` | `-NoEnv` | `--no-env` | No modifica la variable de entorno PATH |
| `--dry-run` | `-DryRun` | `--dry-run` | Solo detecta, no descarga/instala |
| `--debug` | `-Debug` | `--debug` | Modo depuración (ver más abajo) |
| `--help` | `-Help` | `--help` | Muestra la ayuda |
| - | - | `/nopause` | Argumento de compatibilidad (ya no pausa) |

```bash
bash setup.sh --dry-run        # solo detecta el entorno actual
bash setup.sh --dir /opt/node  # especifica el directorio de instalación
bash setup.sh --debug          # instalación de verificación aislada
```

### 3. Gestión del servicio — directorio `server/`

Instala `dsh web` como servicio del sistema con **autoarranque al iniciar**. Un script principal `server-service.<ext>` por plataforma, más cuatro envoltorios prácticos: `install` / `start` / `stop` / `uninstall`.

| Plataforma | Mecanismo de servicio | Script |
| --- | --- | --- |
| Windows | Tarea programada `dsh-web` (`schtasks /sc onstart`, usuario SYSTEM, autoarranque al iniciar) | `server-service.cmd` / `server-service.ps1` |
| Linux | systemd `dsh-web.service` | `server-service.sh` |
| macOS | launchd `com.deepseek-harness.dsh-web.plist` | `server-service.sh` |

Uso unificado (`server-service.<ext>`):

| Comando | Descripción |
| --- | --- |
| `install` | Registra e inicia el servicio |
| `uninstall` | Desinstala el servicio |
| `start` / `stop` | Inicia / detiene el servicio |
| `status` | Muestra el estado del servicio |

El servicio se ejecuta bajo la cuenta SYSTEM / root; su `homedir()` difiere del usuario de escritorio, por lo que no puede ver las sesiones creadas por los inicios manuales. Por ello, el comando de registro establece explícitamente `DSH_HOME=<home del usuario>\.dsh` (la anulación de raíz de datos de máxima prioridad que admite dsh), de modo que el servicio y los inicios manuales **comparten los mismos datos de sesión**.

Los envoltorios pasan los argumentos directamente:

| argumento | Descripción |
| --- | --- |
| `--port <puerto>` | Puerto (predeterminado 3080) |
| `--host <host>` | Dirección de enlace (predeterminada 127.0.0.1) |
| `--debug` | Usa nodejs/dsh bajo el directorio del script |

Por ejemplo:

```bat
install-server-service.cmd --port 8080
bash install-server-service.sh
```

> `install` / `uninstall` en Windows requiere privilegios de administrador; Linux / macOS requieren root / sudo.

**Actualizar dsh** — `update-dsh.<ext>`: actualiza `@deepseek-ai/dsh` a la última versión y, si el servicio está instalado, lo reinicia para aplicar el cambio:

```bat
server\update-dsh.cmd            # actualiza dsh y reinicia el servicio
server\update-dsh.cmd --dry-run  # solo muestra la versión actual/última, no actualiza
server\update-dsh.cmd --debug    # actualiza dsh bajo el node del directorio del script
```

```bash
bash server/update-dsh.sh         # macOS / Linux, mismos argumentos
```

## Resolución del puerto

El lanzador resuelve el puerto de `dsh web` en el siguiente orden de prioridad:

1. el argumento de línea de comandos `--port` / `-Port`
2. el `--port` registrado en la configuración del servicio
3. la variable de entorno `DSH_PORT`
4. predeterminado `3080`

## Modo depuración (`--debug` / `-Debug`)

Sirve para la **verificación aislada** de la instalación, sin verse afectado por el entorno nvm/node existente del usuario:

1. elimina solo las entradas que contienen `nvm` / `node` del PATH de la **sesión actual**, no de las variables de entorno del sistema;
2. fuerza el directorio de instalación a `nodejs/` bajo el directorio del script (ya en gitignore);
3. **omite nvm**, fuerza la descarga oficial;
4. los nrm/dsh posteriores siguen la misma lógica que el modo normal (`npm install -g`): el PATH ya apunta al node del directorio del script, cuyo prefijo global está naturalmente aislado; usa `npm_config_registry` / `npm_config_prefix` a nivel de sesión para aislar el registro npm y el directorio global, **sin escribir el `~/.npmrc` del usuario**;
5. actualiza solo el PATH de la sesión actual, **no escribe** el PATH persistente del usuario.

### Activar la sesión actual (mantener el entorno debug)

Al ejecutar directamente `setup.cmd` / `setup.sh` / `setup.ps1`, los cambios de entorno del script solo se aplican dentro de su propio proceso (se restauran al final). Para cambiar también la **sesión de terminal actual** al entorno de depuración (`node` apuntando a `nodejs/` del directorio del script, npm a través del espejo taobao), use una llamada de activación:

| shell | comando de activación | Descripción |
| --- | --- | --- |
| cmd | `call setup.cmd --debug` | `call` se ejecuta en la misma instancia de cmd, el entorno se conserva |
| git-bash / bash | `source setup.sh --debug` | `source` se ejecuta en el shell actual, el entorno se conserva |
| PowerShell | `.\setup.ps1 -Debug` | los cambios `$env:` se conservan naturalmente; solo ejecútelo |

Tras la activación, la sesión actual cambia al entorno de depuración (`node -v` muestra la versión del directorio del script), sin escribir el PATH persistente del usuario; los nuevos terminales no se ven afectados.

## i18n

Las indicaciones/registros cargan automáticamente `locales/<lang>.lang` según el idioma del sistema — **8 idiomas**: `zh`, `zh-TW`, `en`, `ja`, `ko`, `fr`, `de`, `es`; por defecto en chino si no se detecta o es desconocido.

Use la variable de entorno `SETUP_LANG` para forzar un idioma (mayor prioridad), p. ej. `SETUP_LANG=en start.cmd`.

## Mantenimiento de versiones

La última versión de Node.js 22 LTS se mantiene centralmente en la parte superior de los scripts; una actualización solo requiere un cambio:

- `setup.sh`: `VERSION="v22.23.2"`
- `setup.ps1`: `$Script:Version = "22.23.2"` + `$Script:VVersion = "v22.23.2"`
- `setup.cmd`: `VERSION=v22.23.2` + `NVM_VERSION=22.23.2`

## License

MIT