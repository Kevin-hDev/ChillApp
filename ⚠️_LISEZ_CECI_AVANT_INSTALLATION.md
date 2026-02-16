# ⚠️ LISEZ CECI EN PREMIER

**Avant d'installer ou d'utiliser Chill (Application Desktop)**

---

## 🔴 Informations de Sécurité Critiques

### Cette Application Nécessite des Privilèges Administrateur

Chill a besoin de permissions élevées (admin/sudo/root) pour configurer des paramètres système :
- Configuration du pare-feu
- Installation et gestion du serveur SSH
- Configuration des interfaces réseau pour Wake-on-LAN
- Renforcement de la sécurité système (Onglet Sécurité OS)
- Gestion du chiffrement de disque (BitLocker/LUKS/FileVault)

**⚠️ Ne donnez jamais l'accès administrateur à un logiciel auquel vous ne faites pas confiance.**

---

## 🛡️ Ce Que Nous Avons Fait pour Mériter Votre Confiance

### Audits de Sécurité Professionnels

**Deux audits internes successifs + audit qualité :**
- Cartographie architecturale complète (méthodologie Trail of Bits)
- **38 découvertes de sécurité** (4 Critiques, 8 High, 14 Medium, 12 Low)
- **Tous les problèmes corrigés ou documentés**
- **61 tests unitaires passent** après corrections
- Vulnérabilités d'injection de commandes éliminées
- Protections contre les fuites d'informations implémentées

**Détails :** Voir [SECURITE.md](SECURITE.md) pour le rapport d'audit complet.

### Open Source & Auditable

- **Licence :** GNU General Public License v3.0 (GPL v3)
- **Code source :** Publiquement disponible sur GitHub (après publication)
- **Pas de télémétrie :** Tout reste sur votre machine 🔒
- **Pas de fonctionnalités cachées :** Ce que vous voyez est ce que vous obtenez
- **Auditable par la communauté :** Tout le monde peut examiner le code

---

## 📋 Prérequis Système

### Systèmes d'Exploitation Supportés

| OS | Version | Notes |
|----|---------|-------|
| **Windows** | 10/11 | PowerShell 5.1+ requis |
| **Linux** | Ubuntu 20.04+, Debian 11+, Fedora 35+, Arch | systemd requis |
| **macOS** | 11+ (Big Sur et ultérieur) | Rosetta 2 pour Apple Silicon |

### Permissions Requises

- **Accès administrateur/sudo** pour la configuration système
- **Accès réseau** pour les connexions SSH
- **Accès disque** pour le stockage des clés SSH

---

## ⚙️ Ce Que Fait Cette Application

### Fonctionnalités Principales

1. **Assistant de Configuration SSH**
   - Installation automatisée du serveur SSH par OS
   - Génération et gestion de clés (Ed25519 préféré)
   - Stockage sécurisé des clés avec chiffrement
   - Vérification des clés d'hôte (TOFU - Trust On First Use)

2. **Configuration Wake-on-LAN**
   - Détection des interfaces réseau
   - Configuration des adresses MAC
   - Test des paquets WoL
   - Lié aux connexions SSH pour réveil transparent

3. **Intégration Tailscale**
   - Configuration du réseau VPN mesh
   - Connexions pair-à-pair sécurisées
   - Communication avec daemon Go externe (chill-tailscale)
   - Validation URL et flux d'authentification

4. **Onglet Sécurité OS** 🆕
   - **Toggles de Sécurité :** Activer/désactiver les protections OS en un clic
     - Windows : Pare-feu, Anti-ransomware, BitLocker, Désactiver Remote Desktop, etc.
     - Linux : UFW, Fail2Ban, Paramètres réseau sécurisés, Permissions fichiers, etc.
     - macOS : Pare-feu, FileVault, Gatekeeper, Mode furtif, etc.
   - **Checkup Système :** Scan de sécurité 12 points avec score et recommandations
     - État pare-feu, mises à jour en attente, chiffrement disque, antivirus, scan malware, etc.
   - **100% Local :** Aucune donnée envoyée sur le réseau

