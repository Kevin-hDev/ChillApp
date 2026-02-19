# PRD — SecureWake
## Réveil à distance sécurisé sans port forwarding

**Statut :** Proposition  
**Version :** 0.1  
**Date :** Février 2026  
**Auteur :** Kevin HUYNH  
**Cible :** Chill Desktop V2.0 + ChillShell

---

## 1. Contexte et problème

### Le problème actuel

Chill intègre déjà le Wake-on-LAN (WoL). Cette technologie fonctionne très bien, mais uniquement en réseau local. Pour réveiller son PC depuis l'extérieur (café, mobile data, autre réseau), il faut traditionnellement ouvrir un port sur le routeur — ce qui expose la machine sur internet et crée une faille de sécurité inacceptable.

La question est donc : **comment réveiller son PC à distance, sans port forwarding, de manière sécurisée ?**

### Pourquoi le WoL classique ne suffit pas à distance

Le Magic Packet WoL est envoyé en broadcast UDP sur le réseau local. Depuis internet, ce paquet ne peut pas traverser un routeur sans configuration explicite (port forwarding ou directed broadcast). Ces options sont soit non sécurisées, soit trop complexes pour des utilisateurs non-techniques.

### Pourquoi cette feature est maintenant possible

Deux éléments techniques permettent aujourd'hui de résoudre ce problème proprement :

**1. Windows Modern Standby (S0)**
Sur les PC Windows récents (Windows 10/11, matériel compatible), le processeur ne s'arrête pas complètement lors de la mise en veille. Il tourne au ralenti, exactement comme un téléphone en veille. Le réseau reste actif, les services continuent de tourner en arrière-plan.

**2. macOS Power Nap**
Apple a son propre mécanisme depuis longtemps. Sur Apple Silicon (M1/M2/M3...) il est actif en permanence et ne peut pas être désactivé. Sur Intel il est configurable. Dans les deux cas, le réseau reste disponible pendant la veille.

Ces deux mécanismes permettent à un service intégré dans Chill de **maintenir une connexion Tailscale active même pendant la veille**, et donc de recevoir un ordre de réveil sécurisé depuis n'importe où dans le monde.

---

## 2. Objectif de la feature

Permettre à un utilisateur de réveiller son PC à distance depuis ChillShell **sans port forwarding, sans routeur intermédiaire, sans infrastructure externe**, en s'appuyant uniquement sur Tailscale comme canal sécurisé.

### Ce que ça change pour l'utilisateur

| Avant | Après |
|---|---|
| WoL uniquement en réseau local | Réveil depuis n'importe où dans le monde |
| Port forwarding requis pour distance | Aucune config routeur nécessaire |
| Exposition sur internet | Invisible depuis internet (IP Tailscale uniquement) |
| Configuration technique complexe | Activation en un clic dans Chill |

---

## 3. Nom de la feature

**SecureWake**

Nom court, compréhensible, qui communique immédiatement l'idée : un réveil sécurisé. À utiliser dans l'interface, la documentation et le marketing.

---

## 4. Périmètre

### Inclus dans cette feature

- Service SecureWake intégré dans Chill Desktop (Windows + macOS)
- Détection automatique de la compatibilité (Modern Standby / Power Nap)
- Activation / désactivation depuis l'interface Chill en un clic
- Bouton "Réveiller via SecureWake" dans ChillShell (remplacement ou complément du WoL classique)
- Communication exclusivement via l'IP Tailscale (jamais l'IP locale, jamais internet)
- Authentification par les clés déjà présentes dans l'écosystème Chill

### Hors périmètre pour cette version

- Linux (patch kernel proposé en décembre 2025, pas encore stable)
- PC complètement éteints (limite physique, non contournable en logiciel)
- Windows en mode veille S3 classique (processeur coupé, aucun service actif)

---

## 5. Architecture technique

### Vue d'ensemble

```
┌─────────────────────┐        Tailscale (chiffré)       ┌──────────────────────┐
│   ChillShell        │ ─────────────────────────────────► │   Chill Desktop      │
│   (Mobile)          │                                    │   (PC en veille)     │
│                     │   1. Envoie ordre SecureWake      │                      │
│   - Bouton Wake     │      signé via IP Tailscale       │   - Service actif    │
│   - Auth locale     │                                    │   - Reçoit l'ordre  │
│                     │   2. Chill reçoit, vérifie,       │   - Vérifie auth    │
│                     │      réveille le PC               │   - Réveille le PC  │
└─────────────────────┘                                    └──────────────────────┘
```

### Pourquoi Tailscale et pas autre chose

