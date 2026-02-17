# Sécurité — Chill (Desktop)

Document officiel interne décrivant l'ensemble des mesures de sécurité implémentées dans Chill.
Dernière mise à jour : 13 février 2026.

---

## Méthodologie

La sécurité de Chill a été validée par deux audits internes :

1. **Audit de contexte architectural** (protocole Trail of Bits — audit-context-building), produisant une cartographie ultra-granulaire de tous les modules, des limites de confiance et de la surface d'attaque. Analyse ligne par ligne des fonctions critiques.
2. **Audit sécurité complet** (protocole Trail of Bits — sharp-edges + audit-context-building), mené par 6 agents spécialisés en deux phases. Cet audit a produit 38 findings : 4 critiques, 8 élevés, 14 moyens et 12 faibles. Tous ont été corrigés, mitigés ou documentés. L'ensemble des 61 tests passent après corrections.

Un audit qualité complémentaire a identifié et corrigé 34 problèmes (6 critiques, 14 importants, 14 mineurs), incluant des injections de commandes, des duplications de code et des problèmes d'accessibilité. Les 42 tests passent après corrections.

---

## Architecture sécurisée

### Point d'exécution unique

Toutes les commandes système passent par une classe centralisée unique (CommandRunner). Ce point d'entrée unique vers le shell de l'OS crée un point d'audit centralisé et facilite l'application de protections transversales : timeout par défaut de 120 secondes, gestion des exceptions, et séparation des arguments.

Les commandes sont passées sous forme de liste d'arguments séparés (et non concaténés dans une chaîne), ce qui empêche l'interprétation de métacaractères par le shell.

### Élévation de privilèges

L'élévation de privilèges est gérée par un mécanisme unique et sécurisé, adapté à chaque système d'exploitation :

- **Windows** : un script PowerShell temporaire est créé et exécuté via Start-Process avec le verbe RunAs. L'exécution utilise le paramètre -File (et non -Command), empêchant l'interprétation du contenu du script par PowerShell.
- **Linux** : un script bash temporaire est créé et exécuté via pkexec (polkit). Les arguments sont passés comme liste séparée, sans interprétation shell.
- **macOS** : un script temporaire est créé et exécuté via osascript avec privilèges administrateur. Les arguments sont protégés par un échappement POSIX (encapsulation en guillemets simples).

Dans les trois cas, les scripts temporaires sont créés dans des répertoires uniques avec des permissions restrictives (700), et supprimés systématiquement après exécution via un bloc finally.

### Verrouillage par gate UI

Si un code PIN est actif et que l'application n'a pas été déverrouillée, l'intégralité de l'application est remplacée par l'écran de verrouillage. Ce mécanisme opère au niveau le plus haut de l'arbre de widgets : aucune route de l'application n'est accessible tant que le PIN n'est pas vérifié.

Un écran de chargement est affiché au démarrage jusqu'à ce que l'état du PIN soit entièrement chargé depuis le stockage, empêchant tout contournement temporaire.

---

## Authentification locale

### Code PIN

Le PIN comporte un minimum de 8 chiffres. Une validation stricte (regex) est appliquée dans la logique métier, pas uniquement côté interface.

Le PIN est hashé avec PBKDF2-HMAC-SHA256 sur 100 000 itérations, combiné à un salt aléatoire de 16 octets généré par un générateur cryptographiquement sûr. Le PIN en clair n'est jamais stocké.

La comparaison du hash est effectuée en temps constant (XOR bit à bit) pour empêcher les attaques par timing. Trois points de comparaison dans le code utilisent cette méthode.

### Rate limiting et backoff exponentiel

Après 5 tentatives échouées, l'application se verrouille pendant 30 secondes. Le délai augmente ensuite de façon exponentielle : 60 secondes après 10 échecs, 120 après 15, plafonné à 300 secondes.

Le compteur de tentatives est monotone : il n'est jamais remis à zéro par l'expiration du délai. Seule la saisie d'un PIN correct réinitialise le compteur. Les compteurs sont persistés dans le stockage local et survivent aux redémarrages de l'application.

### Migration automatique

L'application gère automatiquement la migration depuis les anciens formats de stockage du PIN (SHA-256 simple sans salt) vers le format actuel avec PBKDF2 et salt. Cette migration est transparente pour l'utilisateur et se déclenche lors de la première vérification réussie.

---

## Configuration SSH automatisée

