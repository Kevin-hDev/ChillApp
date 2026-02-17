# 🖥️ CYBERSÉCURITÉ DÉFENSIVE — APPLICATIONS DESKTOP
## Catalogue complet des techniques gratuites/open source — Février 2026

> **Périmètre** : Tout ce qui concerne la sécurisation des applications desktop — Windows, macOS, Linux, frameworks (Electron, Tauri, .NET, Qt), distribution et mise à jour.
> **Outils** : Uniquement gratuits et open source.
> **Sources** : MITRE ATT&CK/D3FEND, OWASP, NIST, CIS, SANS, CISA, DEF CON/Black Hat 2024-2025.

---

## PARTIE 1 — TECHNIQUES UNIVERSELLES APPLIQUÉES AU DESKTOP

### 1.1 Authentification & Contrôle d'accès

**TOTP (Time-based One-Time Password)** — Catégorie : STOPPER — Complexité : Basique
Un code à 6 chiffres change toutes les 30 secondes. Pour les apps desktop : protéger l'accès admin, les configurations sensibles, les connexions à des services distants.
- *Outils gratuits :* Aegis (Android), FreeOTP, bibliothèques TOTP (speakeasy pour Node.js, pyotp pour Python)

**FIDO2 / WebAuthn / Passkeys** — Catégorie : STOPPER — Complexité : Intermédiaire
La méthode la plus résistante au phishing. Sur desktop : Windows Hello (intégré), Touch ID sur Mac, clés physiques USB. **Norme recommandée en 2026.**
- *Outils gratuits :* Windows Hello (intégré), Apple Passkeys (intégré), bibliothèques FIDO2

**Attaques MFA et parades** : La « fatigue MFA » (bombardement de notifications push) a permis la compromission d'Uber en 2022. Parade : number matching. Le SIM swapping se combat avec des clés physiques FIDO2.

**Zero Trust Architecture (NIST SP 800-207)** — Catégorie : STOPPER — Complexité : Avancé
« Ne jamais faire confiance, toujours vérifier ». Chaque requête est authentifiée, autorisée et chiffrée. Pour le desktop : chaque app doit vérifier l'identité, le contexte et le comportement.
- *Outils gratuits :* Tailscale (gratuit usage personnel), Pomerium (proxy Zero Trust open source)

**PAM (Privileged Access Management)** — Catégorie : STOPPER — Complexité : Avancé
Contrôle les accès des comptes à privilèges. Coffres-forts de mots de passe, rotation automatique, accès juste-à-temps (JIT).
- *Outils gratuits :* Teleport, Boundary (HashiCorp)

### 1.2 Chiffrement & Cryptographie

**Chiffrement de disque complet** — Catégorie : STOPPER — Complexité : Basique
Rend les données illisibles sans la clé de déchiffrement, crucial en cas de vol physique.
- *Windows :* BitLocker (AES-256 + TPM 2.0), **activé par défaut sous Windows 11 Pro** — GRATUIT intégré
- *macOS :* FileVault 2 (XTS-AES-128 + Secure Enclave), **activé par défaut sur Apple Silicon** — GRATUIT intégré
- *Linux :* LUKS/dm-crypt, configurable à l'installation — GRATUIT intégré

**TLS 1.3 pour les communications** — Catégorie : STOPPER — Complexité : Intermédiaire
Les apps desktop communiquent souvent avec des APIs. TLS 1.3 est obligatoire.
- *Outils gratuits :* Let's Encrypt, bibliothèques TLS natives de chaque plateforme

**Cryptographie post-quantique** — Catégorie : STOPPER — Complexité : Expert
Standards NIST 2024 : ML-KEM (FIPS 203), ML-DSA (FIPS 204), SLH-DSA (FIPS 205). Dépréciation des algorithmes vulnérables au quantique d'ici 2035.

**Gestion des secrets** — Catégorie : STOPPER — Complexité : Intermédiaire
Ne jamais stocker de secrets en clair dans l'app ou le code source.
- *Outils gratuits :* HashiCorp Vault, SOPS+Age
- *Par OS :* Windows Credential Manager (intégré), macOS Keychain (intégré), Linux Secret Service API / libsecret
- *Détection de fuites :* GitLeaks, TruffleHog, git-secrets

