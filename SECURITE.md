# Politique de Sécurité

## 🔒 Travail de Sécurité Réalisé

Chill a fait l'objet d'une **validation de sécurité interne approfondie** avant publication.

### Audits de Sécurité Réalisés

**Deux audits internes successifs + audit qualité :**

1. **Audit de Contexte Architectural** (méthodologie Trail of Bits - audit-context-building)
   - Cartographie ultra-granulaire de tous les modules
   - Analyse des limites de confiance et surface d'attaque
   - Analyse ligne par ligne des fonctions critiques

2. **Audit de Sécurité Complet** (méthodologie Trail of Bits - sharp-edges + audit-context-building)
   - **6 agents spécialisés** en parallèle
   - **38 findings :** 4 Critiques, 8 Élevés, 14 Moyens, 12 Faibles
   - **Tous corrigés, mitigés ou documentés**
   - **61 tests unitaires passent** après corrections

3. **Audit Qualité de la Codebase**
   - 34 problèmes identifiés et corrigés
   - 6 Critiques, 14 Importants, 14 Mineurs
   - Vulnérabilités d'injection de commandes corrigées
   - Duplication de code supprimée
   - **42 tests passent** après corrections

### Ce Que Cela Signifie

- ✅ Méthodologie de sécurité professionnelle appliquée (protocole Trail of Bits)
- ✅ Tous les problèmes identifiés corrigés ou documentés
- ✅ Vulnérabilités d'injection de commandes éliminées
- ✅ 61 tests unitaires passent (sécurité + fonctionnalité)

---

## 🛡️ Mesures de Sécurité Implémentées

### Architecture Sécurisée

**Point d'Exécution Unique :**
Toutes les commandes système passent par une classe centralisée unique (CommandRunner). Ce point d'entrée unique crée un point d'audit centralisé et facilite l'application de protections transversales :
- Timeout par défaut de 120 secondes
- Gestion des exceptions
- Séparation des arguments (liste, pas chaîne concaténée)

