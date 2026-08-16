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
  <img src="../img/use.png" alt="capture d'écran de harness-start" />
</p>

Un **lanceur de bureau pour DeepSeek Harness** basé sur **webview**, multiplateforme (Windows / macOS / Linux).

Double-cliquez ou une seule commande :

- **Chaîne d'outils prête automatiquement** : détecte/installe `node → miroir npm taobao + nrm → dsh` niveau par niveau, sans réinstaller inutilement ;
- **Service au démarrage** : enregistre `dsh web` comme service système qui s'exécute automatiquement au démarrage ;
- **Fenêtre de bureau** : ouvre DeepSeek Harness dans le Edge / Chrome du système en **mode app** (une fenêtre autonome sans barre d'adresse ni barre de favoris, semblable à une application de bureau).

## Fonctionnement

```
lanceur start
   │ ① exécute setup (complète la chaîne d'outils manquante)
   │ ② résout le port : argument --port > configuration du service > DSH_PORT > défaut 3080
   │ ③ vérifie si le service dsh tourne ; le démarre sinon
   ▼
webview (Edge / Chrome --app) ──►  http://localhost:<port>
```

En interne, le service s'exécute comme `node <dsh cli> web --port 3080 --host 127.0.0.1`, écoutant uniquement sur l'adresse de boucle locale.

## Démarrage rapide

### Windows (recommandé)

Double-cliquez sur `start.cmd`, ou en ligne de commande :

```bat
start.cmd
```

Vous pouvez aussi utiliser la version PowerShell :

```powershell
powershell -ExecutionPolicy Bypass -File start.ps1
```

### macOS / Linux

```bash
bash start.sh
```

La première exécution complète automatiquement la chaîne d'outils manquante (nécessite un réseau) ; les suivantes s'ouvrent instantanément.

> **Avant le premier lancement, installez d'abord le service dsh** (une seule fois ; il démarre automatiquement au démarrage) :
>
> ```bat
> rem Windows (privilèges administrateur)
> server\install-server-service.cmd
> ```
>
> ```bash
> # macOS / Linux (sudo)
> sudo bash server/install-server-service.sh
> ```
>
> Ou avec PowerShell : `powershell -ExecutionPolicy Bypass -File server\install-server-service.ps1`.
>
> Si le service n'est pas encore installé, `start.cmd` / `start.ps1` / `start.sh` ne peuvent que détecter/tenter de le démarrer et avertiront qu'il n'est pas installé ; exécutez d'abord l'install ci-dessus.

## Aperçu des scripts

Le projet comporte trois groupes de scripts ; la logique est identique sur toutes les plateformes.

### 1. Lanceur (entrée) — `start.cmd` / `start.ps1` / `start.sh`

Pour un usage quotidien, utilisez uniquement celui-ci. Il fait automatiquement : détecter la chaîne d'outils (**ignore setup si dsh est déjà prêt**) → détecter/démarrer le service dsh → ouvrir la fenêtre de bureau via webview.

| argument (cmd) | argument (ps1) | argument (sh) | Description |
| --- | --- | --- | --- |
| `--port <port>` | `-Port <port>` | `--port <port>` | Port du service (défaut 3080) |
| `--debug` | `-Debug` | `--debug` | Exécute setup en mode débogage (installation isolée dans le dossier du script) |
| `--help` | `-Help` | `--help` | Affiche l'aide |
| `/nopause` | - | - | Argument de compatibilité (plus aucune pause) |

```bash
# Windows
start.cmd --port 8080
# macOS / Linux
bash start.sh --port 8080
```

### 2. Installation de la chaîne d'outils — `setup.cmd` / `setup.ps1` / `setup.sh`

**Ne fait qu'une chose** : détecter/installer `nvm → node → (miroir npm taobao + nrm) → dsh` niveau par niveau, en sautant tout niveau déjà prêt, sans jamais réinstaller.

1. **nvm** : uniquement détecter/utiliser (fonction shell / nvm-windows), **jamais installer** ;
2. **node** : vérifie que la version majeure est ≥22 ; sinon installe de préférence Node 22 via nvm ; si nvm est indisponible ou échoue, télécharge la version officielle depuis `nodejs.org` dans le dossier cible (défaut `nodejs/` sous le dossier du script) ;
3. **miroir npm taobao + nrm** : définit le registre npm sur `https://registry.npmmirror.com` (ignore si déjà défini) et installe `nrm` globalement (un échec n'est qu'un avertissement, pas bloquant) ;
4. **dsh** : si absent, `npm install -g @deepseek-ai/dsh` (à ce stade, le miroir taobao est utilisé).

| argument (sh) | argument (ps1) | argument (cmd) | Description |
| --- | --- | --- | --- |
| `--dir <chemin>` | `-Dir <chemin>` | `--dir <chemin>` | Dossier d'installation de node (défaut : `nodejs/` sous le dossier du script) |
| `--no-env` | `-NoEnv` | `--no-env` | Ne modifie pas la variable d'environnement PATH |
| `--dry-run` | `-DryRun` | `--dry-run` | Détection seule, pas de téléchargement/installation |
| `--debug` | `-Debug` | `--debug` | Mode débogage (voir ci-dessous) |
| `--help` | `-Help` | `--help` | Affiche l'aide |
| - | - | `/nopause` | Argument de compatibilité (plus aucune pause) |

```bash
bash setup.sh --dry-run        # détecte seulement l'environnement actuel
bash setup.sh --dir /opt/node  # spécifie le dossier d'installation
bash setup.sh --debug          # installation de vérification isolée
```

### 3. Gestion du service — dossier `server/`

Installe `dsh web` comme service système qui **démarre automatiquement au boot**. Un script principal `server-service.<ext>` par plateforme, plus quatre wrappers pratiques : `install` / `start` / `stop` / `uninstall`.

| Plateforme | Mécanisme de service | Script |
| --- | --- | --- |
| Windows | Tâche planifiée `dsh-web` (`schtasks /sc onstart`, utilisateur SYSTEM, auto-démarrage au boot) | `server-service.cmd` / `server-service.ps1` |
| Linux | systemd `dsh-web.service` | `server-service.sh` |
| macOS | launchd `com.deepseek-harness.dsh-web.plist` | `server-service.sh` |

Utilisation unifiée (`server-service.<ext>`) :

| Commande | Description |
| --- | --- |
| `install` | Enregistre et démarre le service |
| `uninstall` | Désinstalle le service |
| `start` / `stop` | Démarre / arrête le service |
| `status` | Affiche l'état du service |

Le service s'exécute sous le compte SYSTEM / root ; son `homedir()` diffère de celui de l'utilisateur de bureau, il ne peut donc pas voir les sessions créées par les lancements manuels. C'est pourquoi la commande d'enregistrement définit explicitement `DSH_HOME=<home de l'utilisateur>\.dsh` (le remplacement de racine de données de priorité maximale pris en charge par dsh), afin que le service et les lancements manuels **partagent les mêmes données de session**.

Les wrappers transmettent les arguments directement :

| argument | Description |
| --- | --- |
| `--port <port>` | Port (défaut 3080) |
| `--host <hôte>` | Adresse de liaison (défaut 127.0.0.1) |
| `--debug` | Utilise nodejs/dsh sous le dossier du script |

Par exemple :

```bat
install-server-service.cmd --port 8080
bash install-server-service.sh
```

> `install` / `uninstall` sous Windows nécessite des privilèges administrateur ; Linux / macOS nécessitent root / sudo.

**Mise à jour de dsh** — `update-dsh.<ext>` : met à jour `@deepseek-ai/dsh` vers la dernière version et, si le service est installé, le redémarre pour appliquer le changement :

```bat
server\update-dsh.cmd            # met à jour dsh et redémarre le service
server\update-dsh.cmd --dry-run  # affiche seulement la version courante/dernière, pas de mise à jour
server\update-dsh.cmd --debug    # met à jour dsh sous le node du dossier du script
```

```bash
bash server/update-dsh.sh         # macOS / Linux, mêmes arguments
```

## Résolution du port

Le lanceur résout le port de `dsh web` dans l'ordre de priorité suivant :

1. l'argument de ligne de commande `--port` / `-Port`
2. le `--port` enregistré dans la configuration du service
3. la variable d'environnement `DSH_PORT`
4. défaut `3080`

## Mode débogage (`--debug` / `-Debug`)

Sert à une **vérification isolée** de l'installation, sans être affecté par l'environnement nvm/node existant de l'utilisateur :

1. supprime uniquement les entrées contenant `nvm` / `node` du PATH de la **session actuelle**, sans toucher aux variables d'environnement système ;
2. force le dossier d'installation à `nodejs/` sous le dossier du script (déjà gitignoré) ;
3. **ignore nvm**, force le téléchargement officiel ;
4. les nrm/dsh suivants suivent la même logique que le mode normal (`npm install -g`) : le PATH pointe déjà vers le node du dossier du script, dont le préfixe global est naturellement isolé ; utilise `npm_config_registry` / `npm_config_prefix` au niveau de la session pour isoler le registre npm et le dossier global, **sans écrire le `~/.npmrc` de l'utilisateur** ;
5. met à jour uniquement le PATH de la session actuelle, **n'écrit pas** le PATH persistant de l'utilisateur.

### Activation de la session actuelle (maintien de l'environnement debug)

En exécutant directement `setup.cmd` / `setup.sh` / `setup.ps1`, les modifications d'environnement du script ne s'appliquent qu'à son propre processus (restaurées à la fin). Pour basculer aussi la **session de terminal actuelle** dans l'environnement de débogage (`node` pointant vers `nodejs/` du dossier du script, npm via le miroir taobao), utilisez un appel d'activation :

| shell | commande d'activation | Description |
| --- | --- | --- |
| cmd | `call setup.cmd --debug` | `call` s'exécute dans la même instance cmd, l'environnement est conservé |
| git-bash / bash | `source setup.sh --debug` | `source` s'exécute dans le shell actuel, l'environnement est conservé |
| PowerShell | `.\setup.ps1 -Debug` | les changements `$env:` sont naturellement conservés ; exécutez simplement |

Après activation, la session actuelle bascule dans l'environnement de débogage (`node -v` affiche la version du dossier du script), sans écrire le PATH persistant de l'utilisateur ; les nouveaux terminaux ne sont pas affectés.

## i18n

Les invites/journaux chargent automatiquement `locales/<lang>.lang` selon la langue du système — **8 langues** : `zh`, `zh-TW`, `en`, `ja`, `ko`, `fr`, `de`, `es` ; par défaut en chinois si non détectée ou inconnue.

Utilisez la variable d'environnement `SETUP_LANG` pour forcer une langue (priorité la plus élevée), par ex. `SETUP_LANG=en start.cmd`.

## Maintenance des versions

La dernière version de Node.js 22 LTS est gérée centralement en haut des scripts ; une mise à niveau ne nécessite qu'un seul changement :

- `setup.sh` : `VERSION="v22.23.2"`
- `setup.ps1` : `$Script:Version = "22.23.2"` + `$Script:VVersion = "v22.23.2"`
- `setup.cmd` : `VERSION=v22.23.2` + `NVM_VERSION=22.23.2`

## License

MIT