### 1.3 Sécurité réseau

**DNS sécurisé** — Catégorie : STOPPER/DÉTECTER — Complexité : Basique
- *Outils gratuits :* Pi-hole, NextDNS (gratuit limité), Quad9, DNSSEC

**IDS/IPS** — Catégorie : DÉTECTER — Complexité : Avancé
- *Outils gratuits :* Suricata, Snort 3, Zeek

**VPN** — Catégorie : STOPPER — Complexité : Intermédiaire
- *Gratuit :* WireGuard (~4000 lignes de code, rapide et sûr)

### 1.4 Technologies de déception

**Honeypots** — Catégorie : DÉTECTER/DÉCOURAGER — Complexité : Intermédiaire
- *Outils gratuits :* T-Pot, Cowrie (SSH/Telnet), OpenCanary, HoneyD

**Canary Tokens** — Catégorie : DÉTECTER — Complexité : Basique
- *Outil gratuit :* canarytokens.org (fichiers Word/PDF piégés, faux credentials, DNS tokens)

**Tarpits** — Catégorie : RALENTIR/DÉCOURAGER — Complexité : Basique
- **Endlessh** : tarpit SSH, piège les bots pendant des heures — gratuit

### 1.5 Bannissement & Blocage

**Fail2Ban** — Catégorie : STOPPER/BANNIR — Complexité : Basique
Bannissement automatique d'IP après X tentatives échouées. Configurable pour SSH, RDP (via logs), services web.
- *Gratuit, open source (Linux)*

**CrowdSec** — Catégorie : STOPPER/BANNIR — Complexité : Intermédiaire
Intelligence collective. **10M+ signaux/jour.** Bouncers pour nginx, nftables, Cloudflare.
- *Gratuit, open source*

**Threat Intelligence feeds gratuits** : AbuseIPDB, AlienVault OTX, abuse.ch, CISA KEV

### 1.6 Monitoring & Détection

**SIEM** — *Gratuits :* Wazuh, Elastic Security (ELK Stack)
**EDR/XDR** — *Gratuits :* Wazuh (capacités EDR), Velociraptor (DFIR)
**Sigma Rules** — Format de détection universel — *Gratuit :* SigmaHQ, Hayabusa

### 1.7 Réponse aux incidents

**Framework NIST SP 800-61** — Six phases : Préparation → Détection → Confinement → Éradication → Récupération → Retour d'expérience.
**MITRE ATT&CK + D3FEND** — 200+ techniques d'attaque mappées à 267 défenses — entièrement gratuit.
**Forensics** — *Gratuits :* Velociraptor, Volatility 3, Autopsy
**SOAR** — *Gratuit :* Shuffle SOAR

### 1.8 Supply Chain & DevSecOps

**SBOM** — *Gratuits :* Syft, Trivy, Grype. **Obligatoire sous le CRA européen dès septembre 2026.**
**Dependency scanning** — *Gratuits :* Trivy, Grype, Dependabot
**Code signing** — Voir Partie 4 pour les détails par OS
**Secret scanning** — *Gratuits :* GitLeaks, TruffleHog, git-secrets
**Sigstore/SLSA** — Signature et vérification d'artefacts — entièrement gratuit

---

## PARTIE 2 — SÉCURITÉ WINDOWS

### 2.1 Durcissement Windows — Les fondations

**ASR Rules (Attack Surface Reduction)** — Catégorie : STOPPER — Complexité : Intermédiaire
**19+ règles** de Microsoft Defender bloquant les comportements spécifiques exploités par les malwares : blocage des processus enfants Office, blocage du vol de crédentiels LSASS, protection anti-ransomware heuristique, blocage des binaires non fiables.
Microsoft rapporte **jusqu'à 40% de réduction des infections**. Trois règles prioritaires : protection LSASS, persistance WMI, pilotes signés vulnérables.
Déploiement recommandé : mode Audit pendant 30 jours, puis mode Block.
- *GRATUIT — intégré à Windows Defender*