Tailscale résout déjà trois problèmes simultanément :
- **Chiffrement** : tout le trafic est chiffré de bout en bout (WireGuard sous le capot)
- **Authentification** : seules les machines enregistrées sur le même compte Tailscale peuvent communiquer
- **NAT traversal** : traversée des routeurs sans aucune configuration, dans les deux sens

Le service SecureWake n'écoute que sur l'IP Tailscale du PC. Cette IP est invisible depuis internet. Un attaquant extérieur ne peut pas la joindre.

### Le service SecureWake dans Chill Desktop

C'est un processus léger qui tourne en arrière-plan. Il s'inscrit comme service système au démarrage de Chill et reste actif pendant la veille grâce au Modern Standby ou Power Nap.

Il fait exactement trois choses :
1. Maintenir une connexion légère en écoute sur l'IP Tailscale
2. Vérifier l'authenticité de chaque ordre reçu
3. Déclencher le réveil du PC si l'ordre est valide

---

## 6. Implémentation Windows

### Prérequis

- Windows 10 version 1903 ou supérieur
- Matériel compatible Modern Standby (S0)
- Tailscale installé et connecté (déjà géré par Chill)

### Vérification de la compatibilité

Avant d'activer SecureWake, Chill doit vérifier que le PC est bien en Modern Standby.

```dart
// Dans Chill Desktop — vérification Modern Standby Windows
Future<bool> isModernStandbySupported() async {
  final result = await Process.run(
    'powercfg',
    ['/a'],
    runInShell: true,
  );
  // Modern Standby est dispo si "Veille connectée (S0 basse consommation)" apparaît
  return result.stdout.toString().contains('S0') ||
         result.stdout.toString().contains('Connected Standby');
}
```

### Enregistrement comme service Windows

Le service SecureWake doit survivre à la mise en veille. Sur Windows, cela se fait via un service système (Windows Service) qui s'inscrit dans le gestionnaire de services.

```dart
// Enregistrement du service SecureWake au démarrage
Future<void> registerSecureWakeService() async {
  // Crée le service Windows via sc.exe
  await Process.run('sc', [
    'create', 'ChillSecureWake',
    'binPath=', '"${Platform.resolvedExecutable} --securewake-service"',
    'start=', 'auto',
    'DisplayName=', 'Chill SecureWake',
  ], runInShell: true);

  // Démarre le service immédiatement
  await Process.run('sc', ['start', 'ChillSecureWake'], runInShell: true);
}
```

### Maintien du réseau en veille

Windows Modern Standby garde le réseau actif par défaut, mais il faut s'assurer que l'adaptateur réseau ne se désactive pas pour économiser de l'énergie.

```powershell
# Script PowerShell exécuté par Chill lors de l'activation de SecureWake
# Désactive la coupure réseau pendant la veille pour l'adaptateur Tailscale

$adapter = Get-NetAdapter | Where-Object { $_.InterfaceDescription -like "*Tailscale*" }
Set-NetAdapterPowerManagement -Name $adapter.Name -WakeOnMagicPacket Enabled
powercfg /setacvalueindex SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 d4e98f31-5ffe-4ce1-be31-1b38b384c009 0
```

### Écoute sur l'IP Tailscale

```dart
// Le service écoute uniquement sur l'IP Tailscale — jamais sur 0.0.0.0
Future<String> getTailscaleIP() async {
  final result = await Process.run('tailscale', ['ip', '-4']);
  return result.stdout.toString().trim(); // ex: 100.64.1.2
}

Future<void> startSecureWakeListener() async {
  final tailscaleIP = await getTailscaleIP();
  final server = await ServerSocket.bind(tailscaleIP, 47777);

  server.listen((socket) async {
    final data = await socket.first;
    if (await verifySecureWakeOrder(data)) {
      await wakeSystem();
    }
    socket.close();
  });
}
```

### Réveil du système

```dart
// Déclenche le réveil du PC depuis la veille
Future<void> wakeSystem() async {
  // Méthode 1 : appui virtuel sur le bouton power via SetSuspendState
  await Process.run('powercfg', ['/h', 'off']); // désactive hibernation si active
  
  // Méthode 2 : via l'API Windows SetThreadExecutionState
  // Signale au système que le service a besoin que la machine soit active
  await Process.run('powershell', [
    '-Command',
    '[System.Runtime.InteropServices.Marshal]::GetFunctionPointerForDelegate('
    + '[Windows.System.Power.PowerManager])'
  ]);
  
  // Méthode simple et fiable : écriture dans le journal d'événements
  // Windows interprète certains événements comme signal de réveil
  await Process.run('powershell', [
    '-Command',
    'Add-Type -AssemblyName System.Windows.Forms; '
    + '[System.Windows.Forms.Application]::DoEvents()'
  ]);
}
```

---

