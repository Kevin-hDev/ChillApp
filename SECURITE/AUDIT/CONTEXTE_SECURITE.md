# Contexte de Securite — ChillApp

## Rapport d'audit architectural (methodologie Trail of Bits — audit-context-building)

**Date :** 2026-02-12
**Cible :** ChillApp — application Flutter desktop (Windows/Linux/macOS)
**Portee :** Cartographie architecturale, analyse ultra-granulaire, surface d'attaque
**Regles :** Contexte factuel uniquement. Aucune identification de vulnerabilite, aucune correction, aucun POC, aucune severite.

---

# PHASE 1 — Initial Orientation

## 1.1 Cartographie des modules

### Module : `core/command_runner.dart`
- **Role :** Abstraction unique pour executer toutes les commandes systeme via `dart:io` `Process.run`. Point d'entree unique vers le shell OS.
- **Dependances :** `dart:async`, `dart:io`
- **Dependants :** `NetworkInfo`, `SshSetupNotifier`, `WolSetupNotifier`, `DashboardNotifier`, `ConnectionInfoNotifier`
- **Surface d'attaque :** Execution de commandes systeme, elevation de privileges, construction de chaines de commandes

### Module : `core/network_info.dart`
- **Role :** Recuperation des informations reseau (IP Ethernet, IP WiFi, MAC address, nom d'utilisateur) selon l'OS. Methodes statiques uniquement.
- **Dependances :** `dart:io`, `CommandRunner`
- **Dependants :** `SshSetupNotifier`, `WolSetupNotifier`, `ConnectionInfoNotifier`
- **Surface d'attaque :** Parsing de sorties de commandes, injection via noms d'interfaces, lecture de fichiers systeme

### Module : `core/os_detector.dart`
- **Role :** Detection de l'OS courant et de la distribution Linux via `/etc/os-release`.
- **Dependances :** `dart:io`
- **Dependants :** `SshSetupNotifier`, `WolSetupNotifier`, `DashboardNotifier`
- **Surface d'attaque :** Lecture et parsing de `/etc/os-release`, matching de distribution

### Module : `features/lock/lock_provider.dart`
- **Role :** Gestion du verrouillage par PIN (creation, verification, suppression). Stockage du hash et du salt dans SharedPreferences. Rate limiting apres 5 tentatives echouees.
- **Dependances :** `dart:convert`, `dart:math`, `package:crypto`, `package:shared_preferences`, `package:flutter_riverpod`
- **Dependants :** `ChillApp` (app.dart), `LockScreen`
- **Surface d'attaque :** Hashing cryptographique, generation de salt, stockage local, rate limiting, migration d'ancien format

### Module : `features/tailscale/tailscale_provider.dart`
- **Role :** Gestion du daemon Tailscale embarque (`chill-tailscale`). Communication bidirectionnelle JSON via stdin/stdout du processus fils. Polling status toutes les 10 secondes.
- **Dependances :** `dart:async`, `dart:convert`, `dart:io`, `package:flutter/foundation.dart`, `package:flutter_riverpod`
- **Dependants :** `DashboardNotifier` (via `ref.listen`), `TailscaleScreen`
- **Surface d'attaque :** Execution de processus externe, parsing JSON, ouverture d'URLs, gestion du cycle de vie du daemon

### Module : `features/ssh_setup/ssh_setup_provider.dart`
- **Role :** Configuration automatisee du serveur SSH selon l'OS. Windows : PowerShell (installation OpenSSH, service, firewall). Linux : pkexec + script bash (installation, systemctl, firewall). macOS : osascript + systemsetup.
- **Dependances :** `dart:io`, `CommandRunner`, `NetworkInfo`, `OsDetector`, `SetupStep`
- **Dependants :** `SshSetupScreen`
- **Surface d'attaque :** Execution de commandes admin, creation de fichiers temporaires, installation de paquets systeme, configuration firewall

### Module : `features/wol_setup/wol_setup_provider.dart`
- **Role :** Configuration automatisee du Wake-on-LAN. Windows : PowerShell (detection carte, Magic Packet, powercfg, registre). Linux : pkexec + script bash (installation ethtool, ethtool -s, service systemd).
- **Dependances :** `dart:io`, `CommandRunner`, `NetworkInfo`, `OsDetector`, `SetupStep`
- **Dependants :** `WolSetupScreen`
- **Surface d'attaque :** Execution de commandes admin, modification du registre Windows, creation de services systemd, creation de fichiers temporaires

### Module : `features/connection_info/connection_info_provider.dart`
- **Role :** Recuperation et affichage de toutes les informations de connexion reseau (IPs, MAC, nom d'utilisateur, nom d'adaptateur).
- **Dependances :** `dart:io`, `CommandRunner`, `NetworkInfo`
- **Dependants :** `ConnectionInfoScreen`
- **Surface d'attaque :** Lecture d'informations reseau (lecture seule)

### Module : `features/dashboard/dashboard_provider.dart`
- **Role :** Verification de l'etat de configuration de SSH et WoL. Ecoute reactive du provider Tailscale.
- **Dependances :** `CommandRunner`, `OsDetector`, `TailscaleProvider`
- **Dependants :** `DashboardScreen`
- **Surface d'attaque :** Verification passive de services (lecture seule)

### Module : `features/settings/settings_provider.dart`
- **Role :** Persistance du theme (sombre/clair) via SharedPreferences.
- **Dependances :** `package:shared_preferences`, `package:flutter_riverpod`
- **Dependants :** `ChillApp` (app.dart), `SettingsScreen`
- **Surface d'attaque :** Stockage local (cle booleenne uniquement)

### Module : `config/router.dart`
- **Role :** Definition des routes GoRouter. 6 routes statiques, pas de parametres dynamiques.
- **Dependances :** `package:go_router`, ecrans de chaque feature
- **Dependants :** `ChillApp` (app.dart)
- **Surface d'attaque :** Aucune route dynamique, pas de parametres d'URL

### Module : `app.dart`
- **Role :** Widget racine. Conditionne l'affichage : LockScreen si PIN actif et non deverrouille, sinon MaterialApp.router. Gere le theme.
- **Dependances :** `router`, `theme`, `lockProvider`, `settingsProvider`
- **Dependants :** `main.dart`
- **Surface d'attaque :** Gate de verrouillage UI

### Module : `main.dart`
- **Role :** Point d'entree. Initialise Flutter et lance l'app dans un ProviderScope Riverpod.
- **Dependances :** `package:flutter`, `package:flutter_riverpod`, `app.dart`
- **Surface d'attaque :** Aucune (initialisation minimale)

---

## 1.2 Acteurs du systeme

| Acteur | Description | Niveau de confiance |
|--------|-------------|---------------------|
| **Utilisateur local** | Personne physique devant l'ecran. Saisit le PIN, declenche les configurations. | Partiellement de confiance (peut saisir des entrees inattendues) |
| **OS hote** | Windows, Linux, macOS. Fournit les commandes systeme, les fichiers systeme, les services. | De confiance (environnement d'execution) |
| **Shell OS** | PowerShell (Windows), Bash (Linux), osascript (macOS). Execute les commandes. | De confiance (mais les sorties doivent etre parsees) |
| **Daemon chill-tailscale** | Processus Go externe lance par l'app. Communique via JSON stdin/stdout. | Partiellement de confiance (binaire externe, ses sorties sont parsees) |
| **Tailscale backend** | Service Tailscale distant. Fournit les URLs d'auth, le statut, la liste de peers. | Externe, non de confiance (donnees recues via le daemon) |
| **SharedPreferences** | Stockage local cle-valeur. Contient le hash du PIN, le salt, les preferences. | De confiance localement (mais accessible a tout processus avec les droits utilisateur) |
| **Systeme de fichiers** | `/etc/os-release`, `/sys/class/net/`, fichiers temporaires, services systemd. | De confiance (mais contenu variable) |
| **Reseau local** | Fournit les informations IP, MAC, etat des interfaces. | Observable (informations exposees) |

---

## 1.3 Variables d'etat

### SharedPreferences Keys
| Cle | Type | Module | Description |
|-----|------|--------|-------------|
| `pin_hash` | String | LockNotifier | Hash SHA-256 du PIN (format: `sha256(salt:pin)`) |
| `pin_salt` | String | LockNotifier | Salt aleatoire base64 (16 octets) |
| `pin_failed_attempts` | int | LockNotifier | Nombre de tentatives echouees consecutives |
| `pin_locked_until` | int | LockNotifier | Timestamp en ms de fin de verrouillage |
| `darkMode` | bool | ThemeModeNotifier | Preference de theme (true = sombre) |

### Riverpod State
| Provider | Type d'etat | Module |
|----------|-------------|--------|
| `lockProvider` | `LockState(isEnabled, isUnlocked, failedAttempts, lockedUntil)` | lock_provider.dart |
| `tailscaleProvider` | `TailscaleState(status, selfHostname, selfIp, peers, errorMessage, isLoggingIn)` | tailscale_provider.dart |
| `sshSetupProvider` | `SshSetupState(steps, isRunning, isComplete, ipEthernet, ipWifi, username, errorMessage)` | ssh_setup_provider.dart |
| `wolSetupProvider` | `WolSetupState(steps, isRunning, isComplete, macAddress, ipEthernet, ipWifi, adapterName, errorMessage)` | wol_setup_provider.dart |
| `connectionInfoProvider` | `ConnectionInfoState(ipEthernet, ipWifi, macAddress, username, adapterName, isLoading, error)` | connection_info_provider.dart |
| `dashboardProvider` | `DashboardState(sshConfigured, wolConfigured, tailscaleConnected)` | dashboard_provider.dart |
| `themeModeProvider` | `bool` | settings_provider.dart |

### Processus actifs
| Variable | Type | Module | Description |
|----------|------|--------|-------------|
| `_daemon` | `Process?` | TailscaleNotifier | Reference au processus chill-tailscale actif |
| `_pollTimer` | `Timer?` | TailscaleNotifier | Timer de polling status (10 secondes) |
| `_stdoutSub` | `StreamSubscription<String>?` | TailscaleNotifier | Abonnement au flux stdout du daemon |
| `_stderrSub` | `StreamSubscription<String>?` | TailscaleNotifier | Abonnement au flux stderr du daemon |

---

## 1.4 Limites de confiance

```
Utilisateur (PIN/UI)
    |
    v
[LIMITE 1] UI Flutter (Dart) --- Validation des entrees
    |
    v
Providers Riverpod (logique metier)
    |
    v
[LIMITE 2] CommandRunner.run() / runPowerShell() / runElevated()
    |                              --- Construction de commandes
    v
[LIMITE 3] Process.run / Process.start
    |                              --- Delegation au shell OS
    v
Shell OS (PowerShell / Bash / osascript)
    |
    v
[LIMITE 4] Services systeme (sshd, systemd, registre, firewall)
    |                              --- Elevation de privileges
    v
OS Kernel

---

Providers Riverpod
    |
    v
[LIMITE 5] Process.start(chill-tailscale)
    |                              --- Communication IPC JSON
    v
Daemon Go chill-tailscale
    |
    v
[LIMITE 6] Tailscale backend (reseau)
    |                              --- Communication reseau externe
    v
Internet / Tailscale Control Plane
```

**Traversees de limites identifiees :**
1. **UI -> Provider** : Saisie PIN, declenchement de `runAll()`, `login()`, `logout()`
2. **Provider -> CommandRunner** : Passage de strings dans `run()`, `runPowerShell()`, `runElevated()`
3. **CommandRunner -> Process.run** : Execution de commandes systeme avec les arguments fournis
4. **CommandRunner -> Processus eleve** : Elevation via `pkexec`, `Start-Process -Verb RunAs`, `osascript with administrator privileges`
5. **Provider -> Daemon** : Communication JSON via stdin/stdout avec `chill-tailscale`
6. **Daemon -> URL** : Ouverture d'URL recue du daemon dans le navigateur systeme

---

# PHASE 2 — Ultra-Granular Function Analysis

## 2.1 CommandRunner.run()

**Fichier :** `/home/huynh-kevin/projects/ChillApp/lib/core/command_runner.dart`, lignes 25-53

### Purpose
Methode statique qui execute une commande systeme via `Process.run` avec un timeout configurable (defaut 120s). C'est le point d'entree unique pour toute execution de commande dans l'application. Encapsule le resultat dans un `CommandResult` qui normalise exit code, stdout et stderr.

### Inputs & Assumptions
1. `executable` (String) — nom ou chemin du binaire. **Assumption :** l'executable existe dans le PATH ou au chemin specifie
2. `args` (List<String>) — arguments passes au binaire. **Assumption :** les arguments sont pre-formates par l'appelant et ne necessitent pas d'echappement supplementaire
3. `timeout` (Duration?, optionnel) — duree max. **Assumption :** 120 secondes est suffisant pour toute commande (installation de paquets comprise)
4. **Assumption :** `Process.run` isole les arguments (pas d'interpretation shell des metacaracteres)
5. **Assumption :** le stdout et stderr sont decodables en String (`.toString()` est appele)

### Outputs & Effects
1. Retourne un `CommandResult` avec `exitCode`, `stdout` (trimme), `stderr` (trimme)
2. En cas de `TimeoutException` : retourne exitCode -1, stderr "La commande a depasse le delai d'attente."
3. En cas de `ProcessException` : retourne exitCode -1, stderr contient le message de l'exception
4. **Effet secondaire :** un processus OS est cree puis attendu jusqu'a completion ou timeout
5. Le `success` getter est `exitCode == 0` (ligne 16)

### Block-by-Block Analysis

**Bloc 1 : `Process.run` + timeout (lignes 31-34)**
- **What :** Execute le binaire avec ses arguments et applique un timeout
- **Why here :** Point central d'execution — toute commande passe par la
- **Assumptions :** `Process.run` ne declenche pas de shell intermediaire sur Dart VM; les arguments sont passes comme liste separee
- **First Principles :** Pourquoi `Process.run` et pas `Process.start` ? Parce que `run` attend la completion et retourne le resultat complet. Pourquoi un timeout ? Pour eviter un blocage infini si un processus ne repond pas.

**Bloc 2 : Construction du CommandResult (lignes 35-39)**
- **What :** Encapsule stdout/stderr en string trimmees
- **Why here :** Normalisation immediate apres execution
- **Assumptions :** `result.stdout` et `result.stderr` sont toujours non-null (garanti par `Process.run`)

**Bloc 3 : Catch TimeoutException (lignes 40-45)**
- **What :** Capture le timeout et retourne un resultat d'erreur
- **Why here :** Gestion explicite du cas de timeout
- **Assumptions :** le processus est automatiquement tue par Dart apres le timeout. Unclear; need to inspect le comportement de `.timeout()` sur `Process.run` — le processus enfant pourrait continuer a tourner.

**Bloc 4 : Catch ProcessException (lignes 46-52)**
- **What :** Capture les erreurs de lancement du processus (binaire inexistant, permissions insuffisantes)
- **Why here :** Gestion des erreurs pre-execution
- **Assumptions :** `ProcessException` couvre tous les cas d'echec au lancement

### Cross-Function Dependencies
1. `runPowerShell()` (ligne 56-61) : appelle `run('powershell', ...)` — delegue entierement
2. `runElevated()` (ligne 64-97) : appelle `run()` avec des executables d'elevation (`powershell`, `pkexec`, `osascript`)
3. Tous les providers (`SshSetupNotifier`, `WolSetupNotifier`, `DashboardNotifier`, `ConnectionInfoNotifier`) appellent `run()` directement ou via `runPowerShell()`/`runElevated()`
4. `NetworkInfo` appelle `run()` pour chaque requete d'information reseau

---

## 2.2 CommandRunner.runElevated()

**Fichier :** `/home/huynh-kevin/projects/ChillApp/lib/core/command_runner.dart`, lignes 64-97

### Purpose
Execute une commande avec elevation de privileges selon l'OS. Windows utilise `Start-Process -Verb RunAs`, Linux utilise `pkexec`, macOS utilise `osascript with administrator privileges`. C'est le mecanisme d'elevation unique de l'application.

### Inputs & Assumptions
1. `executable` (String) — le binaire a executer avec elevation
2. `args` (List<String>) — les arguments du binaire
3. **Assumption :** l'utilisateur va accepter la boite de dialogue d'elevation (UAC, pkexec, osascript)
4. **Assumption Windows :** l'echappement `a.replaceAll('"', '\\"')` est suffisant pour proteger les arguments dans le contexte PowerShell imbrique
5. **Assumption Linux :** pkexec passe les arguments comme liste separee (pas d'interpretation shell)
6. **Assumption macOS :** l'echappement de `\`, `"`, `$` est suffisant pour `do shell script`

### Outputs & Effects
1. Retourne un `CommandResult` (delegue a `run()`)
2. **Windows :** Lance un nouveau PowerShell en tant qu'administrateur. La commande est encapsulee dans : `Start-Process powershell -Verb RunAs -ArgumentList '-NoProfile -Command "$command"' -Wait`
3. **Linux :** Lance `pkexec executable args...` — affiche une boite de dialogue polkit
4. **macOS :** Lance `osascript -e 'do shell script "$command" with administrator privileges'` — affiche une boite de dialogue mot de passe

### Block-by-Block Analysis

**Bloc Windows (lignes 65-73)**
- **What :** Construit une commande PowerShell imbriquee avec elevation UAC
- **Why here :** Windows necessite `Start-Process -Verb RunAs` pour l'elevation
- **Assumptions :** L'echappement `replaceAll('"', '\\"')` sur chaque argument (ligne 67) est suffisant. La commande resultante est interpolee dans une chaine entre guillemets simples exterieurs et guillemets doubles interieurs.
- **Structure de la commande resultante :** `powershell -NoProfile -Command Start-Process powershell -Verb RunAs -ArgumentList '-NoProfile -Command "$executable \"$arg1\" \"$arg2\""' -Wait`
- **5 Whys :** Pourquoi `-Wait` ? Pour que `Process.run` ne retourne pas immediatement avant que la commande elevee soit terminee. Pourquoi `-NoProfile` ? Pour eviter l'execution de scripts de profil utilisateur potentiellement lents ou modifiants.

**Bloc Linux (lignes 74-77)**
- **What :** Passe l'executable et les args directement a `pkexec`
- **Why here :** `pkexec` accepte une liste d'arguments separee, pas besoin d'echappement
- **Assumptions :** `pkexec` est disponible (installe avec polkit). Les arguments ne sont pas reinterpretes par un shell.
- **Observation :** Contrairement a Windows et macOS, les arguments ne sont pas echappes ici car `run()` passe une `List<String>` a `Process.run`, et `pkexec` les recoit tels quels.

**Bloc macOS (lignes 78-95)**
- **What :** Construit une commande `osascript` avec echappement pour AppleScript
- **Why here :** macOS utilise `osascript` pour l'elevation
- **Assumptions :** L'echappement de `\`, `"`, `$` (lignes 80-88) est suffisant pour le contexte AppleScript `do shell script`. Les arguments sont concatenes en une seule chaine (pas de separation par liste).
- **Observation :** La commande resultante est : `osascript -e 'do shell script "$escapedExe $escapedArgs" with administrator privileges'`. Les arguments sont dans une seule chaine, donc interpretes par le shell par defaut de macOS (`/bin/sh`).

### Cross-Function Dependencies
1. `run()` — appelant final pour toutes les branches OS
2. `SshSetupNotifier._runLinux()` (ligne 263) : appelle `runElevated('bash', [tempScript.path])`
3. `SshSetupNotifier._runMac()` (lignes 316, 325) : appelle `runElevated('systemsetup', ['-setremotelogin', 'on'])`
4. `WolSetupNotifier._runLinux()` (ligne 338) : appelle `runElevated('bash', [tempScript.path])`

---

## 2.3 CommandRunner.runPowerShell()

**Fichier :** `/home/huynh-kevin/projects/ChillApp/lib/core/command_runner.dart`, lignes 56-61

### Purpose
Raccourci pour executer une commande PowerShell avec `-NoProfile -Command`. Utilise sur Windows uniquement en pratique.

### Inputs & Assumptions
1. `command` (String) — commande PowerShell complete, potentiellement multi-lignes
2. `timeout` (Duration?, optionnel)
3. **Assumption :** la commande `command` est une chaine de confiance construite dans le code source (hard-coded dans les providers)
4. **Assumption :** `-NoProfile` empeche l'execution de scripts de profil
5. **Assumption :** `-Command` interprete toute la chaine comme une commande PowerShell — les metacaracteres PowerShell sont actifs

### Outputs & Effects
1. Delegue entierement a `run('powershell', ['-NoProfile', '-Command', command])`
2. La chaine `command` est passee comme un seul argument a `-Command`

### Cross-Function Dependencies
1. `SshSetupNotifier._runWindows()` : 7 appels pour installer, demarrer, configurer SSH
2. `WolSetupNotifier._runWindows()` : 8+ appels pour configurer WoL
3. `DashboardNotifier._checkSsh()/_checkWol()` : verification d'etat
4. `ConnectionInfoNotifier.fetchAll()` : recuperation d'informations
5. `NetworkInfo.getEthernetIp()/getWifiIp()/getUsername()` : requetes d'info reseau

---

## 2.4 NetworkInfo.getEthernetIp()

**Fichier :** `/home/huynh-kevin/projects/ChillApp/lib/core/network_info.dart`, lignes 7-48

### Purpose
Recupere l'adresse IP de l'interface Ethernet active selon l'OS. Utilise des commandes systeme differentes par plateforme.

### Inputs & Assumptions
1. Aucun parametre
2. **Assumption :** il existe au maximum une interface Ethernet active pertinente
3. **Assumption Windows :** le filtrage par InterfaceDescription exclut correctement Wi-Fi, Wireless, Bluetooth, Virtual
4. **Assumption Linux :** `findEthernetAdapter()` retourne le bon nom d'interface
5. **Assumption macOS :** les interfaces Ethernet sont annotees "Ethernet" ou "Thunderbolt" dans la sortie de `networksetup -listallhardwareports`

### Outputs & Effects
1. Retourne `String?` — l'adresse IP ou null si non trouvee
2. **Windows :** Execute une commande PowerShell filtrant Get-NetAdapter puis Get-NetIPAddress
3. **Linux :** Appelle `findEthernetAdapter()` puis `ip -4 addr show $adapter` via bash avec grep
4. **macOS :** Parse la sortie de `networksetup -listallhardwareports` pour trouver le device, puis `ipconfig getifaddr`
5. Le stdout est retourne brut si non vide, null sinon

### Block-by-Block Analysis

**Bloc Linux (lignes 21-28)**
- **What :** Recupere l'IP via `ip addr show` et grep
- **Why here :** Linux necessite des outils specifiques (ip, grep)
- **Assumptions :** Le nom de l'adaptateur retourne par `findEthernetAdapter()` est insere directement dans la chaine de commande bash : `"ip -4 addr show $adapter 2>/dev/null | grep -oP '(?<=inet\\s)\\d+(\\.\\d+){3}' | head -1"`. **Le nom de l'adaptateur est interpole dans une commande bash sans echappement.**
- **Observation :** Le nom de l'adaptateur provient de `findEthernetAdapter()` qui lit les noms d'interfaces depuis `/sys/class/net/`. Sur un systeme standard, ces noms sont controles par udev/systemd-networkd et ne contiennent pas de caracteres speciaux shell. Mais la source de ces noms est le systeme d'exploitation.

**Bloc macOS (lignes 29-46)**
- **What :** Parse les lignes de `networksetup -listallhardwareports` pour trouver le device
- **Why here :** macOS utilise `networksetup` pour lister les interfaces
- **Assumptions :** La regex `Device:\s*(en\d+)` capture correctement le nom du device. Le `match.group(1)!` (avec `!`) suppose que le match a toujours un groupe capture.
- **Fallback :** si aucune interface Ethernet/Thunderbolt n'est trouvee, essaie `en1` (ligne 44)

### Cross-Function Dependencies
1. `findEthernetAdapter()` (Linux) — fournit le nom de l'interface
2. `CommandRunner.run()` — execute les commandes
3. `CommandRunner.runPowerShell()` — execute les commandes Windows
4. Appele par `SshSetupNotifier`, `WolSetupNotifier`, `ConnectionInfoNotifier`

---

## 2.5 NetworkInfo.getWifiIp()

**Fichier :** `/home/huynh-kevin/projects/ChillApp/lib/core/network_info.dart`, lignes 51-98

### Purpose
Recupere l'adresse IP de l'interface WiFi active selon l'OS. Structure similaire a `getEthernetIp()`.

### Inputs & Assumptions
1. Aucun parametre
2. **Assumption Linux :** le nom d'interface WiFi est determine en itérant `/sys/class/net/` et en verifiant l'existence de `/sys/class/net/$iface/wireless` et `carrier == 1`
3. **Assumption :** le script bash genere (lignes 64-71) ne necessite pas d'echappement car les noms d'interfaces viennent du noyau

### Outputs & Effects
1. Retourne `String?` — l'adresse IP WiFi ou null
2. **Linux :** Le nom d'interface WiFi est recupere via un script bash inline, puis `ip -4 addr show $wifiIface` (ligne 75). Le nom d'interface est interpole dans la commande sans echappement.

### Cross-Function Dependencies
Identiques a `getEthernetIp()`.

---

## 2.6 NetworkInfo.getMacAddress()

**Fichier :** `/home/huynh-kevin/projects/ChillApp/lib/core/network_info.dart`, lignes 112-116

### Purpose
Recupere l'adresse MAC d'une interface reseau en lisant `/sys/class/net/$adapter/address` (Linux uniquement).

### Inputs & Assumptions
1. `adapter` (String) — nom de l'interface reseau
2. **Assumption :** le nom de l'adaptateur est un nom d'interface valide
3. **Assumption :** le parametre `adapter` est passe tel quel a `CommandRunner.run('cat', ['/sys/class/net/$adapter/address'])`. L'interpolation se fait dans le chemin du fichier.
4. **Assumption :** `Process.run('cat', [path])` traite le chemin comme un seul argument (pas d'interpretation shell)

### Outputs & Effects
1. Retourne `String?` — l'adresse MAC ou null
2. Execute `cat /sys/class/net/<adapter>/address` via `Process.run`

---

## 2.7 LockNotifier.setPin()

**Fichier :** `/home/huynh-kevin/projects/ChillApp/lib/features/lock/lock_provider.dart`, lignes 76-82

### Purpose
Cree un nouveau PIN. Genere un salt cryptographique aleatoire, hash le PIN avec SHA-256, et stocke les deux dans SharedPreferences. Met a jour l'etat pour indiquer que le PIN est actif et l'app est deverrouillee.

### Inputs & Assumptions
1. `pin` (String) — le PIN saisi par l'utilisateur
2. **Assumption :** le PIN est valide (8 chiffres — cette validation est faite cote UI dans `LockScreen`, pas dans le provider)
3. **Assumption :** `SharedPreferences.getInstance()` est thread-safe et atomique
4. **Assumption :** les deux appels `setString` (salt et hash) s'executent sequentiellement et avec succes

### Outputs & Effects
1. Stocke `pin_salt` dans SharedPreferences (base64 de 16 octets aleatoires)
2. Stocke `pin_hash` dans SharedPreferences (SHA-256 de `salt:pin`)
3. Met a jour l'etat Riverpod : `isEnabled = true`, `isUnlocked = true`
4. **Observation :** Les deux `setString` ne sont pas dans une transaction. Si l'app crash entre les deux, l'etat pourrait etre inconsistant (salt ecrit mais pas le hash, ou inversement).

### Block-by-Block Analysis

**Bloc generation du salt (ligne 78)**
- **What :** Appelle `_generateSalt()` qui utilise `Random.secure()` pour generer 16 octets aleatoires, encodes en base64
- **Why here :** Le salt doit etre genere avant le hash
- **Assumptions :** `Random.secure()` est cryptographiquement sur sur toutes les plateformes Flutter desktop

**Bloc stockage (lignes 79-80)**
- **What :** Ecrit d'abord le salt, puis le hash dans SharedPreferences
- **Why here :** Les deux valeurs doivent etre persistees avant la mise a jour de l'etat
- **Assumptions :** L'ordre d'ecriture (salt avant hash) est important pour la coherence. Si seul le salt est ecrit, `verifyPin()` echouera car le hash stored sera l'ancien ou null.

### Cross-Function Dependencies
1. `_generateSalt()` (lignes 66-70) — generation du salt
2. `_hashPin()` (lignes 72-74) — hashing SHA-256 de `salt:pin`
3. `verifyPin()` — utilise le hash et le salt stockes pour la verification
4. `removePin()` — supprime les cles creees par `setPin()`

---

## 2.8 LockNotifier.verifyPin()

**Fichier :** `/home/huynh-kevin/projects/ChillApp/lib/features/lock/lock_provider.dart`, lignes 84-143

### Purpose
Verifie un PIN saisi contre le hash stocke. Gere le rate limiting (verrouillage de 30 secondes apres 5 echecs) et la migration automatique de l'ancien format sans salt vers le nouveau format.

### Inputs & Assumptions
1. `pin` (String) — le PIN saisi
2. **Assumption :** `SharedPreferences` contient un `pin_hash` valide (sinon retourne false)
3. **Assumption :** le rate limiting est base sur l'etat Riverpod en memoire ET persiste dans SharedPreferences
4. **Assumption :** `DateTime.now()` est fiable (non manipulable par l'utilisateur)

### Outputs & Effects
1. Retourne `bool` — true si le PIN est correct, false sinon
2. En cas de succes : remet les compteurs a zero, met `isUnlocked = true`
3. En cas d'echec : incremente `failedAttempts`, si >= 5 cree un `lockedUntil` de 30 secondes
4. Persiste les compteurs dans SharedPreferences
5. **Migration :** si `pin_salt` n'existe pas (ancien format), verifie avec SHA-256 simple, et si correct, migre vers le format salt (lignes 107-116)

### Block-by-Block Analysis

**Bloc rate limiting check (lignes 88-96)**
- **What :** Verifie si l'utilisateur est actuellement verrouille (>= 5 echecs et lockedUntil dans le futur)
- **Why here :** Premier controle avant toute verification de PIN
- **Assumptions :** La condition `state.failedAttempts >= 5 && state.lockedUntil != null` necessite les DEUX conditions. Si `failedAttempts >= 5` mais `lockedUntil` est null, le rate limiting n'est pas actif.
- **Observation :** Si le verrouillage est expire (ligne 89), les compteurs sont remis a zero. Le PIN n'est pas verifie dans cette branche — l'utilisateur devra re-saisir.

**Bloc verification avec salt (lignes 104-106)**
- **What :** Hash le PIN avec le salt stocke et compare au hash stocke
- **Why here :** Chemin principal de verification
- **Assumptions :** La comparaison est par valeur de string (`==`), pas par comparaison temporelle constante

**Bloc migration ancien format (lignes 107-116)**
- **What :** Si pas de salt, verifie avec SHA-256 simple, puis migre si correct
- **Why here :** Retrocompatibilite avec une version precedente qui n'utilisait pas de salt
- **Assumptions :** L'ancien format stockait `sha256(pin)` directement. La migration genere un nouveau salt et re-hash.

**Bloc echec (lignes 128-141)**
- **What :** Incremente les tentatives, active le verrouillage si >= 5
- **Why here :** Apres l'echec de verification
- **Assumptions :** Le verrouillage est de 30 secondes exactement (ligne 132). Le compteur n'est pas borne — apres expiration du verrouillage, 5 nouvelles tentatives sont possibles.

### Cross-Function Dependencies
1. `_hashPin()` — calcul du hash
2. `_generateSalt()` — utilise lors de la migration
3. `setPin()` — la verification depend du format de stockage de `setPin()`
4. `LockScreen._verify()` — appelant principal
5. `PinInputDialog.onComplete` — appelant secondaire pour les dialogues

---

## 2.9 LockNotifier.removePin()

**Fichier :** `/home/huynh-kevin/projects/ChillApp/lib/features/lock/lock_provider.dart`, lignes 145-157

### Purpose
Supprime completement le PIN : efface les 4 cles SharedPreferences et remet l'etat a "pas de PIN, deverrouille".

### Inputs & Assumptions
1. Aucun parametre
2. **Assumption :** les 4 appels `remove()` s'executent avec succes
3. **Assumption :** l'appelant a deja verifie que l'utilisateur est autorise a supprimer le PIN (verification du PIN actuel)

### Outputs & Effects
1. Supprime `pin_hash`, `pin_salt`, `pin_failed_attempts`, `pin_locked_until` de SharedPreferences
2. Met a jour l'etat : `isEnabled = false`, `isUnlocked = true`, `failedAttempts = 0`, `lockedUntil = null`

### Cross-Function Dependencies
1. `setPin()` — cree les cles que `removePin()` supprime
2. Unclear; need to inspect l'appelant dans les ecrans Settings pour verifier si la verification PIN est requise avant suppression

---

## 2.10 TailscaleNotifier._startDaemon()

**Fichier :** `/home/huynh-kevin/projects/ChillApp/lib/features/tailscale/tailscale_provider.dart`, lignes 110-146

### Purpose
Demarre le processus daemon Go `chill-tailscale` et etablit la communication bidirectionnelle JSON via stdin/stdout. Envoie la commande `start` une fois le processus lance.

### Inputs & Assumptions
1. Aucun parametre (utilise `_getDaemonPath()` pour localiser le binaire)
2. **Assumption :** le binaire `chill-tailscale` est present au chemin attendu
3. **Assumption :** le daemon emet des lignes JSON sur stdout et accepte des commandes JSON sur stdin
4. **Assumption :** le daemon est un processus long qui reste actif

### Outputs & Effects
1. Met `status = loading` au debut
2. Lance le processus via `Process.start(daemonPath, [])`
3. Abonne a stdout (ligne par ligne, JSON) via `_handleEvent()`
4. Abonne a stderr pour debug logging
5. Envoie `{'cmd': 'start'}` sur stdin
6. En cas d'erreur : met `status = error` avec message "Le moteur Tailscale est introuvable."

### Block-by-Block Analysis

**Bloc localisation du daemon (ligne 116)**
- **What :** Appelle `_getDaemonPath()` pour trouver le binaire
- **Why here :** Le chemin varie entre production et debug
- **Assumptions :** `_getDaemonPath()` (lignes 81-107) cherche dans plusieurs repertoires : a cote de l'executable Flutter, dans `lib/`, `data/`, puis remonte l'arbre de build pour trouver `tailscale-daemon/`. Fallback au PATH systeme (ligne 106).

**Bloc Process.start (ligne 119)**
- **What :** Lance le daemon comme processus enfant
- **Why here :** `Process.start` (pas `run`) car c'est un processus long-lived
- **Assumptions :** Le daemon demarre sans arguments et commence a ecouter stdin immediatement

**Bloc stdout listener (lignes 122-129)**
- **What :** Transforme le flux stdout en lignes, chaque ligne est parsee comme JSON par `_handleEvent`
- **Why here :** Le protocole est "une ligne JSON par evenement"
- **Assumptions :** Chaque ligne est un JSON valide. Les lignes incompletes ou corrompues causeront une erreur dans `_handleEvent` (catchee par le try/catch interne)

**Bloc stderr listener (lignes 132-135)**
- **What :** Affiche les logs du daemon en debug
- **Why here :** Pour le diagnostic
- **Assumptions :** stderr ne contient que des logs informatifs, pas de donnees critiques

**Bloc sendCommand start (ligne 138)**
- **What :** Envoie `{'cmd': 'start'}` au daemon
- **Why here :** Demande au daemon de se connecter au backend Tailscale
- **Assumptions :** Le daemon est pret a recevoir des commandes immediatement apres `Process.start`

### Cross-Function Dependencies
1. `_getDaemonPath()` — localise le binaire
2. `_handleEvent()` — parse les reponses JSON
3. `_onDaemonCrash()` — appele si le flux stdout se termine
4. `_sendCommand()` — envoie des commandes JSON au daemon
5. `_shutdownDaemon()` — arrete le daemon proprement
6. `retry()` — appelle `_startDaemon()` apres avoir tue l'ancien daemon

---

## 2.11 TailscaleNotifier._shutdownDaemon()

**Fichier :** `/home/huynh-kevin/projects/ChillApp/lib/features/tailscale/tailscale_provider.dart`, lignes 301-325

### Purpose
Arrete le daemon proprement. Envoie la commande `shutdown` via stdin, attend 3 secondes, puis tue le processus si necessaire.

### Inputs & Assumptions
1. Aucun parametre (utilise `_daemon`)
2. **Assumption :** le daemon repond a la commande `{'cmd': 'shutdown'}` en se terminant
3. **Assumption :** 3 secondes est suffisant pour un arret propre

### Outputs & Effects
1. Arrete le polling (`_stopPolling()`)
2. Annule les abonnements stdout/stderr
3. Met `_daemon = null` AVANT d'envoyer la commande shutdown (ligne 309)
4. Envoie `{'cmd': 'shutdown'}` sur stdin
5. Attend `exitCode` avec timeout de 3 secondes, tue si timeout
6. En cas d'exception (ex: stdin deja ferme) : tue le processus

### Block-by-Block Analysis

**Bloc null check et reassignment (lignes 307-309)**
- **What :** Sauvegarde la reference au process, met `_daemon` a null
- **Why here :** Previent les acces concurrents au daemon pendant l'arret
- **Assumptions :** Aucun autre code ne peut lancer un nouveau daemon pendant l'arret (single-threaded Dart)

**Bloc shutdown command + wait (lignes 312-320)**
- **What :** Envoie la commande JSON de shutdown, attend la terminaison avec timeout
- **Why here :** Arret gracieux avant le kill force
- **Assumptions :** `unawaited()` signifie que le `exitCode` future n'est pas attendu par `_shutdownDaemon()` lui-meme. Cela signifie que le processus pourrait continuer a tourner apres le retour de `_shutdownDaemon()`.
- **Observation :** `_shutdownDaemon()` est `void` (pas `Future<void>`), donc il ne peut pas etre attendu.

### Cross-Function Dependencies
1. `ref.onDispose()` (ligne 76) — appelle `_shutdownDaemon()` a la destruction du provider
2. `retry()` — tue le daemon avant de le relancer (mais n'utilise pas `_shutdownDaemon()`, gere le kill manuellement)

---

## 2.12 TailscaleNotifier.login()

**Fichier :** `/home/huynh-kevin/projects/ChillApp/lib/features/tailscale/tailscale_provider.dart`, lignes 236-239

### Purpose
Declenche le processus de login OAuth Tailscale. Envoie la commande `login` au daemon qui repondra avec un evenement `auth_url`.

### Inputs & Assumptions
1. Aucun parametre
2. **Assumption :** le daemon est actif et en etat `loggedOut`
3. **Assumption :** le daemon va repondre avec un `auth_url` event contenant une URL Tailscale valide

### Outputs & Effects
1. Met `isLoggingIn = true` et efface les erreurs precedentes
2. Envoie `{'cmd': 'login'}` au daemon

### Cross-Function Dependencies
1. `_sendCommand()` — envoie la commande
2. `_handleEvent()` — recevra la reponse `auth_url` et appellera `_openUrl()`
3. `_openUrl()` (lignes 275-284) — ouvre l'URL dans le navigateur systeme

---

## 2.13 TailscaleNotifier.retry()

**Fichier :** `/home/huynh-kevin/projects/ChillApp/lib/features/tailscale/tailscale_provider.dart`, lignes 248-260

### Purpose
Relance le daemon apres une erreur. Tue l'ancien processus si existant, arrete le polling, puis demarre un nouveau daemon.

### Inputs & Assumptions
1. Aucun parametre
2. **Assumption :** `process.kill()` reussit a terminer le processus
3. **Assumption :** attendre `exitCode` avec timeout de 3s est suffisant

### Outputs & Effects
1. Met `_daemon = null` avant de tuer le processus
2. Appelle `process.kill()` (SIGTERM sur Linux/macOS, TerminateProcess sur Windows)
3. Attend `exitCode` avec timeout 3s (ignore le timeout)
4. Arrete le polling
5. Appelle `_startDaemon()` pour relancer

### Block-by-Block Analysis

**Bloc kill ancien daemon (lignes 249-257)**
- **What :** Met _daemon a null, tue le processus, attend un peu
- **Why here :** Il faut nettoyer l'ancien avant de relancer
- **Assumptions :** `process.kill()` envoie SIGTERM. Si le processus ne repond pas en 3s, il continue a tourner (pas de SIGKILL).

---

## 2.14 TailscaleNotifier._openUrl()

**Fichier :** `/home/huynh-kevin/projects/ChillApp/lib/features/tailscale/tailscale_provider.dart`, lignes 275-284

### Purpose
Ouvre une URL dans le navigateur systeme par defaut. Utilisee pour ouvrir l'URL d'authentification Tailscale.

### Inputs & Assumptions
1. `url` (String) — l'URL a ouvrir, recue du daemon via JSON
2. **Assumption :** l'URL est une URL Tailscale valide
3. **Assumption :** l'URL ne contient pas de caracteres malveillants
4. **Assumption Linux :** `xdg-open` est disponible
5. **Assumption Windows :** le `''` (chaine vide) comme titre dans `cmd /c start '' url` empeche l'injection

### Outputs & Effects
1. **Linux :** Execute `Process.run('xdg-open', [url])` — l'URL est passee comme argument separe
2. **Windows :** Execute `Process.run('cmd', ['/c', 'start', '', url])` — le `''` est le titre de la fenetre, l'URL est le 5e element de la liste d'arguments
3. **macOS :** Execute `Process.run('open', [url])` — l'URL est passee comme argument separe
4. Le resultat de `Process.run` n'est pas verifie

### Cross-Function Dependencies
1. `_handleEvent()` (case 'auth_url', ligne 167-170) — appelle `_openUrl()` avec l'URL du daemon
2. L'URL provient du daemon Go, qui la recoit du backend Tailscale

---

## 2.15 SshSetupNotifier.runAll()

**Fichier :** `/home/huynh-kevin/projects/ChillApp/lib/features/ssh_setup/ssh_setup_provider.dart`, lignes 97-117

### Purpose
Orchestre la configuration SSH complete. Detecte l'OS et delegue a `_runWindows()`, `_runLinux()`, ou `_runMac()`.

### Inputs & Assumptions
1. Aucun parametre
2. **Assumption :** l'utilisateur a declenche cette action manuellement (pas d'execution automatique)
3. **Assumption :** une seule execution a la fois (`isRunning` empeche l'execution concurrente cote UI)

### Outputs & Effects
1. Met `isRunning = true` au debut, `isRunning = false` a la fin
2. Met `isComplete = true` si tout reussit
3. En cas d'exception : met `errorMessage` avec le message d'erreur

---

## 2.16 SshSetupNotifier._runLinux()

**Fichier :** `/home/huynh-kevin/projects/ChillApp/lib/features/ssh_setup/ssh_setup_provider.dart`, lignes 213-308

### Purpose
Configure SSH sur Linux : detecte la distro, installe openssh-server, demarre/active le service, configure le firewall. Toutes les commandes admin sont regroupees dans un seul script bash execute via pkexec.

### Inputs & Assumptions
1. Aucun parametre
2. **Assumption :** la distro est correctement detectee par `OsDetector.detectLinuxDistro()`
3. **Assumption :** `apt`/`dnf`/`pacman` est disponible selon la distro
4. **Assumption :** les codes de sortie personnalises (10, 20) permettent d'identifier l'etape qui a echoue

### Outputs & Effects
1. Cree un fichier temporaire `setup.sh` dans un dossier temporaire unique
2. Execute le script via `CommandRunner.runElevated('bash', [tempScript.path])`
3. Supprime le dossier temporaire dans un `finally`
4. Analyse le code de sortie pour determiner quelle etape a echoue
5. Verifie ensuite que SSH tourne avec `systemctl is-active`
6. Recupere les informations reseau (IPs, username)

### Block-by-Block Analysis

**Bloc creation du script (lignes 236-255)**
- **What :** Construit un script bash multi-etapes avec des codes de sortie specifiques
- **Why here :** Regroupe toutes les commandes admin en un seul appel pkexec (un seul mot de passe)
- **Assumptions :** La variable `$installCmd` est determinee par la distro et contient une commande d'installation valide. Le script utilise des codes de sortie personnalises : 10 = echec installation, 20 = echec demarrage service.
- **Observation :** Le script est construit par interpolation de string Dart : `'$installCmd\n'`. La variable `installCmd` contient des commandes hard-coded dans le code source (pas d'entree utilisateur).

**Bloc execution elevee (lignes 257-266)**
- **What :** Cree un fichier temporaire, execute via pkexec, nettoie dans finally
- **Why here :** Execution avec elevation de privileges
- **Assumptions :** Le chemin du fichier temporaire ne contient pas de caracteres speciaux. `Directory.systemTemp.createTemp('chill-')` cree un dossier dans `/tmp/` avec un suffixe aleatoire.

**Bloc analyse des codes de sortie (lignes 269-284)**
- **What :** Map les codes de sortie aux etapes specifiques
- **Why here :** Le script utilise des codes de sortie pour communiquer quelle etape a echoue
- **Assumptions :** 126 = erreur de permission pkexec, 127 = pkexec introuvable, 10 = echec install, 20 = echec service

### Cross-Function Dependencies
1. `OsDetector.detectLinuxDistro()` — determine la commande d'installation
2. `CommandRunner.runElevated()` — execute le script avec elevation
3. `CommandRunner.run()` — verifie le statut du service apres installation
4. `NetworkInfo.getEthernetIp()/getWifiIp()/getUsername()` — recupere les informations de connexion

---

## 2.17 SshSetupNotifier._runWindows()

**Fichier :** `/home/huynh-kevin/projects/ChillApp/lib/features/ssh_setup/ssh_setup_provider.dart`, lignes 127-208

### Purpose
Configure SSH sur Windows via PowerShell : installe le client et le serveur OpenSSH, demarre et active le service, configure le firewall, verifie le fonctionnement.

### Inputs & Assumptions
1. Aucun parametre
2. **Assumption :** les commandes PowerShell sont executees avec les privileges adequats (certaines necessitent admin)
3. **Assumption :** `Add-WindowsCapability` fonctionne meme en mode non-admin pour verifier l'installation
4. **Assumption :** "already installed" dans stderr indique que le composant est deja present

### Outputs & Effects
1. 7 etapes sequentielles, chacune mise a jour dans l'UI
2. Chaque etape est verifiee et en cas d'echec, une exception est levee
3. Installe OpenSSH.Client puis OpenSSH.Server
4. Demarre le service `sshd` et le configure en demarrage automatique
5. Cree une regle firewall pour le port 22 si aucune regle SSH n'existe
6. Verifie que le service est en etat "Running"

### Block-by-Block Analysis

**Bloc verification firewall (lignes 172-187)**
- **What :** Verifie si une regle firewall SSH existe, sinon la cree
- **Why here :** Necessaire apres l'installation et le demarrage du service
- **Assumptions :** `Get-NetFirewallRule -Name *ssh*` avec le wildcard detecte toute regle liee a SSH. Si aucune regle n'existe (`stdout.isEmpty`), une nouvelle regle est creee sur le port 22 TCP inbound.
- **Observation :** Le nom de la regle est `sshd` et le DisplayName est `OpenSSH Server` — les deux sont hard-coded.

---

## 2.18 WolSetupNotifier.runAll() et sous-methodes

**Fichier :** `/home/huynh-kevin/projects/ChillApp/lib/features/wol_setup/wol_setup_provider.dart`, lignes 95-114

### Purpose
Orchestre la configuration Wake-on-LAN complete. Detecte l'OS et delegue a `_runWindows()` ou `_runLinux()`. macOS n'est pas supporte (exception).

---

## 2.19 WolSetupNotifier._runWindows()

**Fichier :** `/home/huynh-kevin/projects/ChillApp/lib/features/wol_setup/wol_setup_provider.dart`, lignes 124-231

### Purpose
Configure WoL sur Windows : trouve la carte Ethernet, active Magic Packet, autorise le reveil reseau, desactive le demarrage rapide, recupere la MAC.

### Inputs & Assumptions
1. **Assumption :** il existe une carte Ethernet physique active (non WiFi, non Bluetooth, non Virtual)
2. **Assumption :** le nom de l'adaptateur peut contenir des apostrophes — elles sont echappees avec `replaceAll("'", "''")` (lignes 147-148) pour PowerShell

### Outputs & Effects
1. Detecte l'adaptateur Ethernet via PowerShell (filtrage par InterfaceDescription)
2. Le format de sortie est `Name|||Description` (delimite par `|||`)
3. Active la propriete "Wake on Magic Packet" via `Set-NetAdapterAdvancedProperty`
4. Autorise le reveil par le reseau via `powercfg /deviceenablewake`
5. Desactive le demarrage rapide via modification du registre (`HiberbootEnabled = 0`)
6. Recupere l'adresse MAC

### Block-by-Block Analysis

**Bloc echappement nom adaptateur (lignes 147-148)**
- **What :** Echappe les apostrophes dans le nom et la description de l'adaptateur pour utilisation dans les commandes PowerShell
- **Why here :** Le nom de l'adaptateur vient de la sortie de `Get-NetAdapter` et est insere dans des commandes PowerShell subsequentes
- **Assumptions :** Le remplacement `' -> ''` est l'echappement correct pour les chaines PowerShell entre guillemets simples

**Bloc modification registre (lignes 200-217)**
- **What :** Desactive le demarrage rapide Windows via `reg add` sur `HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Power`
- **Why here :** Le demarrage rapide peut empecher le WoL de fonctionner
- **Assumptions :** La commande `reg add ... /f` ecrase silencieusement la valeur existante. La verification ulterieure (lignes 206-211) confirme que la valeur est bien 0.

---

## 2.20 WolSetupNotifier._runLinux()

**Fichier :** `/home/huynh-kevin/projects/ChillApp/lib/features/wol_setup/wol_setup_provider.dart`, lignes 236-384

### Purpose
Configure WoL sur Linux : installe ethtool si necessaire, trouve l'interface Ethernet, active WoL avec `ethtool -s`, cree un service systemd pour rendre la configuration permanente.

### Inputs & Assumptions
1. **Assumption :** l'interface Ethernet trouvee supporte WoL
2. **Assumption :** le nom de l'interface (`ethIface`) est insere dans le contenu du service systemd (lignes 296-307) et dans le script bash (lignes 314-331) sans echappement
3. **Assumption :** le script bash est execute avec elevation via `CommandRunner.runElevated('bash', [tempScript.path])`

### Outputs & Effects
1. Verifie si `ethtool` est installe (pas d'elevation)
2. Trouve l'interface Ethernet active
3. Cree un fichier service systemd dans un dossier temporaire
4. Construit un script bash qui : installe ethtool si necessaire, active WoL, verifie, copie le service, l'active
5. Execute le script via pkexec
6. Nettoie les fichiers temporaires
7. Recupere la MAC et les IPs

### Block-by-Block Analysis

**Bloc creation du service systemd (lignes 296-309)**
- **What :** Genere le contenu d'un fichier `.service` avec le nom de l'interface interpole
- **Why here :** Le service systemd doit etre cree avant l'execution du script admin
- **Assumptions :** Le nom de l'interface (`$ethIface`) est insere dans `ExecStart=/usr/sbin/ethtool -s $ethIface wol g` (ligne 303). Le chemin du fichier temporaire (`${tempServiceFile.path}`) est insere dans le script bash pour la copie vers `/etc/systemd/system/`.
- **Observation :** Le nom de l'interface provient de la sortie de `ls /sys/class/net/` dans un script bash precedent (findAdapter).

**Bloc script bash admin (lignes 314-331)**
- **What :** Script multi-etapes avec codes de sortie : 10 = echec install ethtool, 20 = echec activation WoL, 30 = WoL non detecte apres activation, 40 = echec service systemd
- **Why here :** Regroupe toutes les commandes admin en un seul appel pkexec
- **Assumptions :** Le `$installCmd` est construit a partir de la distro. Le `$ethIface` est interpole dans les commandes `ethtool` sans echappement. Le chemin du fichier service temporaire est interpole dans la commande `cp`.

---

# PHASE 3 — Global System Understanding

## 3.1 Invariants systeme

1. **Invariant PIN hash/salt :** `pin_hash` et `pin_salt` doivent toujours exister ensemble dans SharedPreferences. Si `pin_salt` n'existe pas mais `pin_hash` existe, c'est l'ancien format (migration automatique dans `verifyPin()`).

2. **Invariant lock gate :** Si `lockState.isEnabled == true` et `lockState.isUnlocked == false`, l'UI affiche `LockScreen` au lieu de l'app (verifie dans `app.dart`, lignes 18-27). Aucune route de l'app n'est accessible.

3. **Invariant execution unique :** Les setups SSH et WoL utilisent `isRunning` pour empecher l'execution concurrente. Cependant, cette protection est cote UI (le bouton est desactive) — le provider n'a pas de garde interne.

4. **Invariant daemon unique :** Un seul processus `chill-tailscale` est cense tourner. `retry()` tue l'ancien avant d'en lancer un nouveau. `_shutdownDaemon()` met `_daemon = null` avant de tuer.

5. **Invariant nettoyage temporaire :** Les fichiers temporaires (scripts bash) sont crees dans `Directory.systemTemp.createTemp('chill-')` et supprimes dans un `finally`. Si la suppression echoue, les fichiers restent dans `/tmp/`.

6. **Invariant elevation unique Linux :** Les configurations SSH et WoL sur Linux regroupent toutes les commandes admin dans un seul script bash execute via pkexec — un seul mot de passe est demande.

## 3.2 Workflows end-to-end

### Workflow SSH Setup (Linux)
```
Utilisateur clique "Configurer SSH"
  -> SshSetupNotifier.runAll()
    -> OsDetector.detectLinuxDistro()
      -> Lecture /etc/os-release
    -> _runLinux()
      -> Construction du script bash (install + systemctl + firewall)
      -> Ecriture dans fichier temporaire
      -> CommandRunner.runElevated('bash', [tempScript.path])
        -> CommandRunner.run('pkexec', ['bash', '/tmp/chill-XXXXX/setup.sh'])
          -> Process.run('pkexec', ['bash', '/tmp/chill-XXXXX/setup.sh'])
            -> pkexec affiche la boite polkit
            -> Utilisateur saisit le mot de passe
            -> bash execute le script en tant que root
      -> Suppression fichier temporaire
      -> Analyse du code de sortie
      -> CommandRunner.run('systemctl', ['is-active', '--quiet', 'sshd'])
      -> NetworkInfo.getEthernetIp() / getWifiIp() / getUsername()
  -> state.isComplete = true
```

### Workflow SSH Setup (Windows)
```
Utilisateur clique "Configurer SSH"
  -> SshSetupNotifier.runAll()
    -> _runWindows()
      -> CommandRunner.runPowerShell('Add-WindowsCapability -Online -Name OpenSSH.Client...')
      -> CommandRunner.runPowerShell('Add-WindowsCapability -Online -Name OpenSSH.Server...')
      -> CommandRunner.runPowerShell('Start-Service sshd')
      -> CommandRunner.runPowerShell("Set-Service -Name sshd -StartupType 'Automatic'")
      -> CommandRunner.runPowerShell("Get-NetFirewallRule -Name *ssh*...")
      -> CommandRunner.runPowerShell("New-NetFirewallRule ...") [si necessaire]
      -> CommandRunner.runPowerShell("(Get-Service sshd).Status")
      -> NetworkInfo.getEthernetIp() / getWifiIp() / getUsername()
  -> state.isComplete = true
```

### Workflow WoL Setup (Linux)
```
Utilisateur clique "Configurer WoL"
  -> WolSetupNotifier.runAll()
    -> OsDetector.detectLinuxDistro()
    -> _runLinux()
      -> Verification ethtool (sans elevation)
      -> Detection interface Ethernet (sans elevation)
      -> Construction fichier service systemd (dans temp)
      -> Construction script bash (install ethtool + ethtool -s + service)
      -> CommandRunner.runElevated('bash', [tempScript.path])
        -> pkexec -> mot de passe -> execution root
      -> Suppression temp
      -> Analyse code de sortie
      -> NetworkInfo.getMacAddress() / getEthernetIp() / getWifiIp()
  -> state.isComplete = true
```

### Workflow Tailscale Login
```
Utilisateur clique "Se connecter"
  -> TailscaleNotifier.login()
    -> state.isLoggingIn = true
    -> _sendCommand({'cmd': 'login'})
      -> _daemon!.stdin.writeln(jsonEncode({'cmd': 'login'}))
    -> Daemon Go recoit la commande
    -> Daemon Go contacte Tailscale control plane
    -> Daemon Go repond avec {'event': 'auth_url', 'url': 'https://...'}
    -> _handleEvent() traite la ligne JSON
      -> _openUrl(url)
        -> Process.run('xdg-open', [url]) [Linux]
    -> Utilisateur s'authentifie dans le navigateur
    -> Daemon Go detecte la connexion
    -> Daemon Go repond avec {'event': 'connected', ...}
    -> _handleEvent() met a jour l'etat
      -> state.status = connected, peers, selfIp, etc.
      -> _startPolling() (refresh toutes les 10s)
```

### Workflow PIN Lock
```
Application demarre
  -> main.dart -> ProviderScope -> ChillApp
    -> lockProvider.build()
      -> _load() [Future, non attendu]
        -> SharedPreferences.getInstance()
        -> Lecture pin_hash, failedAttempts, lockedUntil
      -> return LockState() [defaut: isEnabled=false, isUnlocked=false]
    -> app.dart verifie lockState.isEnabled && !lockState.isUnlocked
      -> Si true : affiche LockScreen
      -> Si false : affiche MaterialApp.router

Utilisateur saisit le PIN (8 chiffres)
  -> LockScreen._onDigit() x8
    -> LockScreen._verify()
      -> lockProvider.notifier.verifyPin(pin)
        -> SharedPreferences.getInstance()
        -> Verification rate limiting
        -> Recuperation hash + salt stockes
        -> Calcul SHA-256(salt:pin)
        -> Comparaison avec hash stocke
        -> Mise a jour compteurs
  -> Si succes : state.isUnlocked = true
    -> app.dart rebuild -> MaterialApp.router (app accessible)
  -> Si echec : animation shake, message d'erreur
```

## 3.3 Limites de confiance detaillees

| # | Frontiere | Source | Destination | Donnees traversant | Mecanisme de protection |
|---|-----------|--------|-------------|-------------------|------------------------|
| 1 | UI -> LockNotifier | Saisie utilisateur | verifyPin() | PIN (8 chiffres) | Validation longueur cote UI (max 8), rate limiting (5 essais/30s) |
| 2 | LockNotifier -> SharedPreferences | Provider | Stockage local | Hash, salt, compteurs | Aucun chiffrement du stockage |
| 3 | Providers -> CommandRunner.run() | Logique metier | Execution systeme | Executable + args (hard-coded) | Arguments passes comme List<String> |
| 4 | Providers -> CommandRunner.runPowerShell() | Logique metier | PowerShell | Commandes PS (hard-coded) | `-NoProfile`, `-Command` |
| 5 | Providers -> CommandRunner.runElevated() | Logique metier | Shell eleve | Commandes + args | Echappement partiel (Windows: `"`, macOS: `\`, `"`, `$`) |
| 6 | CommandRunner -> Process.run | Dart VM | OS Kernel | Executable + args | Separation des arguments (List<String>) |
| 7 | Setup providers -> Filesystem | Dart | /tmp/ | Scripts bash, services systemd | Dossier temporaire unique, suppression dans finally |
| 8 | TailscaleNotifier -> Process.start | Provider | Daemon Go | Commandes JSON via stdin | Serialisation JSON |
| 9 | Daemon Go -> TailscaleNotifier | Daemon | Provider | Evenements JSON via stdout | Deserialistion JSON avec try/catch |
| 10 | TailscaleNotifier -> _openUrl | Provider | Navigateur OS | URL du daemon | L'URL est passee comme argument (pas dans un shell pour Linux/macOS). Windows utilise `cmd /c start '' url`. |
| 11 | DashboardNotifier -> ref.listen | Provider | Provider | Etat Tailscale | Communication Riverpod interne |
| 12 | NetworkInfo -> /sys/class/net/ | Dart | Filesystem Linux | Noms d'interfaces, MAC, carrier | Lecture seule |
| 13 | NetworkInfo -> CommandRunner | Provider | Shell | Noms d'interfaces interpoles dans des commandes | Les noms d'interfaces sont interpoles dans des commandes bash sans echappement explicite |

## 3.4 Surface d'attaque complete

### Entrees utilisateur
| Entree | Source | Consommateur | Traitement |
|--------|--------|-------------|------------|
| PIN (8 chiffres) | Clavier / NumPad | LockNotifier.setPin(), verifyPin() | Hashing SHA-256 avec salt |
| Clic "Configurer SSH" | UI | SshSetupNotifier.runAll() | Declenchement de workflow |
| Clic "Configurer WoL" | UI | WolSetupNotifier.runAll() | Declenchement de workflow |
| Clic "Se connecter" (Tailscale) | UI | TailscaleNotifier.login() | Envoi commande au daemon |
| Toggle theme | UI | ThemeModeNotifier.toggle() | Bool dans SharedPreferences |

### Entrees systeme (pas de controle utilisateur direct)
| Entree | Source | Consommateur | Traitement |
|--------|--------|-------------|------------|
| Noms d'interfaces reseau | `/sys/class/net/`, `Get-NetAdapter`, `networksetup` | NetworkInfo, WolSetupNotifier | Interpoles dans des commandes shell et des chemins de fichiers |
| Contenu de `/etc/os-release` | Filesystem | OsDetector | Parsing regex pour determiner la distro |
| Sortie JSON du daemon chill-tailscale | Processus Go | TailscaleNotifier._handleEvent() | Parsing JSON, extraction de strings (hostname, IP, URL) |
| URL d'authentification Tailscale | Daemon Go (via backend) | TailscaleNotifier._openUrl() | Passee a `xdg-open` / `cmd /c start` / `open` |
| Sortie des commandes PowerShell | PowerShell | Divers providers | Parsing de stdout (contains, split, regex) |
| Etat des services (sshd, ssh, wol-enable) | systemctl / Get-Service | DashboardNotifier | Verification booleen (success / contains 'Running') |

### Points d'interaction avec l'OS
| Action | Module | Commande | Privileges |
|--------|--------|----------|-----------|
| Installation OpenSSH | SshSetupNotifier | `Add-WindowsCapability` / `apt install` / `dnf install` / `pacman -S` | Admin (implicite sur Windows, pkexec sur Linux) |
| Demarrage service SSH | SshSetupNotifier | `Start-Service sshd` / `systemctl enable --now sshd` | Admin |
| Configuration firewall | SshSetupNotifier | `New-NetFirewallRule` / `ufw allow ssh` / `firewall-cmd` | Admin |
| Detection interface reseau | NetworkInfo, WolSetupNotifier | `Get-NetAdapter` / `ls /sys/class/net/` / `networksetup` | Utilisateur |
| Modification proprietees carte | WolSetupNotifier | `Set-NetAdapterAdvancedProperty` | Admin (implicite) |
| Modification registre Windows | WolSetupNotifier | `reg add HKLM\...` | Admin (implicite) |
| Modification powercfg | WolSetupNotifier | `powercfg /deviceenablewake` | Admin (implicite) |
| Creation service systemd | WolSetupNotifier | `cp ... /etc/systemd/system/` + `systemctl enable` | Admin (pkexec) |
| Lancement daemon Go | TailscaleNotifier | `Process.start(chill-tailscale)` | Utilisateur |
| Ouverture URL navigateur | TailscaleNotifier | `xdg-open` / `cmd /c start` / `open` | Utilisateur |
| Lecture /etc/os-release | OsDetector | `File.readAsString()` | Utilisateur |
| Lecture /sys/class/net/ | NetworkInfo | `ls` / `cat` via bash | Utilisateur |

### Stockage local
| Donnee | Mecanisme | Protection |
|--------|-----------|-----------|
| Hash du PIN | SharedPreferences (`pin_hash`) | SHA-256 avec salt (mais pas de chiffrement du stockage) |
| Salt du PIN | SharedPreferences (`pin_salt`) | Stocke en clair dans SharedPreferences |
| Tentatives echouees | SharedPreferences (`pin_failed_attempts`) | Stocke en clair |
| Timestamp de verrouillage | SharedPreferences (`pin_locked_until`) | Stocke en clair |
| Preference theme | SharedPreferences (`darkMode`) | Non sensible |

### Processus externes
| Processus | Lance par | Communication | Cycle de vie |
|-----------|----------|---------------|-------------|
| chill-tailscale | TailscaleNotifier._startDaemon() | JSON via stdin/stdout | Lance au build du provider, arrete a la destruction du provider ou via retry() |
| Commandes systeme (PowerShell, bash, pkexec, osascript) | CommandRunner.run() | Argument list + stdout/stderr | Ephemere (lance, attendu, termine) |
| xdg-open / cmd / open | TailscaleNotifier._openUrl() | URL comme argument | Fire-and-forget (resultat non verifie) |

---

## 3.5 Diagramme de dependances des modules

```
main.dart
  └── app.dart
       ├── config/router.dart
       │    ├── DashboardScreen
       │    ├── SshSetupScreen
       │    ├── WolSetupScreen
       │    ├── ConnectionInfoScreen
       │    ├── SettingsScreen
       │    └── TailscaleScreen
       ├── config/theme.dart
       │    └── config/design_tokens.dart
       ├── features/lock/lock_provider.dart
       │    ├── dart:convert, dart:math
       │    ├── package:crypto (SHA-256)
       │    └── package:shared_preferences
       └── features/settings/settings_provider.dart
            └── package:shared_preferences

features/dashboard/dashboard_provider.dart
  ├── core/command_runner.dart
  ├── core/os_detector.dart
  └── features/tailscale/tailscale_provider.dart

features/ssh_setup/ssh_setup_provider.dart
  ├── core/command_runner.dart
  ├── core/network_info.dart
  │    └── core/command_runner.dart
  ├── core/os_detector.dart
  └── shared/models/setup_step.dart

features/wol_setup/wol_setup_provider.dart
  ├── core/command_runner.dart
  ├── core/network_info.dart
  ├── core/os_detector.dart
  └── shared/models/setup_step.dart

features/connection_info/connection_info_provider.dart
  ├── core/command_runner.dart
  └── core/network_info.dart

features/tailscale/tailscale_provider.dart
  ├── dart:io (Process.start)
  └── dart:convert (JSON)
```

---

## 3.6 Recapitulatif des patterns architecturaux observes

1. **Pattern "CommandRunner centralize" :** Toute execution de commande passe par la classe statique `CommandRunner`. Cela cree un point d'audit unique.

2. **Pattern "Script temporaire" :** Pour les operations Linux elevees, un script bash est ecrit dans `/tmp/`, execute via pkexec, puis supprime. Cela permet un seul mot de passe pour plusieurs operations.

3. **Pattern "Code de sortie semantique" :** Les scripts bash utilisent des codes de sortie personnalises (10, 20, 30, 40) pour identifier l'etape ayant echoue, analyses ensuite par le provider Dart.

4. **Pattern "Daemon IPC JSON" :** Le module Tailscale communique avec un processus Go externe via JSON sur stdin/stdout. Le daemon est gere comme un processus long-lived.

5. **Pattern "Riverpod Notifier" :** Chaque feature a un `Notifier` avec un etat immutable et un `build()` qui declenche le chargement initial via `Future.microtask()`.

6. **Pattern "UI gate" :** Le verrouillage PIN est une gate au niveau de `app.dart` : si le PIN est actif et non deverrouille, l'application entiere est remplacee par `LockScreen`.

7. **Pattern "OS branching" :** Chaque operation a des branches `Platform.isWindows / isLinux / isMacOS` avec des implementations completement separees par OS.

---

*Fin du rapport de contexte de securite. Ce document est factuel et ne contient ni identification de vulnerabilites, ni propositions de corrections, ni POC, ni attribution de severite.*