**WDAC (Windows Defender Application Control)** — Catégorie : STOPPER — Complexité : Expert
Contrôle d'exécution au niveau noyau. Seuls les binaires, scripts et pilotes explicitement autorisés peuvent s'exécuter. Plus puissant qu'AppLocker car il opère en mode kernel.
- *Outils gratuits :* WDAC Wizard, OSconfig, PowerShell — intégré à Windows

**Credential Guard** — Catégorie : STOPPER — Complexité : Intermédiaire
Utilise la virtualisation (VBS) pour isoler les secrets LSASS dans un conteneur inaccessible au noyau OS. **Activé par défaut sur Windows 11 et Server 2025.** La contre-mesure la plus efficace contre Mimikatz.
- *GRATUIT — intégré à Windows*

**LAPS (Local Administrator Password Solution)** — Catégorie : STOPPER — Complexité : Basique
Rotation automatique du mot de passe administrateur local de chaque machine, stocké chiffré dans AD. **Intégré nativement à Windows 11 22H2+.** Élimine le mouvement latéral par mot de passe admin partagé.
- *GRATUIT — intégré à Windows*

**Windows Firewall with Advanced Security** — Catégorie : STOPPER — Complexité : Intermédiaire
Firewall intégré avec règles entrantes/sortantes par application, port, protocole. Trois profils : Domaine, Privé, Public.
- *GRATUIT — intégré à Windows*

**Core Isolation / Memory Integrity (HVCI)** — Catégorie : STOPPER — Complexité : Basique
Protection au niveau hyperviseur. Virtualisation-Based Security (VBS) qui isole les processus critiques.
- *GRATUIT — intégré à Windows 11*

**Windows Sandbox** — Catégorie : STOPPER — Complexité : Basique
Environnement jetable pour tester des fichiers suspects. Se réinitialise à chaque fermeture.
- *GRATUIT — intégré à Windows 10/11 Pro*

### 2.2 Active Directory — Le joyau de la couronne

**Modèle d'administration par tiers** — Catégorie : STOPPER — Complexité : Avancé
Segmente les privilèges en trois niveaux étanches :
- **Tier 0 :** Contrôleurs de domaine, PKI, identité. Les admins Tier 0 ne se connectent QU'aux systèmes Tier 0.
- **Tier 1 :** Serveurs d'entreprise et applications.
- **Tier 2 :** Postes de travail et périphériques.
Principe clé : une compromission à un niveau inférieur ne remonte PAS au niveau supérieur.

**Contre-mesures Kerberoasting** — Catégorie : STOPPER/DÉTECTER — Complexité : Intermédiaire
L'attaque exploite les tickets Kerberos chiffrés en RC4 pour craquer les mots de passe des comptes de service.
Parades :
- Mots de passe de 25+ caractères pour les comptes de service
- Utilisation de **gMSA** (Group Managed Service Accounts, rotation automatique)
- Forçage du chiffrement AES256
- Placement des comptes sensibles dans le groupe **Protected Users** (force AES, interdit la délégation, réduit la durée des TGT à 4h)
- Surveillance de l'Event ID 4769

**Contre-mesures Golden Ticket** — Catégorie : STOPPER/DÉTECTER — Complexité : Expert
L'attaque forge des TGT avec le hash KRBTGT, donnant un accès total au domaine pour 10 ans.
Parade critique : **réinitialiser le mot de passe KRBTGT deux fois** avec un intervalle de 12-24h.
Compléter avec : modèle Tiered Admin, Credential Guard, monitoring des Event IDs 4768-4771, détection des durées de tickets anormales.

