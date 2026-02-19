L'audit de securite (offensive + defensive) a identifie 58 failles dans ChillApp     
     et genere 58 corrections de code en Dart. Ces corrections sont du code de
     reference qui doit etre adapte et integre dans le vrai projet sans rien casser.

     Probleme : On ne peut pas tout faire d'un coup. Il faut proceder par etapes,
     tester a chaque fois, et commencer par ce qui est le plus dangereux.

     Approche : 5 sprints progressifs, du plus critique au moins urgent. Chaque sprint
     produit un commit testable et stable.

     Execution : Opus 4.6 supervise et coordonne. Des agents Sonnet 4.6 sont delegues
     pour coder les corrections. Opus verifie le travail apres chaque sprint via code
     review.

     ---
     Etape 0 — Preparation (prerequis avant tout)

     But : Mettre de l'ordre et etablir une base saine.

     Actions

     1. Corriger les dossiers de code : Les codes P3 (Runtime) et P4 (Framework) n'ont
     pas ete copies correctement. Copier depuis .defender_working/ vers les bons
     dossiers
     2. Creer le dossier lib/core/security/ (nouveau module securite)
     3. Lancer les tests existants (flutter test) pour verifier que tout passe AVANT de
      toucher quoi que ce soit — c'est notre "photo avant"
     4. Creer une branche git feature/security-hardening pour isoler les changements

     Fichiers concernes

     - Source : docs/TEST_HACK_RED_TEAM/Defensive_Report/.defender_working/CHILLAPP_202
     60218_153000/code/
     - Destination : docs/TEST_HACK_RED_TEAM/Defensive_Report/code/ (reorganiser)
     - Nouveau dossier : lib/core/security/

     Verification

     - flutter test passe a 100%
     - Branche git creee et propre

     ---
     Sprint 1 — Fondations critiques (P0)

     But : Bloquer les 3 chaines d'attaque les plus dangereuses.
     Risque : MOYEN (on touche a lock_provider.dart)
     Duree estimee : 2-3 sessions

     Ce qu'on bloque

     - CHAIN-001 : Un attaquant peut lire le fichier SharedPreferences, supprimer le
     PIN, et prendre le controle total
     - CHAIN-002 : Le daemon Go peut etre remplace par un imposteur sans que personne
     ne le detecte
     - CHAIN-003 : Un agent IA peut automatiser l'attaque complete en moins d'1 heure

     Sous-etapes (dans cet ordre strict)

     1.1 — SecureBytes (FIX-001) — Risque FAIBLE

     - Quoi : Nouveau fichier lib/core/security/secure_memory.dart
     - Pourquoi : Les secrets (PIN) restent en memoire meme apres usage. Cette classe
     les efface proprement
     - Impact : AUCUN changement dans le code existant (nouveau fichier seulement)
     - Source : .defender_working/.../code/blindage_code/fix_001_secure_memory.dart
     - Test : Adapter test_fix_001.dart dans test/unit/security/

     1.2 — SecureStorage (FIX-027) — Risque ELEVE ⚠️

     - Quoi : Nouveau fichier lib/core/security/secure_storage.dart + MODIFIER
     lib/features/lock/lock_provider.dart
     - Pourquoi : Le PIN est stocke en texte clair dans SharedPreferences. On le migre
     vers le coffre-fort de l'OS (Keychain macOS, Credential Manager Windows, libsecret
      Linux)
     - Impact : C'est LE changement le plus risque — il touche au systeme de PIN. Il
     faut :
       a. D'abord creer SecureStorage (nouveau fichier)
       b. Ajouter une logique de migration dans lock_provider.dart (lire ancien format
     SharedPrefs → ecrire dans SecureStorage → supprimer de SharedPrefs)
       c. Garder un fallback temporaire si SecureStorage echoue
     - Source :
     .defender_working/.../code/blindage_reseau_crypto/.../fix_027_secure_storage.dart
     - Test : Tests du PIN existants (test/unit/lock_test.dart) DOIVENT toujours passer
      + nouveaux tests SecureStorage
     - Commit : Apres cette sous-etape, commit immediat

     1.3 — Integrite du daemon (FIX-014) — Risque FAIBLE

     - Quoi : Nouveau fichier lib/core/security/daemon_integrity.dart
     - Pourquoi : Le daemon Go est lance sans verifier si c'est le bon binaire. On
     ajoute un controle SHA-256
     - Impact : Modification mineure dans le provider Tailscale pour appeler la
     verification avant Process.start()
     - Source :
     .defender_working/.../code/blindage_framework/fix_008_011_startup_security.dart
     (partie integrite)

     1.4 — IPC authentifie (FIX-012) — Risque MOYEN

     - Quoi : Nouveau fichier lib/core/security/ipc_auth.dart
     - Pourquoi : La communication app ↔ daemon est en JSON clair sans
     authentification. On ajoute HMAC-SHA256
     - Impact : Les messages IPC devront inclure un tag HMAC. Le daemon Go devra aussi
     etre mis a jour (plus tard)
     - Source : .defender_working/.../code/blindage_framework/fix_012_035_ipc_auth.dart

     1.5 — Chiffrement IPC (FIX-035) — Risque FAIBLE

     - Quoi : Nouveau fichier lib/core/security/ipc_encryption.dart
     - Pourquoi : Chiffrer les messages entre l'app et le daemon (Encrypt-then-MAC)
     - Impact : Depend de FIX-012. Nouveau fichier, pas de modif existante
     - Source :
     .defender_working/.../code/blindage_reseau_crypto/.../fix_035_ipc_encryption.dart

     1.6 — Fail Closed (FIX-032) — Risque FAIBLE

     - Quoi : Nouveau fichier lib/core/security/fail_closed.dart
     - Pourquoi : Si le daemon plante, l'app ne doit jamais essayer un fallback non
     securise. Circuit breaker
     - Impact : Nouveau fichier. Integration dans le flux de connexion SSH
     - Source :
     .defender_working/.../code/blindage_reseau_crypto/.../fix_032_fail_closed.dart

     1.7 — SSH algorithmes durcis (FIX-033) — Risque FAIBLE

     - Quoi : Nouveau fichier lib/core/security/ssh_hardened_config.dart
     - Pourquoi : Bloquer les algorithmes SSH obsoletes (SHA-1, CBC, 3DES) et forcer
     les modernes
     - Impact : Nouveau fichier. Modification dans la config SSH au moment de la
     connexion
     - Source :
     .defender_working/.../code/blindage_reseau_crypto/.../fix_033_dartssh2_config.dart

     Verification Sprint 1

     - flutter test passe toujours
     - Le PIN fonctionne (creer, verifier, supprimer)
     - Le daemon demarre avec verification d'integrite
     - Commit : feat(security): sprint 1 — fondations critiques P0

     ---
     Sprint 2 — Protection au demarrage (P1 urgents)

     But : Securiser le demarrage de l'app et empecher la desactivation facile des
     protections OS.
     Risque : MOYEN (on modifie main.dart et le module securite)
     Duree estimee : 2-3 sessions

     Sous-etapes

     2.1 — Error handler securise (FIX-002) — Risque FAIBLE

     - Quoi : Nouveau fichier lib/core/security/secure_error_handler.dart + MODIFIER
     lib/main.dart
     - Pourquoi : Les erreurs peuvent fuiter des infos sensibles (chemins, stack
     traces). On les filtre
     - Source :
     .defender_working/.../code/blindage_code/fix_002_secure_error_handling.dart

     2.2 — Verifications au demarrage (FIX-010/011) — Risque FAIBLE

     - Quoi : Nouveau fichier lib/core/security/startup_security.dart + appel dans
     main.dart
     - Pourquoi : Detecter les debuggers (Frida, gdb), les injections (LD_PRELOAD), les
      hooks malveillants
     - Source :
     .defender_working/.../code/blindage_framework/fix_008_011_startup_security.dart

     2.3 — Confirmation progressive (FIX-009) — Risque MOYEN

     - Quoi : Nouveau widget + MODIFIER lib/features/security/security_commands.dart
     - Pourquoi : Empecher la desactivation du pare-feu/AppArmor en un seul clic.
     Forcer un delai + saisie "CONFIRMER"
     - Source : .defender_working/.../code/blindage_framework/fix_008_009_navigation_co
     nfirmation.dart

     2.4 — Journal d'audit (FIX-020) — Risque FAIBLE

     - Quoi : Nouveau fichier lib/core/security/security_audit_log.dart
     - Pourquoi : Logger qui active/desactive les protections, avec une chaine de hash
     anti-falsification
     - Source :
     .defender_working/.../code/blindage_framework/fix_020_security_audit_log.dart

     2.5 — Firewall Tailscale-only (FIX-017) — Risque FAIBLE

     - Quoi : Nouveau fichier lib/core/security/tailscale_firewall.dart
     - Pourquoi : SSH ne devrait accepter que les connexions Tailscale (100.64.0.0/10)
     - Source :
     .defender_working/.../code/blindage_framework/fix_017_firewall_ssh_tailscale.dart

     2.6 — Obfuscation des builds (FIX-021/022) — Risque FAIBLE

     - Quoi : Modifier les commandes de build + nouveau fichier pour chaines chiffrees
     - Pourquoi : Le binaire Flutter est lisible en clair, les noms de classes sont
     visibles
     - Source :
     .defender_working/.../code/blindage_framework/fix_021_022_obfuscation.dart

     2.7 — Heartbeat securise (FIX-034) + sshd_config durci (FIX-036) — Risque FAIBLE

     - Quoi : Nouveaux fichiers (communication daemon + config SSH cible)
     - Source : .defender_working/.../code/blindage_reseau_crypto/

     Verification Sprint 2

     - flutter test passe
     - L'app demarre normalement avec les verifications
     - La desactivation du pare-feu demande confirmation
     - Commit : feat(security): sprint 2 — protection demarrage et commandes P1

     ---
     Sprint 3 — Renforcement en profondeur (P1 suite + P2)

     But : Durcir l'app en profondeur — memoire, routes, reseau.
     Risque : MOYEN
     Duree estimee : 2-3 sessions

     Sous-etapes

     - FIX-003 : Isolation crypto dans un Isolate Dart (MODIFIER lock_provider.dart)
     - FIX-008 : Route guards pour pages sensibles (MODIFIER router.dart)
     - FIX-013 : Protection capture d'ecran
     - FIX-015/016 : Configs sandbox OS (AppArmor Linux, entitlements macOS)
     - FIX-028/030 : Memoire native FFI (hors GC Dart, anti cold-boot)
     - FIX-029 : Rotation automatique des cles SSH (30 jours)
     - FIX-037 : Detection proxy/VPN tiers
     - FIX-038/039 : Securite Tailscale + etat signe
     - FIX-045/052 : Kill switch + Rate limiting anti-IA (defenses d'urgence)

     Verification Sprint 3

     - flutter test passe
     - Navigation securisee fonctionne
     - Kill switch testable (en mode dry-run)
     - Commit : feat(security): sprint 3 — renforcement profondeur P1-P2

     ---
     Sprint 4 — Defenses avancees (P2-P3)

     But : Ajouter les couches de deception et surveillance.
     Risque : FAIBLE (que des nouveaux fichiers, peu de modifs existantes)
     Duree estimee : 2-3 sessions

     Sous-etapes

     - FIX-041-044 : Honeypot SSH, canary tokens, tarpit, secure logging
     - FIX-046-051 : Duress PIN, moving target, botnet monitor, attestation mutuelle
     - FIX-053-056 : Detection IA comportementale, segmentation reseau, supply chain
     - FIX-004-007 : Types sensibles, sealed classes, streams securises, nonce manager
     (P3 Dart restant)
     - FIX-018/019 : Packaging signe (MSIX/Snap/DMG)
     - FIX-025/026 : Canary values, WDAC Windows

     Verification Sprint 4

     - flutter test passe
     - Modules de deception fonctionnels
     - Commit : feat(security): sprint 4 — defenses avancees et deception P2-P3

     ---
     Sprint 5 — Finalisation (P3 backlog + polish)

     But : Derniers ajustements, documentation, preparation future.
     Risque : FAIBLE
     Duree estimee : 1-2 sessions

     Sous-etapes

     - FIX-031/040 : Preparation post-quantique (documentation + checker)
     - FIX-057/058 : Preparation forensique + conformite CRA
     - FIX-023/024 : Anti-debug avance + obfuscation control flow
     - Integration finale : s'assurer que tous les modules se connectent
     - Tests de regression complets
     - Documentation d'integration mise a jour

     Verification Sprint 5

     - flutter test passe (tous les tests)
     - flutter build linux compile sans erreur
     - Commit final : feat(security): sprint 5 — finalisation et preparation future

     ---
     Resume visuel

     Sprint 0  Preparation          │ Risque: NUL    │ Organiser les fichiers
     Sprint 1  P0 Critiques         │ Risque: MOYEN  │ PIN securise + daemon verifie +
     IPC chiffre
     Sprint 2  P1 Demarrage         │ Risque: MOYEN  │ Error handler + startup checks +
      confirmation
     Sprint 3  P1-P2 Profondeur     │ Risque: MOYEN  │ Memoire + routes + kill switch +
      rate limit
     Sprint 4  P2-P3 Avance         │ Risque: FAIBLE │ Deception + surveillance +
     packaging
     Sprint 5  P3 Finalisation      │ Risque: FAIBLE │ Post-quantique + forensics +
     polish

     Regle d'or a chaque etape

     1. Creer les NOUVEAUX fichiers d'abord (risque zero)
     2. MODIFIER les fichiers existants un par un
     3. Lancer flutter test apres chaque modification
     4. Si un test echoue → corriger AVANT de continuer
     5. Commit apres chaque sous-etape reussie

     Fichiers existants qui seront modifies (liste complete)

     Fichier: lib/main.dart
     Sprint: 2
     Modification: Ajouter error handler + startup checks
     ────────────────────────────────────────
     Fichier: lib/features/lock/lock_provider.dart
     Sprint: 1, 3
     Modification: SecureStorage (S1) + CryptoIsolate (S3)
     ────────────────────────────────────────
     Fichier: lib/config/router.dart
     Sprint: 3
     Modification: Ajouter SecurityRouteObserver
     ────────────────────────────────────────
     Fichier: lib/features/security/security_commands.dart
     Sprint: 2
     Modification: Ajouter ProgressiveConfirmation
     ────────────────────────────────────────
     Fichier: lib/features/tailscale/tailscale_provider.dart
     Sprint: 1
     Modification: Ajouter verification daemon + IPC auth
     ────────────────────────────────────────
     Fichier: Scripts de build
     Sprint: 2
     Modification: Ajouter --obfuscate