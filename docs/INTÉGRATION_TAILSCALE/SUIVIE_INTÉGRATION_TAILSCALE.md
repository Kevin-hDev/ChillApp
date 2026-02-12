## SUIVIE INTÉGRATION TAILSCALE

---

### Statut : TERMINÉ

Date de fin : 12 février 2026

---

### Approche choisie

Le plan initial prévoyait `tsnet` (Go) + API REST Tailscale. En pratique, on a utilisé **libtailscale** (le vrai moteur Go de l'app officielle Tailscale Android), compilé avec `gomobile bind` depuis le repo `tailscale-android`.

Avantages :
- Tunnel VPN WireGuard embarqué directement dans l'app (pas besoin de l'app officielle)
- Authentification OAuth intégrée via le navigateur système
- Accès à la LocalAPI Go pour récupérer les appareils du réseau
- Aucun token API externe nécessaire

---

### Fichiers créés / modifiés

#### Côté Android (Kotlin)

| Fichier | Rôle |
|---------|------|
| `android/app/libs/libtailscale.aar` | Bibliothèque Go compilée (63 Mo), contient le moteur WireGuard + Tailscale |
| `TailscalePlugin.kt` | Plugin Flutter principal : implémente `libtailscale.AppContext` (20+ callbacks pour Go), gère le MethodChannel, l'IPN Bus, la LocalAPI, le stockage chiffré |
| `TailscaleVpnService.kt` | Service VPN Android : implémente `libtailscale.IPNService`, gère le tunnel réseau, le foreground service, les routes VPN |
| `build.gradle.kts` | Ajout des dépendances : `security-crypto`, `kotlinx-coroutines-android`, import du `.aar` |
| `AndroidManifest.xml` | Permissions VPN, foreground service, déclaration du VpnService |

#### Côté Flutter (Dart)

| Fichier | Rôle |
|---------|------|
| `lib/services/tailscale_service.dart` | Service MethodChannel (`com.chillshell.tailscale`) : login, logout, getStatus, getPeers, callback onStateChanged |
| `lib/features/settings/providers/tailscale_provider.dart` | Notifier Riverpod : gère l'état Tailscale, écoute les changements natifs, récupère la liste des peers |
| `lib/features/settings/widgets/tailscale_dashboard.dart` | Dashboard : affiche l'IP, le statut, la liste des appareils avec bouton copier IP |
| `lib/features/settings/widgets/tailscale_access_card.dart` | Carte d'accès : boutons login/logout, explication Tailscale pour les nouveaux utilisateurs |
| `lib/models/tailscale_device.dart` | Modèle de données : nom, IP, statut en ligne, OS, identifiant |

#### Traductions (i18n)

18 clés Tailscale traduites dans les 5 langues (EN, FR, DE, ES, ZH) dans les fichiers `app_*.arb`.

---

### Flux de fonctionnement

```
1. Utilisateur tape "Se connecter"
2. Flutter → MethodChannel → TailscalePlugin.handleLogin()
3. Vérification permission VPN Android
4. libtailscale.start() → démarre le backend Go
5. LocalAPI POST /localapi/v0/login-interactive (timeout 30s)
6. Go envoie notification IPN Bus : BrowseToURL → ouvre le navigateur
7. Utilisateur s'authentifie (Google, Microsoft, etc.)
8. Go envoie notification IPN Bus : LoginFinished
9. Go envoie notification IPN Bus : State = 6 (Running)
10. TailscaleVpnService démarre → tunnel VPN actif
11. Go envoie notification IPN Bus : NetMap → IP 100.x.y.z récupérée
12. Flutter notifié via onStateChanged → dashboard mis à jour
13. LocalAPI GET /localapi/v0/status → liste complète des peers
```

---

### Bugs corrigés pendant l'intégration

| Bug | Cause | Correction |
|-----|-------|------------|
| StackOverflowError dans `protect(int)` | `protect(fd)` appelait lui-même au lieu de `super.protect(fd)` (conflit interface IPNService / classe VpnService) | `return super.protect(fd)` |
| BrowseToURL null crash | Go envoie des notifications avec valeurs null, `json.has()` retourne true même si la valeur est null | Ajout `!json.isNull("BrowseToURL")` + validation URL |
| State null JSONException | `json.getInt("State")` crash sur null | `json.optInt("State", -1)` + null check |
| 404 sur login-interactive | Chemin sans slash initial | `/localapi/v0/login-interactive` (avec `/` au début) |
| Timeout immédiat | `callLocalAPI(0, ...)` = 0ms de timeout en Go | Changé à 30000 (30 secondes) |
| Seulement 1 appareil affiché | Utilisait l'API REST (nécessite token séparé jamais obtenu) | Remplacé par LocalAPI `/localapi/v0/status` (getPeers) |
| excludeRoute compilation | Android API attend `IpPrefix`, pas `InetAddress` + `prefixLen` séparés | `android.net.IpPrefix(InetAddress.getByName(route), prefixLen)` |

---

### Durcissement sécurité

| Mesure | Détail |
|--------|--------|
| URL OAuth masquée dans les logs | `Log.d("BrowseToURL received (142 chars)")` au lieu de l'URL complète |
| Messages d'erreur génériques | `"Authentication failed"` au lieu du stacktrace Kotlin |
| Clé publique tronquée | Seuls les 16 premiers caractères sont exposés comme identifiant |
| Presse-papier auto-nettoyé | L'IP copiée est effacée du clipboard après 30 secondes |
| Stockage chiffré | EncryptedSharedPreferences pour l'état Go, FlutterSecureStorage pour les settings Dart |

---

### Nettoyage code mort

Éléments supprimés après stabilisation :
- `tailscaleToken` dans AppSettings (auth gérée par Go natif, plus de token Dart)
- `getMyIP()` dans le service et le plugin Kotlin (IP récupérée via IPN Bus)
- `fromJson()` / `toJson()` dans TailscaleDevice (plus de REST API)
- Clé i18n `tailscaleNewSSH` dans les 5 langues (bouton SSH retiré par choix UX)
- Paramètres `clearToken` / `token` dans settings_provider

---

### Compilation libtailscale.aar

Commande utilisée (depuis le repo `tailscale-android` cloné) :

```bash
gomobile bind -target android -androidapi 26 -o libtailscale.aar ./libtailscale
```

Prérequis : Go 1.22+, Android SDK/NDK, gomobile (`go install golang.org/x/mobile/cmd/gomobile@latest`)

Fichier résultant : `android/app/libs/libtailscale.aar` (63 Mo)
