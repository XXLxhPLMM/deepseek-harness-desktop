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
  <img src="../img/use.png" alt="harness-start Screenshot" />
</p>

Ein auf **webview** basierender **DeepSeek-Harness-Desktop-Launcher**, plattformübergreifend (Windows / macOS / Linux).

Doppelklick oder ein einzelner Befehl:

- **Automatisch bereite Toolchain**: erkennt/installiert `node → npm-Taobao-Mirror + nrm → dsh` Stufe für Stufe und verweigert redundante Installationen;
- **Autostart-Dienst**: registriert `dsh web` als Systemdienst, der beim Booten automatisch läuft;
- **Desktop-Fenster**: öffnet DeepSeek Harness im systemeigenen Edge / Chrome im **App-Modus** (ein eigenständiges Fenster ohne Adress- und Lesezeichenleiste, ähnlich einer Desktop-Anwendung).

## Funktionsweise

```
start-Launcher
   │ ① setup ausführen (fehlende Toolchain automatisch ergänzen)
   │ ② Port auflösen: --port-Argument > Dienstkonfiguration > DSH_PORT > Standard 3080
   │ ③ prüfen, ob der dsh-Dienst läuft; andernfalls automatisch starten
   ▼
webview (Edge / Chrome --app) ──►  http://localhost:<port>
```

Intern läuft der Dienst als `node <dsh cli> web --port 3080 --host 127.0.0.1` und lauscht nur auf der lokalen Loopback-Adresse.

## Schnellstart

### Windows (empfohlen)

Doppelklicken Sie `start.cmd` oder in der Befehlszeile:

```bat
start.cmd
```

Oder verwenden Sie die PowerShell-Version:

```powershell
powershell -ExecutionPolicy Bypass -File start.ps1
```

### macOS / Linux

```bash
bash start.sh
```

Der erste Lauf ergänzt automatisch die fehlende Toolchain (Netzwerk erforderlich); danach öffnet er sich sofort.

> **Vor dem ersten Start muss der dsh-Dienst installiert werden** (einmalig; er startet automatisch beim Boot):
>
> ```bat
> rem Windows (Administratorrechte)
> server\install-server-service.cmd
> ```
>
> ```bash
> # macOS / Linux (sudo)
> sudo bash server/install-server-service.sh
> ```
>
> Oder mit PowerShell: `powershell -ExecutionPolicy Bypass -File server\install-server-service.ps1`.
>
> Wenn der Dienst noch nicht installiert ist, können `start.cmd` / `start.ps1` / `start.sh` ihn nur erkennen/zu starten versuchen und warnen, dass er nicht installiert ist; führen Sie zuerst den obigen install-Befehl aus.

## Skriptübersicht

Das Projekt besteht aus drei Skriptgruppen; die Logik ist auf allen Plattformen gleich.

### 1. Launcher (Einstieg) — `start.cmd` / `start.ps1` / `start.sh`

Für den täglichen Gebrauch nutzen Sie nur dieses. Es macht automatisch: Toolchain erkennen (**überspringt setup, wenn dsh bereits bereit ist**) → dsh-Dienst erkennen/starten → das Desktop-Fenster per webview öffnen.

| Argument (cmd) | Argument (ps1) | Argument (sh) | Beschreibung |
| --- | --- | --- | --- |
| `--port <Port>` | `-Port <Port>` | `--port <Port>` | Dienstport (Standard 3080) |
| `--debug` | `-Debug` | `--debug` | setup im Debug-Modus ausführen (isolierte Installation in das Skriptverzeichnis) |
| `--help` | `-Help` | `--help` | Hilfe anzeigen |
| `/nopause` | - | - | Kompatibilitätsargument (kein Pausieren mehr) |

```bash
# Windows
start.cmd --port 8080
# macOS / Linux
bash start.sh --port 8080
```

### 2. Toolchain-Installation — `setup.cmd` / `setup.ps1` / `setup.sh`

**Tut nur eines**: erkennt/installiert `nvm → node → (npm-Taobao-Mirror + nrm) → dsh` Stufe für Stufe, überspringt jede bereits bereite Stufe und installiert nie erneut.