L'application configure automatiquement le serveur SSH selon le système d'exploitation, en regroupant toutes les opérations administratives dans un seul script exécuté avec élévation. L'utilisateur ne saisit son mot de passe administrateur qu'une seule fois.

### Protections spécifiques

- **Scripts temporaires sécurisés** : les scripts sont créés dans des répertoires temporaires uniques (noms aléatoires), avec des permissions restrictives (700 sur le répertoire et le script), et supprimés dans un bloc finally.
- **Codes de sortie sémantiques** : les scripts utilisent des codes de sortie personnalisés (10, 20, 30, 40) pour identifier précisément l'étape ayant échoué, permettant un diagnostic clair.
- **Vérification post-installation** : après la configuration, l'application vérifie que le service SSH est bien actif.
- **Configuration firewall** : une règle firewall pour le port 22 est créée uniquement si aucune règle SSH n'existe déjà.

### Systèmes supportés

- **Windows** : installation d'OpenSSH via Windows Capabilities, démarrage et activation automatique du service, configuration du firewall.
- **Linux** : détection automatique de la distribution (Ubuntu, Debian, Fedora, Arch et dérivées via ID_LIKE), installation via le gestionnaire de paquets approprié, activation du service via systemd, configuration du firewall.
- **macOS** : activation du Remote Login via les outils système.

---

## Configuration Wake-on-LAN automatisée

La configuration du Wake-on-LAN suit le même modèle sécurisé que SSH : un seul script avec élévation, des fichiers temporaires sécurisés, et des codes de sortie sémantiques.

### Protections spécifiques

- **Validation du nom d'interface** : une validation stricte par expression régulière (caractères alphanumériques, tirets et points uniquement, maximum 15 caractères) est appliquée sur tous les noms d'interface réseau avant leur utilisation dans des commandes.
- **Échappement des noms d'adaptateurs** : sur Windows, les noms d'adaptateurs réseau sont échappés pour PowerShell avant insertion dans les commandes.
- **Service systemd** : sur Linux, un service systemd est créé pour rendre la configuration WoL permanente après redémarrage.

---

## Intégration Tailscale

L'application communique avec un daemon Go externe (chill-tailscale) via un protocole JSON sur stdin/stdout. Ce daemon gère la connexion au réseau Tailscale.

### Protections spécifiques

- **Validation d'URL** : les URLs d'authentification reçues du daemon sont validées (schéma HTTPS uniquement) avant d'être ouvertes dans le navigateur.
- **Guard contre les appels concurrents** : un mécanisme de verrouillage empêche les tentatives de relance simultanées du daemon.
- **Arrêt propre** : le daemon est arrêté via une commande JSON dédiée, avec un timeout de 3 secondes avant un arrêt forcé. Les abonnements aux flux sont annulés proprement.
- **Parsing JSON défensif** : chaque réponse JSON du daemon est parsée dans un bloc try-catch. Les données de peers invalides sont filtrées silencieusement.
- **Vérification du binaire** : au démarrage, les permissions du binaire daemon sont vérifiées.
- **Messages d'erreur génériques** : les erreurs réseau et système ne divulguent pas de détails techniques à l'utilisateur. Les détails sont redirigés vers les logs de debug (inactifs en production).

---

## Protection contre les injections de commandes

L'audit a identifié et corrigé plusieurs vecteurs d'injection :

- **Élévation Windows** : remplacement de l'imbrication PowerShell par des scripts temporaires exécutés via -File, empêchant l'interprétation du contenu.
- **Élévation macOS** : remplacement de l'interpolation osascript par des scripts temporaires avec échappement POSIX.
- **Noms d'interfaces réseau** : validation centralisée par expression régulière stricte, appliquée dans toutes les fonctions qui utilisent des noms d'interface dans des commandes.
- **Noms d'adaptateurs Windows** : échappement des apostrophes pour PowerShell.
- **Commandes PowerShell WoL** : utilisation de guillemets simples PowerShell pour les valeurs interpolées.

---

## Protection contre les fuites d'information

- **Messages d'erreur** : les messages affichés à l'utilisateur sont génériques. Les détails techniques (stderr, stack traces) sont redirigés vers les logs de debug, inactifs en production.
- **Presse-papiers** : le contenu copié (adresses IP, informations réseau) est automatiquement effacé après 30 secondes.
- **Logs de production** : tous les appels de debug sont conditionnés par le mode debug. Aucune information sensible (chemins, IP, identifiants) n'apparaît dans les logs de production.
- **Catch silencieux** : tous les blocs catch vides ont été remplacés par des logs de debug informatifs (6 blocs corrigés).