**Élévation de Privilèges :**
Mécanisme unique et sécurisé adapté à chaque OS :
- **Windows :** Script PowerShell temporaire exécuté via Start-Process avec verbe RunAs, paramètre -File (pas d'interprétation de commande)
- **Linux :** Script bash temporaire exécuté via pkexec (polkit), arguments passés comme liste séparée
- **macOS :** Script temporaire exécuté via osascript avec privilèges admin, protection par échappement POSIX

Scripts temporaires :
- Créés dans répertoires uniques avec permissions restrictives (700)
- Supprimés systématiquement après exécution (bloc finally)

### Authentification Locale

**Code PIN :**
- Minimum 8 chiffres (100 millions de combinaisons)
- Hashé avec **PBKDF2-HMAC-SHA256** (100 000 itérations + salt aléatoire 16 octets)
- **Comparaison en temps constant** (XOR bit à bit) prévient les attaques par timing
- Jamais stocké en clair

**Rate Limiting & Backoff Exponentiel :**
- 5 tentatives échouées → 30s de verrouillage
- 10 tentatives → 60s
- 15 tentatives → 120s
- Plafonné à 300s
- Compteur persistant après redémarrages

**Migration Automatique :**
Migration transparente depuis anciens formats de PIN (SHA-256 simple) vers format actuel (PBKDF2 + salt).

**Verrouillage par Gate UI :**
Quand PIN actif, l'intégralité de l'app est remplacée par l'écran de verrouillage jusqu'à vérification. Aucune route accessible avant saisie PIN.

---

### Configuration SSH Automatisée

Configuration SSH serveur sécurisée et automatisée par OS, regroupant toutes les opérations admin dans un seul script avec élévation. Utilisateur saisit mot de passe admin une seule fois.

**Protections Spécifiques :**
- Scripts temporaires dans répertoires uniques (noms aléatoires)
- Permissions restrictives (700 sur répertoire et script)
- Codes de sortie sémantiques (10, 20, 30, 40) pour diagnostic précis
- Vérification post-installation (service SSH actif)
- Création règle firewall seulement si aucune règle SSH existante

**Systèmes Supportés :**
- **Windows :** Installation OpenSSH via Windows Capabilities, démarrage et activation auto du service, config firewall
- **Linux :** Détection auto distro (Ubuntu, Debian, Fedora, Arch via ID_LIKE), installation via gestionnaire approprié, activation service systemd, config firewall
- **macOS :** Activation Remote Login via outils système

---

### Configuration Wake-on-LAN Automatisée

Même modèle sécurisé que SSH : un seul script avec élévation, fichiers temp sécurisés, codes de sortie sémantiques.

**Protections Spécifiques :**
- **Validation nom d'interface :** Validation stricte par regex (alphanumérique, tirets, points uniquement, max 15 chars)
- **Échappement noms d'adaptateurs :** Noms d'adaptateurs Windows échappés pour PowerShell
- **Service systemd :** Sur Linux, crée service systemd pour persistance WoL après redémarrage

---

### Intégration Tailscale

Communication avec daemon Go externe (chill-tailscale) via protocole JSON sur stdin/stdout.

**Protections Spécifiques :**
- **Validation d'URL :** URLs d'auth validées (schéma HTTPS uniquement) avant ouverture navigateur
- **Guard contre appels concurrents :** Mécanisme de verrouillage empêche relances simultanées daemon
- **Arrêt propre :** Daemon arrêté via commande JSON dédiée, timeout 3s avant arrêt forcé
- **Parsing JSON défensif :** Chaque réponse JSON parsée dans try-catch, données peers invalides filtrées silencieusement
- **Vérification binaire :** Permissions binaire daemon vérifiées au démarrage
- **Messages d'erreur génériques :** Erreurs réseau/système ne divulguent pas détails techniques à l'utilisateur (détails dans logs debug, inactifs en production)

---

### 🛡️ Onglet Sécurité OS

**Nouvelle fonctionnalité majeure :** Interface de durcissement sécurité intégrée pour l'OS de l'utilisateur.

#### 1. Toggles de Sécurité (Activer/Désactiver Protections)

Boutons on/off rapides pour activer protections OS sans terminal.

**🪟 Windows (8 toggles) :**
- Pare-feu (tous profils)
- Désactiver Bureau à distance
- Désactiver SMBv1 (protocole obsolète, vecteur WannaCry)
- Désactiver Remote Registry
- Protection anti-ransomware (Controlled Folder Access)
- Audit des connexions (succès + échecs)
- Mises à jour automatiques
- BitLocker (chiffrement disque — nécessite TPM 2.0)

**🐧 Linux (7 toggles) :**
- Pare-feu UFW
- Paramètres réseau sécurisés (protection usurpation IP, redirections...)
- Désactiver services inutiles (impression, découverte réseau...)
- Permissions fichiers sensibles (/etc/shadow, /etc/ssh...)
- Fail2Ban pour SSH (protection brute-force)
- Mises à jour automatiques de sécurité
- Désactiver login root par mot de passe

**🍎 macOS (8 toggles) :**
- Pare-feu applicatif
- Mode furtif (invisible aux scans réseau)
- FileVault (chiffrement disque)
- Désactiver partage fichiers SMB
- Mises à jour automatiques
- Saisie clavier sécurisée (protection keylogger dans Terminal)
- Gatekeeper (blocage apps non signées)
- Verrouillage écran automatique après veille

#### 2. Checkup Système (Bouton Unique)

Scan complet en lecture seule analysant l'état de sécurité du PC avec score sur 12.

**Ce qui est vérifié (12 points) :**
1. Pare-feu actif
2. Mises à jour en attente
3. Chiffrement disque (BitLocker/LUKS/FileVault)
4. Antivirus/signatures (Defender/rkhunter/XProtect)
5. Scan malware rapide
6. Programmes au démarrage
7. Tâches planifiées suspectes
8. Connexions réseau actives
9. Tentatives de connexion échouées
10. Comptes utilisateurs
11. Espace disque
12. Paramètres spécifiques OS (SMBv1/paramètres réseau/Gatekeeper)

**Résultat :** Score sur 12 + recommandations personnalisées (✅ OK, ⚠️ À vérifier, ❌ Problème détecté)

**Confidentialité :** Tout est local, rien n'est envoyé sur le réseau. 🔒

---

### Protection Contre les Injections de Commandes

L'audit a identifié et corrigé plusieurs vecteurs d'injection :

- **Élévation Windows :** Remplacement imbrication PowerShell par scripts temporaires exécutés via -File
- **Élévation macOS :** Remplacement interpolation osascript par scripts temporaires + échappement POSIX
- **Noms d'interfaces réseau :** Validation centralisée par regex stricte dans toutes les fonctions
- **Noms d'adaptateurs Windows :** Échappement apostrophes pour PowerShell
- **Commandes PowerShell WoL :** Guillemets simples PowerShell pour valeurs interpolées

---

### Protection Contre les Fuites d'Information

- **Messages d'erreur :** Messages affichés à l'utilisateur sont génériques. Détails techniques (stderr, stack traces) redirigés vers logs debug (inactifs en production)
- **Presse-papiers :** Contenu copié (adresses IP, infos réseau) automatiquement effacé après 30 secondes
- **Logs de production :** Tous appels debug conditionnés par mode debug. Aucune info sensible (chemins, IP, identifiants) dans logs production
- **Catch silencieux :** Tous blocs catch vides remplacés par logs debug informatifs (6 blocs corrigés)

---

### Gestion des Processus

**Timeout des Commandes :**
Toutes les commandes système soumises à timeout par défaut de 120 secondes (configurable par commande).

**Gestion du Daemon Tailscale :**
Un seul processus daemon autorisé à la fois. Mécanisme de relance tue ancien processus et attend terminaison avant lancement nouveau.

**Race Conditions :**
Plusieurs race conditions identifiées et corrigées :
- Relance daemon Tailscale protégée par garde contre appels concurrents
- Arrêt et redémarrage daemon séquencés correctement
- Abonnements flux stdout/stderr stockés et annulés proprement

---

## ⚠️ Limitations Connues (Documentées et Acceptées)

| Limitation | Explication | Impact |
|------------|-------------|--------|
| **Mot de passe admin dans scripts temp** | Scripts temporaires peuvent contenir commandes sensibles, bien que supprimés immédiatement après exécution. | **Faible.** Scripts créés avec permissions 700 dans répertoires uniques, supprimés dans bloc finally. |
| **PIN dans SharedPreferences** | Hash et salt PIN dans SharedPreferences (accessible sans admin mais protégés par PBKDF2). | **Mitigé.** Brute force offline impraticable avec 100 000 itérations PBKDF2. |
| **Toggles OS nécessitent admin** | Activation protections OS nécessite mot de passe admin/sudo. | **Acceptable.** Changements système nécessitent intrinsèquement élévation. |

---

## 🚨 Signaler une Vulnérabilité

**Nous prenons la sécurité au sérieux, mais comprenez nos limites en tant que projet bénévole.**

### Procédure de Divulgation Responsable

**Si vous découvrez une vulnérabilité de sécurité :**

1. **🚫 N'OUVREZ PAS d'issue publique sur GitHub**
   - Cela mettrait immédiatement tous les utilisateurs en danger
   - Les attaquants pourraient exploiter la faille avant le correctif

2. **📧 Envoyez un email privé à :**
   - **Chill_app@outlook.fr**
   - Sujet : `[SECURITY] Vulnérabilité dans Chill`

3. **📋 Incluez dans votre email :**
   - **Description :** Nature de la vulnérabilité
   - **Reproduction :** Étapes détaillées pour reproduire (PoC)
   - **Impact :** Gravité et conséquences possibles (score CVSS si possible)
   - **Preuve de concept :** Code ou démonstration (si applicable)
   - **Environnement :** Versions affectées (version Chill, version OS)
   - **Suggestions :** Correctif proposé (optionnel mais apprécié)
   - **Crédit :** Comment vous souhaitez être crédité (voir ci-dessous)

### Délais et Attentes

**Ce que vous pouvez attendre :**
- ⏱️ **Accusé de réception :** 48-72 heures (meilleur effort)
- 🔍 **Analyse initiale :** 2-6 jours
- 🛠️ **Correctif :** Selon gravité et complexité
  - **Critique :** 1-2 jours
  - **Élevé :** 3-4 jours
  - **Moyen/Faible :** 1 semaine
- 📢 **Divulgation publique :** Coordonnée avec vous après le correctif

**Ce que vous NE pouvez PAS attendre :**
- 💰 **Bug bounty :** Nous n'avons pas de budget (projet gratuit open source)
- ⚡ **SLA garantis :** Projet bénévole, pas de délais contractuels
- 👔 **Support professionnel :** Équipe de sécurité limitée (1 personne)

### Crédit et Reconnaissance Publique

**Qu'est-ce que le "crédit" ?**

Si vous trouvez une vulnérabilité et nous la signalez de manière responsable, nous vous remercierons publiquement (si vous le souhaitez).

**Options :**

**Option 1 : Reconnaissance Publique** (par défaut)
- ✅ Votre nom/pseudo mentionné dans :
  - SECURITY.md (Hall of Fame)
  - CHANGELOG.md
  - Release notes du correctif
  - Potentiellement sur les réseaux sociaux
- ✅ Bon pour votre réputation professionnelle
- ✅ Peut être ajouté sur votre CV/LinkedIn

**Option 2 : Anonyme**
- ✅ Vulnérabilité corrigée sans mention publique de qui l'a trouvée
- ✅ Votre identité reste privée

**Choisissez l'option que vous préférez dans votre email.**

### Divulgation Coordonnée

Nous suivons la **divulgation coordonnée** :

1. Vous nous signalez la vulnérabilité en privé
2. Nous travaillons sur un correctif
3. Nous vous tenons au courant de l'avancement
4. Une fois le correctif déployé et les utilisateurs notifiés
5. Nous publions les détails de la vulnérabilité (CVE si applicable)
6. Vous êtes crédité publiquement (si souhaité)

**Délai standard :** 90 jours maximum entre la découverte et la divulgation publique (suivant les pratiques de Google Project Zero).

---

## 🏆 Hall of Fame - Chercheurs en Sécurité

Ces personnes ont aidé à sécuriser Chill en signalant des vulnérabilités de manière responsable :

*(Aucune contribution pour le moment - soyez le premier !)*

**Format :**
- **Nom/Pseudo** - Description de la vulnérabilité - Gravité (Critique/Élevée/Moyenne/Faible) - Date - CVE (si applicable)

**Exemple :**
- **John Doe** - Injection de commandes dans setup SSH - Élevée - 2026-03-15 - CVE-2026-12345

---

## 📚 Ressources de Sécurité

### Sécurité SSH :
- [Guide officiel OpenSSH](https://www.openssh.com/security.html)
- [Guide de Durcissement SSH](https://www.ssh.com/academy/ssh/security)
- [Guide NIST SSH](https://nvlpubs.nist.gov/nistpubs/ir/2015/NIST.IR.7966.pdf)

### Sécurité Tailscale :
- [Modèle de Sécurité Tailscale](https://tailscale.com/security)
- [Guide ACL Tailscale](https://tailscale.com/kb/1018/acls/)
- [Chiffrement Tailscale](https://tailscale.com/blog/how-tailscale-works/)

### Sécurité Desktop :
- [OWASP Desktop App Security](https://owasp.org/www-project-desktop-app-security-top-10/)
- [Baselines Sécurité Windows](https://docs.microsoft.com/fr-fr/windows/security/threat-protection/windows-security-baselines)
- [Guide Durcissement Linux](https://www.cisecurity.org/benchmark/distribution_independent_linux)
- [Guide Sécurité macOS](https://support.apple.com/fr-fr/guide/security/welcome/web)

### Sécurité Flutter/Dart :
- [Meilleures Pratiques Sécurité Flutter](https://flutter.dev/docs/deployment/security)
- [Sécurité Dart](https://dart.dev/guides/security)

---

**Dernière mise à jour :** Février 2026  
**Version de cette politique :** 1.0