**Vulnérabilités ADCS (ESC1-ESC8)** — Catégorie : STOPPER — Complexité : Expert
Les services de certificats AD présentent des vulnérabilités de configuration permettant l'escalade de privilèges vers Domain Admin.
- ESC1 (templates avec SAN modifiable) et ESC8 (relais NTLM vers l'enrollment web) sont les plus exploitées
- Parades : Audit de tous les templates, suppression de `ENROLLEE_SUPPLIES_SUBJECT`, activation d'EPA sur IIS
- *Outils d'audit gratuits :* **Certipy** (Python, open source), **PSPKIAudit** (PowerShell, open source), **Locksmith** (open source)

**Outils d'évaluation AD (tous gratuits) :**
- **BloodHound CE** : cartographie graphique des chemins d'attaque dans AD/Entra ID. *Les attaquants l'utilisent — les défenseurs doivent l'utiliser d'abord.* Open source.
- **PingCastle** : évaluation rapide de la santé AD, scoring CMMI, 70+ règles intégrées. Gratuit.
- **Purple Knight** (Semperis) : gratuit, 185+ indicateurs de sécurité, score moyen initial des organisations : 61%.

### 2.3 Menaces Windows et parades

**Contre-mesures Mimikatz** — Catégorie : STOPPER — Complexité : Intermédiaire
Mimikatz est l'outil #1 de vol de credentials en mémoire. Trois niveaux de protection cumulatifs :
1. **RunAsPPL** (LSA Protection) : protège LSASS en tant que processus protégé. Registre : `HKLM\SYSTEM\CurrentControlSet\Control\Lsa\RunAsPPL = 1` — GRATUIT
2. **Credential Guard** (VBS) : isolation virtualisée des secrets — GRATUIT (intégré Windows 11)
3. **ASR Rule** « Block credential stealing from LSASS » : blocage au niveau Defender — GRATUIT

**Sécurité PowerShell** — Catégorie : STOPPER/DÉTECTER — Complexité : Intermédiaire
PowerShell est massivement utilisé par les attaquants. Quatre contrôles essentiels (tous gratuits, intégrés) :
- **AMSI** (Antimalware Scan Interface) : analyse le contenu des scripts avant exécution, même après dé-obfuscation
- **Script Block Logging** (Event ID 4104) : journalise tout le code PowerShell exécuté
- **Constrained Language Mode** (CLM) : restreint PowerShell, empêchant l'accès .NET/COM
- **Suppression de PowerShell v2** : `Remove-WindowsFeature PowerShell-V2` — la v2 n'a AUCUNE protection

**LOLBins (Living Off The Land Binaries)** — Catégorie : DÉTECTER — Complexité : Avancé
Binaires Windows légitimes (certutil, mshta, rundll32, regsvr32) détournés pour télécharger et exécuter du code malveillant. C'est l'une des techniques les plus utilisées car ces binaires sont signés Microsoft.
- Parades : WDAC, ASR rules, Sysmon (Event ID 1 avec ligne de commande), règles Sigma
- *Référence gratuite :* projet LOLBAS (lolbas-project.github.io)

**Ransomware — Protections Windows** — Catégorie : STOPPER — Complexité : Intermédiaire
- **Controlled Folder Access** : empêche les applications non autorisées de modifier les fichiers dans des dossiers protégés — GRATUIT (Defender)
- **ASR Rules anti-ransomware** : blocage heuristique — GRATUIT
- Sauvegardes immuables (voir Partie 5)

**NTLM Relay Attacks** — Catégorie : STOPPER — Complexité : Avancé
- **EPA (Extended Protection for Authentication)** : empêche le relais NTLM
- **SMB Signing** : obligatoire sur tous les serveurs
- **LDAP Signing + Channel Binding** : empêche le relais vers AD
- Tous configurables gratuitement via GPO

**Macros Office malveillantes** — Catégorie : STOPPER — Complexité : Basique
Microsoft bloque par défaut les macros VBA dans les fichiers téléchargés depuis Internet depuis 2022.
- Politique recommandée : bloquer TOUTES les macros sauf celles signées numériquement — configurable gratuitement via GPO

### 2.4 Outils de surveillance Windows (tous gratuits)

**Sysmon** — Catégorie : DÉTECTER — Complexité : Intermédiaire
Journalisation avancée au-delà des capacités natives de Windows. Events clés : création de processus (ID 1), connexions réseau (ID 3), accès LSASS (ID 10), requêtes DNS (ID 22).
- *Configuration recommandée :* **SwiftOnSecurity sysmon-config** (open source) comme base, personnalisée par environnement
- GRATUIT (Microsoft Sysinternals)

**Windows Event Forwarding (WEF)** — Catégorie : DÉTECTER — Complexité : Intermédiaire
Transfert natif de logs sans agent, intégré à Windows. 2 000-4 000 clients par collecteur.
- GRATUIT — intégré à Windows

**Suite Sysinternals (tous gratuits)** :
- **Autoruns** : inventaire complet de tout ce qui démarre automatiquement
- **Process Explorer** : gestionnaire de processus avancé
- **Process Monitor** : surveillance en temps réel des fichiers/registre/réseau
- **TCPView** : connexions réseau en temps réel

**HardenTools** — Catégorie : STOPPER — Complexité : Basique
Hardening Windows en un clic : désactive les fonctionnalités dangereuses (macros, WSH, PowerShell pour les non-admins, etc.)
- Open source, gratuit

### 2.5 Sécurité de l'accès distant Windows

**Durcissement RDP** — Catégorie : STOPPER — Complexité : Basique à Intermédiaire
- **NLA (Network Level Authentication)** : authentification AVANT la session graphique, bloque les attaques pré-authentification comme BlueKeep — GRATUIT (intégré)
- **Remote Credential Guard** : les identifiants ne quittent jamais la machine source — GRATUIT (intégré)
- **Règle d'or :** ne JAMAIS exposer RDP directement sur Internet
- Configurer via GPO, gratuit

**SSH sur Windows** — Catégorie : STOPPER — Complexité : Basique
OpenSSH est intégré nativement à Windows depuis Windows 10 1809.
- Même bonnes pratiques que SSH Linux : clés Ed25519, pas de passwords, ssh-audit

**WinRM/PSRemoting** — Catégorie : STOPPER — Complexité : Intermédiaire
- Toujours utiliser HTTPS (pas HTTP)
- Certificats TLS pour l'authentification
- Restreindre via GPO les machines autorisées

---

## PARTIE 3 — SÉCURITÉ macOS

### 3.1 Protections intégrées Apple (toutes gratuites)

**Gatekeeper** — Catégorie : STOPPER — Complexité : Basique
Bloque l'exécution des applications non signées et non notariées. **macOS Sequoia (septembre 2024) a supprimé le contournement par clic droit**, réduisant drastiquement l'efficacité des infostealers — 95% des détections de stealers survenaient avant cette mise à jour.
- GRATUIT — intégré à macOS

**XProtect + XProtect Remediator** — Catégorie : DÉTECTER/STOPPER — Complexité : Basique
Antimalware intégré utilisant des signatures YARA, mis à jour automatiquement indépendamment de l'OS. XProtect Remediator effectue des scans périodiques actifs.
- GRATUIT — intégré à macOS

**SIP (System Integrity Protection)** — Catégorie : STOPPER — Complexité : Basique
Empêche même root de modifier les fichiers système protégés. Ne peut être désactivé que via le mode Recovery.
- GRATUIT — intégré à macOS

**TCC (Transparency, Consent and Control)** — Catégorie : STOPPER — Complexité : Basique
Contrôle par application l'accès aux ressources sensibles : caméra, micro, localisation, fichiers, enregistrement d'écran.
- GRATUIT — intégré à macOS

**Lockdown Mode** — Catégorie : STOPPER — Complexité : Basique
Mode de sécurité extrême désactivant : la plupart des pièces jointes, la compilation JIT JavaScript, les connexions FaceTime d'inconnus, les profils de configuration. Conçu pour les cibles à haut risque.
- GRATUIT — intégré à macOS/iOS

**FileVault** — Catégorie : STOPPER — Complexité : Basique
Chiffrement disque complet. Activé par défaut sur Apple Silicon. XTS-AES-128 + Secure Enclave.
- GRATUIT — intégré à macOS

**mSCP (macOS Security Compliance Project)** — Catégorie : STOPPER/DÉTECTER — Complexité : Intermédiaire
Projet open source de NIST, NASA et DISA. Génère des profils de configuration, scripts d'audit et de remédiation alignés sur NIST SP 800-53, CIS Benchmarks et DISA STIG.
- GRATUIT — open source

### 3.2 Menaces macOS 2024-2026

**Augmentation de 400% des menaces macOS** entre 2023 et 2024 (Red Canary), et **+101% des infostealers** sur les deux derniers trimestres 2024 (Palo Alto Unit 42).

- **Atomic Stealer (AMOS)** : le plus prolifique. Vole le trousseau Keychain, données des navigateurs, portefeuilles crypto. Utilise des dialogues AppleScript pour piéger l'utilisateur.
- **Banshee Stealer** : a « volé » l'algorithme de chiffrement XProtect d'Apple pour échapper à la détection pendant 2+ mois. Code source fuité en novembre 2024, variantes prolifèrent.

### 3.3 Outils de sécurité macOS (tous gratuits/open source)

**Google Santa** — Catégorie : STOPPER — Complexité : Intermédiaire
Autorisation binaire en mode allowlist/blocklist. Mode MONITOR ou LOCKDOWN. Équivalent de WDAC pour macOS.
- Open source (Google)

**LuLu (Objective-See)** — Catégorie : DÉTECTER/STOPPER — Complexité : Basique
Pare-feu applicatif. Bloque les connexions sortantes inconnues. Alerte quand une app essaie de se connecter à Internet.
- Gratuit, open source

**BlockBlock (Objective-See)** — Catégorie : DÉTECTER — Complexité : Basique
Surveille les emplacements de persistance (LaunchAgents/LaunchDaemons) et alerte lors de toute installation de persistence.
- Gratuit, open source

**KnockKnock (Objective-See)** — Catégorie : DÉTECTER — Complexité : Basique
« AutoRuns pour macOS » — inventaire complet de tous les éléments persistants installés sur le système.
- Gratuit, open source

**osquery** — Catégorie : DÉTECTER — Complexité : Intermédiaire
Interrogation du système en SQL. Cross-platform (macOS, Linux, Windows). Permet de poser des questions comme « quels processus écoutent sur un port ? » ou « quels fichiers ont été modifiés récemment ? »
- Open source (originalement Facebook)

---

## PARTIE 4 — SÉCURITÉ DES FRAMEWORKS DESKTOP

### 4.1 Electron — Le framework le plus ciblé

Electron = Chromium + Node.js. Utilisé par VS Code, Discord, Slack, Signal Desktop, etc. La surface d'attaque est énorme car Node.js a un accès complet au système.

**Baseline de sécurité obligatoire** (par défaut depuis Electron 12-20+) :
- `contextIsolation: true` — isole le code web des API Electron. **CRITIQUE : si désactivé, une XSS = accès total au système.**
- `nodeIntegration: false` — empêche l'accès Node.js depuis le contenu web
- `sandbox: true` — sandbox Chromium au niveau OS
- CSP restrictive pour prévenir le XSS
- Communication uniquement via `contextBridge.exposeInMainWorld()` — jamais d'accès direct aux API Node.js

**Erreurs critiques à éviter dans Electron :**
- JAMAIS `nodeIntegration: true` en production
- JAMAIS `contextIsolation: false`
- JAMAIS charger de contenu distant sans CSP
- JAMAIS `webSecurity: false`
- JAMAIS `allowRunningInsecureContent: true`
- Toujours valider les entrées dans le main process

- *Outil d'audit gratuit :* **Electronegativity** (scan automatique des problèmes de sécurité dans les apps Electron)

### 4.2 Tauri — L'alternative sécurisée par défaut

Architecture Rust + WebView natif OS (pas de Chromium embarqué). **Tout est verrouillé par défaut** : chaque API (fichiers, réseau, shell, etc.) doit être explicitement autorisée via un système de capabilities dans le fichier de configuration.

Avantages sécurité vs Electron :
- Pas de Node.js = pas d'accès système par défaut
- Capabilities déclaratives = surface d'attaque minimale
- Rust = pas de buffer overflows, pas de use-after-free
- Installeurs ~10 Mo (vs ~150 Mo Electron)
- Mémoire ~30-40 Mo au repos (vs ~200+ Mo Electron)

Tauri v2 (fin 2024) avec croissance d'adoption de **35% par an**.
- Entièrement gratuit et open source

### 4.3 Sécurité .NET / WPF / WinForms (Windows natif)

- **Code Access Security** est obsolète — ne pas s'y fier
- Utiliser **ClickOnce** avec signature pour la distribution
- Obfuscation avec **ConfuserEx** (open source) ou **dnSpy** pour le reverse (test)
- Ne jamais stocker de secrets dans le code IL (facilement décompilable avec ILSpy/dnSpy)
- Utiliser Windows Data Protection API (DPAPI) pour stocker les secrets localement

### 4.4 Signature de code — Par plateforme

**Windows : Authenticode** — Catégorie : STOPPER — Complexité : Intermédiaire
- SmartScreen reputation : les applications signées avec un certificat EV ont une meilleure réputation
- Les certificats EV sont payants, MAIS la signature de base est possible avec des certificats auto-signés pour le développement
- **signtool.exe** : outil de signature intégré au Windows SDK (gratuit)
- Pour la distribution : un certificat de signature est nécessaire (coût variable)

**macOS : Developer ID + notarisation** — Catégorie : STOPPER — Complexité : Intermédiaire
- Obligatoire pour que Gatekeeper accepte l'application
- Compte Apple Developer requis (99$/an — c'est le seul coût)
- **codesign** et **notarytool** : outils intégrés à Xcode (gratuit)

**Linux : GPG** — Catégorie : STOPPER — Complexité : Basique
- Signature GPG des paquets .deb/.rpm
- AppImage peut être signé
- Entièrement gratuit

**TUF (The Update Framework)** — Catégorie : STOPPER — Complexité : Avancé
Protège contre la compromission de clés, le rollback et les attaques mix-and-match lors des mises à jour automatiques. Adopté par PyPI, Docker, RubyGems.
- Open source, gratuit

---

## PARTIE 5 — SÉCURITÉ LINUX DESKTOP

### 5.1 Durcissement Linux Desktop

**sysctl hardening** — Catégorie : STOPPER — Complexité : Intermédiaire
Paramètres critiques : `kernel.randomize_va_space=2` (ASLR), `kernel.kptr_restrict=2`, SYN cookies, désactivation du routage IP, restriction de ptrace.

**AppArmor** (Ubuntu/Debian) — Catégorie : STOPPER — Complexité : Intermédiaire
Contrôle basé sur les chemins. **AppArmor 4.0** dans Ubuntu 24.04 LTS avec restrictions réseau. Mode apprentissage avec `aa-genprof`.

**SELinux** (RHEL/Fedora) — Catégorie : STOPPER — Complexité : Avancé
Contrôle basé sur les labels. Développé par la NSA. Extrêmement granulaire mais complexe.

**Durcissement systemd** — Sandboxing par service : `ProtectSystem=strict`, `ProtectHome=yes`, `PrivateTmp=yes`, `NoNewPrivileges=yes`.

**Durcissement SSH** — Clés Ed25519, `PasswordAuthentication no`, `PermitRootLogin no`.
- *Audit :* **ssh-audit** (gratuit)

**Firejail / Bubblewrap** — Catégorie : STOPPER — Complexité : Intermédiaire
Sandboxing d'applications desktop Linux. Firejail supporte des profils prédéfinis pour Firefox, Chrome, LibreOffice, etc.
- Gratuits, open source

### 5.2 Outils de sécurité Linux Desktop (tous gratuits)

| Outil | Catégorie | Description |
|-------|-----------|-------------|
| **Wazuh** | DÉTECTER | SIEM + XDR complet |
| **Falco** | DÉTECTER | Surveillance eBPF des appels système |
| **Tetragon** | DÉTECTER/STOPPER | eBPF avec enforcement temps réel |
| **Lynis** | DÉTECTER | Audit de durcissement, aligné CIS Benchmarks |
| **Auditd** | DÉTECTER | Framework d'audit noyau |
| **AIDE** | DÉTECTER | Monitoring d'intégrité de fichiers |
| **ClamAV** | DÉTECTER | Antivirus open source |
| **rkhunter/chkrootkit** | DÉTECTER | Détection de rootkits |
| **Fail2Ban** | BANNIR | Bannissement automatique d'IP |
| **CrowdSec** | BANNIR | Intelligence collective |
| **Endlessh** | RALENTIR | Tarpit SSH |
| **fwknop** | STOPPER | Single Packet Authorization |

---

## PARTIE 6 — TECHNIQUES AVANCÉES POUR LE DESKTOP

### 6.1 eBPF pour la sécurité

L'eBPF permet d'exécuter du code dans le noyau Linux sans modifier le kernel. **100% de taux de détection avec 0% de faux positifs** (RITECH 2025). Tous gratuits :
- **Falco** : détection runtime
- **Tetragon** : observabilité + enforcement en temps réel
- **Tracee** : traçage profond pour la forensique
- **Cilium** : réseau eBPF

### 6.2 Red Team / Tests de sécurité (gratuits)

- **MITRE Caldera** : émulation d'adversaires automatisée, 527 procédures
- **Atomic Red Team** : 1225+ tests atomiques mappés à 261 techniques ATT&CK
- **Infection Monkey** : BAS auto-propagatif qui teste le mouvement latéral et la segmentation

### 6.3 Threat Intelligence (gratuit)

- **MISP** : plateforme de partage d'IOCs
- **OpenCTI** (ANSSI) : gestion de connaissances CTI
- *Feeds :* AlienVault OTX, abuse.ch, CISA KEV

### 6.4 Sauvegarde

**Règle 3-2-1-1-0** : 3 copies, 2 médias, 1 hors-site, 1 immuable, 0 erreur.
**96% des attaques ransomware ciblent les sauvegardes.**

---

## PARTIE 7 — CADRE RÉGLEMENTAIRE 2025-2026

### NIST CSF 2.0 (février 2024)
Six fonctions : **Gouverner** (nouveau), Identifier, Protéger, Détecter, Répondre, Récupérer. Gratuit.

### Directive NIS2 (octobre 2024)
18 secteurs. Notification 24h. **Amendes : 10M€ ou 2% CA mondial.**

### EU Cyber Resilience Act (CRA)
- **Septembre 2026 :** signaler les vulnérabilités sous 24h
- **Décembre 2027 :** SBOM obligatoire pour tout produit numérique en UE
**Concerne directement les applications desktop vendues/distribuées en Europe.**

### ISO 27001:2022
93 contrôles, 4 thèmes. Nouveaux contrôles cloud et threat intelligence.

---

## RÉCAPITULATIF — OUTILS GRATUITS ESSENTIELS POUR LE DESKTOP

| Besoin | Outil(s) gratuit(s) | OS |
|--------|---------------------|-----|
| Chiffrement disque | BitLocker, FileVault, LUKS | Win/Mac/Linux |
| Firewall | Windows Firewall, LuLu, nftables | Win/Mac/Linux |
| Anti-malware | Defender+ASR, XProtect, ClamAV | Win/Mac/Linux |
| Whitelisting apps | WDAC, Santa, AppArmor | Win/Mac/Linux |
| Détection persistance | Autoruns/Sysmon, BlockBlock/KnockKnock, Auditd | Win/Mac/Linux |
| Vol de credentials | Credential Guard, RunAsPPL, ASR | Windows |
| Audit AD | BloodHound CE, PingCastle, Purple Knight | Windows |
| Audit sécurité AD certs | Certipy, PSPKIAudit, Locksmith | Windows |
| PowerShell sécurité | AMSI, CLM, Script Block Logging | Windows |
| Hardening rapide | HardenTools | Windows |
| Sandbox test | Windows Sandbox | Windows |
| Compliance macOS | mSCP | macOS |
| Sandbox apps | Firejail, Bubblewrap | Linux |
| SIEM/XDR | Wazuh, Elastic Security | Tous |
| Forensics | Velociraptor, Volatility 3, Autopsy | Tous |
| Scanner vulns | Trivy, Grype, Lynis | Tous |
| SBOM | Syft + Grype | Tous |
| Audit Electron | Electronegativity | Tous |
| Bannissement | CrowdSec, Fail2Ban | Linux |
| Tarpit SSH | Endlessh | Linux |
| Threat Intel | MISP, OpenCTI | Tous |