---

## Gestion des processus

### Timeout des commandes

Toutes les commandes système sont soumises à un timeout par défaut de 120 secondes. Ce timeout est configurable par commande. En cas de dépassement, une erreur est retournée proprement.

### Gestion du daemon Tailscale

Un seul processus daemon est autorisé à la fois. Le mécanisme de relance tue l'ancien processus et attend sa terminaison avant d'en lancer un nouveau. Le processus est également arrêté proprement lorsque le provider Riverpod est détruit.

### Race conditions

Plusieurs race conditions ont été identifiées et corrigées :

- La relance du daemon Tailscale est protégée par un garde contre les appels concurrents.
- L'arrêt et le redémarrage du daemon sont séquencés correctement.
- Les abonnements aux flux stdout/stderr sont stockés et annulés proprement.

---

## Validation des entrées

| Source de données | Validation appliquée |
|---|---|
| Code PIN | Regex stricte (8 chiffres exactement), validée dans la logique métier |
| Noms d'interfaces réseau | Regex stricte (alphanumérique, tirets, points, max 15 caractères) |
| URLs du daemon Tailscale | Vérification du schéma HTTPS |
| Sorties JSON du daemon | Parsing défensif avec try-catch, filtrage des données invalides |
| Noms d'adaptateurs Windows | Échappement des apostrophes pour PowerShell |
| Distribution Linux | Lecture de /etc/os-release avec fallback sur ID_LIKE pour les dérivées |
| Locales | Validation contre une liste de locales supportées (fr, en) |

---

## Stockage local

| Donnée | Mécanisme | Protection |
|---|---|---|
| Hash du PIN | SharedPreferences | PBKDF2-HMAC-SHA256, 100 000 itérations |
| Salt du PIN | SharedPreferences | Aléatoire, unique par PIN |
| Tentatives échouées | SharedPreferences | Compteur persisté, monotone |
| Préférence thème | SharedPreferences | Non sensible |

Le stockage SharedPreferences est accessible localement sans chiffrement supplémentaire. Cette limitation est mitigée par le fait que le brute force offline du hash PBKDF2 est rendu impraticable par les 100 000 itérations.

---

## Limitations connues et documentées

| Limitation | Explication | Impact |
|---|---|---|
| PIN en String Dart | Le type String est immutable en Dart. Le PIN saisi reste en mémoire quelques millisecondes jusqu'au ramasse-miettes. | Très faible. Fenêtre d'exposition minimale. |
| SharedPreferences non chiffré | Le hash et le salt du PIN sont accessibles avec les droits utilisateur local. | Mitigé par PBKDF2. Le brute force offline est impraticable. |
| Timeout ne tue pas le processus | La méthode de timeout sur Process.run ne garantit pas l'arrêt du processus enfant (limitation Dart). | Documenté. Amélioration future via Process.start. |
| TOCTOU fichiers temporaires | Entre la création et l'exécution d'un script temporaire, un processus local pourrait théoriquement le modifier. | Mitigé par les permissions 700 sur le répertoire et le script. Nécessite un accès local avec les mêmes droits utilisateur. |
| Fallback daemon sur PATH | Si le binaire chill-tailscale n'est pas trouvé aux emplacements attendus, un fallback sur le PATH système est utilisé. | Un avertissement est logué. Le binaire pourrait théoriquement être remplacé, mais cela nécessite un accès au PATH de l'utilisateur. |

---

## Résumé des audits

| Audit | Date | Résultat |
|---|---|---|
| Audit contexte architectural | Février 2026 | Cartographie complète de 12 modules, 7 acteurs, 13 limites de confiance, 6 workflows end-to-end. |
| Audit sécurité complet | Février 2026 | 38 findings : 4 critiques, 8 élevés, 14 moyens, 12 faibles. 27 corrigés, 11 mitigés ou documentés. 0 restant. 61/61 tests. |
| Audit qualité | Février 2026 | 34 findings : 6 critiques, 14 importants, 14 mineurs. Tous corrigés. 42/42 tests. |

**Verdict global** : L'architecture de sécurité repose sur un point d'exécution unique pour les commandes système, une élévation de privilèges sécurisée par scripts temporaires, et une validation rigoureuse des entrées. Les risques résiduels sont documentés et nécessitent un accès local avec les droits de l'utilisateur.