## 7. Implémentation macOS

### Prérequis

- macOS 11 (Big Sur) ou supérieur
- Apple Silicon : Power Nap toujours actif, aucune configuration requise
- Intel : Power Nap doit être activé (Chill le vérifie et propose de l'activer)

### Vérification Power Nap

```dart
// Vérification et activation de Power Nap sur Mac Intel
Future<bool> isPowerNapEnabled() async {
  final result = await Process.run('pmset', ['-g']);
  return result.stdout.toString().contains('powernap 1');
}

Future<void> enablePowerNap() async {
  // Requiert sudo — Chill demande les permissions admin
  await Process.run('sudo', ['pmset', '-a', 'powernap', '1']);
}

// Détection Apple Silicon vs Intel
Future<bool> isAppleSilicon() async {
  final result = await Process.run('uname', ['-m']);
  return result.stdout.toString().trim() == 'arm64';
}
```

### Enregistrement comme LaunchDaemon (service système macOS)

Sur macOS, les services persistants s'enregistrent via launchd. Un LaunchDaemon tourne en arrière-plan même pendant la veille Power Nap.

```xml
<!-- /Library/LaunchDaemons/com.chill.securewake.plist -->
<!-- Créé automatiquement par Chill lors de l'activation SecureWake -->

<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.chill.securewake</string>

  <key>ProgramArguments</key>
  <array>
    <string>/Applications/Chill.app/Contents/MacOS/Chill</string>
    <string>--securewake-service</string>
  </array>

  <!-- Démarrage automatique -->
  <key>RunAtLoad</key>
  <true/>

  <!-- Redémarrage automatique si crash -->
  <key>KeepAlive</key>
  <true/>

  <!-- Actif pendant Power Nap -->
  <key>ProcessType</key>
  <string>Background</string>

</dict>
</plist>
```

```dart
// Installation du LaunchDaemon depuis Chill
Future<void> installSecureWakeDaemon() async {
  final plistContent = _generatePlistContent();
  final plistPath = '/Library/LaunchDaemons/com.chill.securewake.plist';

  // Écrit le fichier plist (requiert sudo)
  await Process.run('sudo', ['tee', plistPath], input: plistContent);

  // Corrige les permissions
  await Process.run('sudo', ['chmod', '644', plistPath]);
  await Process.run('sudo', ['chown', 'root:wheel', plistPath]);

  // Charge le daemon
  await Process.run('sudo', ['launchctl', 'load', plistPath]);
}
```

### Écoute sur l'IP Tailscale (même logique que Windows)

```dart
// Sur macOS, Tailscale expose une IP 100.x.x.x identique
// Le code d'écoute est identique à Windows — même classe SecureWakeListener
Future<void> startSecureWakeListener() async {
  final tailscaleIP = await getTailscaleIP();
  final server = await ServerSocket.bind(tailscaleIP, 47777);

  server.listen((socket) async {
    final data = await socket.first;
    if (await verifySecureWakeOrder(data)) {
      await wakeSystem();
    }
    socket.close();
  });
}
```

### Réveil du système sur macOS

```dart
// Sur macOS, le réveil depuis Power Nap se fait via caffeinate ou IOKit
Future<void> wakeSystem() async {
  // Méthode 1 : caffeinate force le réveil complet
  await Process.run('caffeinate', ['-u', '-t', '1']);

  // Méthode 2 : via pmset wake immédiat
  await Process.run('sudo', ['pmset', 'sleepnow']); // remet en veille après réveil
  // (on ne l'appelle pas — on veut juste réveiller)

  // Signal au système que l'utilisateur est "actif"
  await Process.run('osascript', [
    '-e', 'tell application "System Events" to key code 0'
  ]);
}
```

---

## 8. Sécurité de l'ordre de réveil

### Le problème à résoudre

Même sur Tailscale, il faut s'assurer que l'ordre de réveil vient bien de ChillShell et pas d'une autre machine sur le réseau Tailscale (si jamais le compte est compromis).

### Solution : ordre signé avec timestamp

Chaque ordre de réveil est signé avec la clé privée SSH ED25519 déjà présente dans ChillShell. Le service SecureWake vérifie la signature avec la clé publique correspondante.

```dart
// Dans ChillShell — construction de l'ordre signé
Future<Uint8List> buildSecureWakeOrder(Ed25519KeyPair keyPair) async {
  final timestamp = DateTime.now().millisecondsSinceEpoch;
  final nonce = _generateRandomNonce(); // 16 octets aléatoires

  // Payload = timestamp + nonce (évite les attaques par rejeu)
  final payload = ByteData(24)
    ..setInt64(0, timestamp)
    ..buffer.asUint8List().setAll(8, nonce);

  // Signature Ed25519 du payload
  final signature = await keyPair.sign(payload.buffer.asUint8List());

  // Ordre final = payload + signature
  return Uint8List.fromList([
    ...payload.buffer.asUint8List(),
    ...signature.bytes,
  ]);
}
```

```dart
// Dans Chill Desktop — vérification de l'ordre reçu
Future<bool> verifySecureWakeOrder(Uint8List orderData) async {
  if (orderData.length < 88) return false; // taille minimale payload+signature

  final payload = orderData.sublist(0, 24);
  final signature = orderData.sublist(24);

  // Vérification du timestamp — rejette les ordres de plus de 30 secondes
  final timestamp = ByteData.sublistView(Uint8List.fromList(payload)).getInt64(0);
  final age = DateTime.now().millisecondsSinceEpoch - timestamp;
  if (age > 30000 || age < 0) return false; // ordre expiré ou futur

  // Vérification de la signature Ed25519
  final publicKey = await _loadAuthorizedPublicKey();
  return await publicKey.verify(payload, signature: Ed25519Signature(signature));
}
```

### Résumé des protections

| Menace | Protection |
|---|---|
| Attaquant extérieur | IP Tailscale invisible depuis internet |
| Machine non autorisée sur Tailscale | Signature Ed25519 vérifiée |
| Rejeu d'un ordre intercepté | Timestamp + nonce, validité 30 secondes |
| Brute force | Ed25519 — mathématiquement impossible |

---

## 9. Intégration dans l'interface

### Chill Desktop — Onglet SecureWake (nouveau)

```
┌─────────────────────────────────────────────┐
│  SecureWake                          🔒      │
│  Réveil à distance sécurisé                  │
├─────────────────────────────────────────────┤
│                                              │
│  Statut système                              │
│  ┌─────────────────────────────────────────┐│
│  │ ✅ Modern Standby (S0)    Compatible    ││
│  │ ✅ Tailscale              Connecté      ││
│  │ ✅ IP Tailscale           100.64.1.2    ││
│  └─────────────────────────────────────────┘│
│                                              │
│  ┌─────────────────────────────────────────┐│
│  │  SecureWake    [  Activé  ●  ]          ││
│  └─────────────────────────────────────────┘│
│                                              │
│  ℹ️  Votre PC peut être réveillé depuis      │
│     n'importe où via ChillShell.            │
│     Aucun port ouvert sur votre routeur.    │
│                                              │
└─────────────────────────────────────────────┘
```

### ChillShell — Bouton de réveil

Dans la fiche de connexion d'un PC, le bouton WoL existant est enrichi :

```
┌──────────────────────────────────┐
│  Mon PC                          │
│  100.64.1.2 (Tailscale)          │
├──────────────────────────────────┤
│                                  │
│  [ ⚡ Réveiller via SecureWake ] │  ← nouveau (si activé sur le PC)
│  [ Réveiller via WoL classique ] │  ← conservé (si même réseau)
│                                  │
│  [ 🔗 Se connecter en SSH ]      │
│                                  │
└──────────────────────────────────┘
```

---

## 10. Compatibilité et limites connues

### Ce qui fonctionne

| OS | Condition | Support |
|---|---|---|
| Windows 10/11 | Modern Standby (S0) activé | ✅ Complet |
| macOS Apple Silicon | Toujours compatible | ✅ Complet |
| macOS Intel | Power Nap activé | ✅ Complet |

### Ce qui ne fonctionne pas

| OS | Condition | Raison |
|---|---|---|
| Windows | Mode S3 (veille classique) | CPU coupé, aucun service actif |
| Linux | Toutes versions actuelles | Patch kernel en cours (décembre 2025), pas encore stable |
| Tous OS | PC complètement éteint | Limite physique, non contournable en logiciel |

### Détection automatique

Chill détecte automatiquement si le PC est compatible. Si ce n'est pas le cas, l'option SecureWake est grisée avec un message explicatif et des recommandations.

---

## 11. Roadmap et priorités

| Version | Contenu |
|---|---|
| V2.0 | SecureWake Windows + macOS |
| V2.1 | SecureWake Linux (si patch kernel intégré dans noyau stable) |
| V2.2 | Historique des réveils + alertes connexion |

---

## 12. Questions ouvertes

- Faut-il un port dédié fixe (47777) ou le rendre configurable dans l'interface ?
- Doit-on ajouter une notification sur le PC au moment du réveil ("Réveil déclenché par ChillShell") ?
- Faut-il un timeout automatique — si personne ne se connecte en SSH dans les 5 minutes après le réveil, le PC se remet en veille ?

---

*Document vivant — à mettre à jour au fil du développement.*