### Application Compagnon

**Chill fonctionne avec ChillShell (app mobile) :**
- ChillShell (Android/iOS) : Client terminal SSH distant
- Chill (Desktop) : Assistant de configuration PC
- Ensemble : Système complet d'accès distant sécurisé

---

## 🚨 Limitations Connues (Compromis Acceptés)

| Limitation | Impact | Atténuation |
|------------|--------|-------------|
| **Mot de passe admin dans scripts temp** | Scripts élevés peuvent contenir commandes sensibles | 🟢 Faible. Scripts avec permissions 700, supprimés immédiatement dans bloc finally |
| **PIN dans SharedPreferences** | Hash PIN accessible sans admin (protégé par PBKDF2) | 🟡 Atténué. 100 000 itérations PBKDF2 rendent le brute force hors ligne impraticable |
| **Toggles sécurité OS nécessitent admin** | Changements système nécessitent élévation | ✅ Acceptable. Inhérent aux modifications système |

**Détails complets :** [SECURITE.md - Limitations Connues](SECURITE.md#️-limitations-connues-documentées-et-acceptées)

---

## 📜 Licence : GPL v3 (Copyleft)

**Ce que cela signifie pour vous :**

✅ **Vous POUVEZ :**
- Utiliser Chill gratuitement (personnel ou commercial)
- Étudier et modifier le code source
- Redistribuer des versions modifiées

⚠️ **Vous DEVEZ :**
- Garder gratuit et open source (GPL v3)
- Fournir le code source si vous distribuez des modifications
- Créditer les auteurs originaux

❌ **Vous NE POUVEZ PAS :**
- Fermer le code source
- Utiliser une licence propriétaire
- Supprimer les notices de copyright

**Pourquoi GPL v3 ?** Nous voulons que Chill reste libre et ouvert pour toujours. Tout le monde peut l'utiliser, mais personne ne peut le transformer en logiciel commercial fermé.

**Licence complète :** [LICENSE](LICENSE)

---

## 🔐 Contact Sécurité

**Vous avez trouvé une vulnérabilité ?**

🚫 **NE PAS ouvrir une issue GitHub publique** (met en danger tous les utilisateurs)

📧 **Email privé :** Chill_app@outlook.fr
Sujet : `[SECURITY] Vulnérabilité dans Chill`

**Divulgation coordonnée :** Timeline 90 jours, crédit dans Hall of Fame (optionnel)

**Détails :** [SECURITE.md - Signaler une Vulnérabilité](SECURITE.md#-signaler-une-vulnérabilité)

---

## 📚 Documentation

Avant d'utiliser Chill :
1. **Commencez ici :** ⚠️_LISEZ_CECI_AVANT_INSTALLATION.md (vous êtes ici)
2. **Détails sécurité :** [SECURITE.md](SECURITE.md)
3. **Contribuer :** [CONTRIBUTING.md](CONTRIBUTING.md)
4. **Historique versions :** [CHANGELOG.md](CHANGELOG.md)
5. **Feuille de route :** [ROADMAP.md](ROADMAP.md)

---

## ✅ Prêt à Installer ?

Si vous comprenez et acceptez :
- Le besoin de privilèges administrateur
- Les limitations connues et compromis
- Les termes de la licence GPL v3
- Les considérations de sécurité

**Alors procédez à l'installation.**

Instructions détaillées : [README.md](README.md)

---

## 🤝 Communauté

- **Issues :** GitHub Issues (pour bugs et demandes de fonctionnalités)
- **Sécurité :** Chill_app@outlook.fr (rapports de sécurité privés uniquement)
- **Contributions :** Voir [CONTRIBUTING.md](CONTRIBUTING.md)

---

**Dernière mise à jour :** Février 2026
**Version Chill :** Consultez [CHANGELOG.md](CHANGELOG.md) pour la version actuelle