1. **nvm**: nur erkennen/verwenden (Shell-Funktion / nvm-windows), **nie installieren**;
2. **node**: prüft, ob die Hauptversion ≥22 ist; wenn nicht, bevorzugt Node 22 über nvm installieren; wenn nvm nicht verfügbar ist oder fehlschlägt, den offiziellen Build von `nodejs.org` in das Zielverzeichnis (Standard `nodejs/` unter dem Skriptverzeichnis) herunterladen;
3. **npm-Taobao-Mirror + nrm**: setzt die npm-Registry auf `https://registry.npmmirror.com` (überspringt, falls bereits gesetzt) und installiert `nrm` global (ein Fehler ist nur eine Warnung, nicht fatal);
4. **dsh**: falls fehlt, `npm install -g @deepseek-ai/dsh` (zu diesem Zeitpunkt wird bereits der Taobao-Mirror verwendet).

| Argument (sh) | Argument (ps1) | Argument (cmd) | Beschreibung |
| --- | --- | --- | --- |
| `--dir <Pfad>` | `-Dir <Pfad>` | `--dir <Pfad>` | Node-Installationsverzeichnis (Standard: `nodejs/` unter dem Skriptverzeichnis) |
| `--no-env` | `-NoEnv` | `--no-env` | Die PATH-Umgebungsvariable nicht ändern |
| `--dry-run` | `-DryRun` | `--dry-run` | Nur erkennen, nicht herunterladen/installieren |
| `--debug` | `-Debug` | `--debug` | Debug-Modus (siehe unten) |
| `--help` | `-Help` | `--help` | Hilfe anzeigen |
| - | - | `/nopause` | Kompatibilitätsargument (kein Pausieren mehr) |

```bash
bash setup.sh --dry-run        # nur die aktuelle Umgebung erkennen
bash setup.sh --dir /opt/node  # Installationsverzeichnis angeben
bash setup.sh --debug          # isolierte Verifikationsinstallation
```

### 3. Dienstverwaltung — Verzeichnis `server/`

Installiert `dsh web` als Systemdienst mit **Autostart beim Boot**. Ein Hauptskript `server-service.<ext>` pro Plattform, dazu vier praktische Wrapper: `install` / `start` / `stop` / `uninstall`.

| Plattform | Dienstmechanismus | Skript |
| --- | --- | --- |
| Windows | Geplante Aufgabe `dsh-web` (`schtasks /sc onstart`, SYSTEM-Benutzer, Autostart beim Boot) | `server-service.cmd` / `server-service.ps1` |
| Linux | systemd `dsh-web.service` | `server-service.sh` |
| macOS | launchd `com.deepseek-harness.dsh-web.plist` | `server-service.sh` |

Einheitliche Verwendung (`server-service.<ext>`):

| Befehl | Beschreibung |
| --- | --- |
| `install` | Dienst registrieren und starten |
| `uninstall` | Dienst deinstallieren |
| `start` / `stop` | Dienst starten / stoppen |
| `status` | Dienststatus anzeigen |

Der Dienst läuft unter dem SYSTEM-/root-Konto; sein `homedir()` unterscheidet sich vom Desktop-Benutzer, sodass er von manuellen Starts erzeugte Sitzungen nicht sehen kann. Deshalb setzt der Registrierungsbefehl explizit `DSH_HOME=<Benutzer-home>\.dsh` (die von dsh offiziell unterstützte Daten-Root-Überschreibung höchster Priorität), sodass Dienst und manuelle Starts **dieselben Sitzungsdaten teilen**.

Die Wrapper reichen Argumente direkt durch:

| Argument | Beschreibung |
| --- | --- |
| `--port <Port>` | Port (Standard 3080) |
| `--host <Host>` | Bindungsadresse (Standard 127.0.0.1) |
| `--debug` | nodejs/dsh unter dem Skriptverzeichnis verwenden |

Zum Beispiel:

```bat
server\install-server-service.cmd --port 8080
bash server/install-server-service.sh
```

> `install` / `uninstall` unter Windows erfordert Administratorrechte; Linux / macOS erfordern root / sudo.

**dsh aktualisieren** — `update-dsh.<ext>`: aktualisiert `@deepseek-ai/dsh` auf die neueste Version und startet den Dienst neu, falls er installiert ist, um die Änderung anzuwenden:

```bat
server\update-dsh.cmd            # dsh aktualisieren und Dienst neu starten
server\update-dsh.cmd --dry-run  # nur aktuelle/letzte Version anzeigen, nicht aktualisieren
server\update-dsh.cmd --debug    # dsh unter dem node des Skriptverzeichnisses aktualisieren
```

```bash
bash server/update-dsh.sh         # macOS / Linux, gleiche Argumente
```

## Port-Auflösung

Der Launcher löst den `dsh web`-Port in folgender Prioritätsreihenfolge auf:

1. das Befehlszeilenargument `--port` / `-Port`
2. das in der Dienstkonfiguration registrierte `--port`
3. die Umgebungsvariable `DSH_PORT`
4. Standard `3080`

## Debug-Modus (`--debug` / `-Debug`)

Dient der **isolierten Verifikation** der Installation, unbeeinflusst von der vorhandenen nvm/node-Umgebung des Benutzers:

1. entfernt nur die Einträge mit `nvm` / `node` aus dem PATH der **aktuellen Sitzung**, nicht aus Systemumgebungsvariablen;
2. erzwingt das Installationsverzeichnis `nodejs/` unter dem Skriptverzeichnis (bereits gitignored);
3. **überspringt nvm**, erzwingt offiziellen Download;
4. nachfolgende nrm/dsh folgen derselben Logik wie der Normalmodus (`npm install -g`): der PATH zeigt bereits auf das node des Skriptverzeichnisses, dessen globales Präfix natürlich isoliert ist; verwendet sitzungsbezogenes `npm_config_registry` / `npm_config_prefix`, um Registry und globales Verzeichnis zu isolieren, **ohne das `~/.npmrc` des Benutzers zu schreiben**;
5. aktualisiert nur den PATH der aktuellen Sitzung, **schreibt nicht** den persistenten PATH des Benutzers.

### Aktivieren der aktuellen Sitzung (Debug-Umgebung beibehalten)

Beim direkten Ausführen von `setup.cmd` / `setup.sh` / `setup.ps1` gelten die Umgebungsänderungen des Skripts nur in dessen eigenem Prozess (bei Ende wiederhergestellt). Um auch die **aktuelle Terminal-Sitzung** in die Debug-Umgebung zu wechseln (`node` zeigt auf `nodejs/` des Skriptverzeichnisses, npm über den Taobao-Mirror), verwenden Sie einen aktivierenden Aufruf:

| Shell | Aktivierungsbefehl | Beschreibung |
| --- | --- | --- |
| cmd | `call setup.cmd --debug` | `call` läuft in derselben cmd-Instanz, Umgebung bleibt erhalten |
| git-bash / bash | `source setup.sh --debug` | `source` läuft in der aktuellen Shell, Umgebung bleibt erhalten |
| PowerShell | `.\setup.ps1 -Debug` | `$env:`-Änderungen bleiben natürlich erhalten; einfach ausführen |

Nach der Aktivierung wechselt die aktuelle Sitzung in die Debug-Umgebung (`node -v` zeigt die Version des Skriptverzeichnisses), ohne den persistenten PATH des Benutzers zu schreiben; neue Terminals sind nicht betroffen.

## i18n

Eingabeaufforderungen/Logs laden automatisch `locales/<lang>.lang` je nach Systemsprache — **8 Sprachen**: `zh`, `zh-TW`, `en`, `ja`, `ko`, `fr`, `de`, `es`; Standard ist Chinesisch, wenn nicht erkannt oder unbekannt.

Verwenden Sie die Umgebungsvariable `SETUP_LANG`, um eine Sprache zu erzwingen (höchste Priorität), z. B. `SETUP_LANG=en start.cmd`.

## Versionswartung

Die neueste Node.js-22-LTS-Version wird zentral oben in den Skripten gepflegt; ein Upgrade erfordert nur eine Änderung:

- `setup.sh`: `VERSION="v22.23.2"`
- `setup.ps1`: `$Script:Version = "22.23.2"` + `$Script:VVersion = "v22.23.2"`
- `setup.cmd`: `VERSION=v22.23.2` + `NVM_VERSION=22.23.2`

## License

MIT
