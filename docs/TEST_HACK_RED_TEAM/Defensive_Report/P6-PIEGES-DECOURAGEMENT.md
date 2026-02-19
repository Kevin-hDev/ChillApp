# P6 — Pièges et Découragement

## Synthèse

| Métrique | Valeur |
|----------|--------|
| Gaps assignés (P2) | 18 |
| Gaps traités | 18 |
| Gaps différés | 0 |
| Fichiers de code | 13 |
| Fichiers de tests | 7 |
| Catégories | DC (Deception), BH (Comportemental) |

## Tableau des corrections

| Fix | Gap | Priorité | Catégorie | Titre | Fichier code |
|-----|-----|----------|-----------|-------|-------------|
| FIX-041 | GAP-041 | P2 | DC | Honeypot SSH avec tarpit | fix_041_honeypot_ssh.dart |
| FIX-042 | GAP-042 | P1 | DC | Canary tokens (fichiers pièges) | fix_042_canary_tokens.dart |
| FIX-043 | GAP-043 | P1 | DC | Tarpit backoff exponentiel | fix_043_tarpit.dart |
| FIX-044 | GAP-044 | P1 | DC | Secure logger hash chain | fix_044_secure_logging.dart |
| FIX-045 | GAP-045 | P0 | DC | Kill switch multi-couche | fix_045_055_kill_switch.dart |
| FIX-046 | GAP-046 | P2 | DC | Duress PIN | fix_046_duress_pin.dart |
| FIX-047 | GAP-047 | P3 | DC | Moving target (port hopping) | fix_047_048_moving_target_fingerprint.dart |
| FIX-048 | GAP-048 | P3 | DC | Fingerprinting inverse | fix_047_048_moving_target_fingerprint.dart |
| FIX-049 | GAP-049 | P2 | DC | Défenses botnets SSH | fix_049_050_botnet_tailscale_monitoring.dart |
| FIX-050 | GAP-050 | P1 | DC | Monitoring Tailscale ACLs | fix_049_050_botnet_tailscale_monitoring.dart |
| FIX-051 | GAP-051 | P2 | DC | Attestation mutuelle | fix_051_mutual_attestation.dart |
| FIX-052 | GAP-052 | P0 | BH | Rate limiting anti-IA | fix_052_053_ai_detection.dart |
| FIX-053 | GAP-053 | P1 | BH | Détection comportementale IA | fix_052_053_ai_detection.dart |
| FIX-054 | GAP-054 | P1 | BH | Segmentation réseau | fix_054_network_segmentation.dart |
| FIX-055 | GAP-055 | P1 | BH | Kill switch IA-résistant | fix_045_055_kill_switch.dart |
| FIX-056 | GAP-056 | P2 | BH | Défense supply chain IA | fix_056_supply_chain.dart |
| FIX-057 | GAP-057 | P3 | BH | Préparation forensique | fix_057_058_forensics_cra.dart |
| FIX-058 | GAP-058 | P3 | BH | Conformité CRA | fix_057_058_forensics_cra.dart |

## Détail des protections

### DC — Deception (11 protections)

#### FIX-041 : Honeypot SSH
- **Principe** : Faux serveur SSH sur port 22, bannière réaliste, tarpit (1 byte/10s)
- **Mécanisme** : Le vrai SSH tourne sur un port aléatoire via Tailscale, invisible aux scanners
- **Résultat** : L'attaquant perd du temps sur un faux serveur qui log toutes ses actions

#### FIX-042 : Canary Tokens
- **Principe** : Fichiers pièges (fausse clé SSH, faux credentials, faux .env, fausse DB)
- **Mécanisme** : Surveillance périodique par stat.accessed. Alerte si lecture/modification
- **Résultat** : Détection immédiate d'une exploration du système de fichiers

#### FIX-043 : Tarpit Serveur-Side
- **Principe** : Backoff exponentiel (0→1→2→4→8→16→32→60s max), auto-blacklist après 20 échecs
- **Différence vs PROT-008** : Stocké en mémoire, non réinitiliable par l'attaquant (contrairement à SharedPreferences)
- **Résultat** : Brute-force PIN rendu impraticable

#### FIX-044 : Secure Logger Anti-Tamper
- **Principe** : Chaîne de hachage SHA-256 (type blockchain). Chaque log contient le hash du précédent
- **Sanitisation** : Supprime automatiquement clés SSH, tokens, mots de passe, IPs non-Tailscale, chemins utilisateur
- **Résultat** : Logs infalsifiables avec preuve cryptographique d'intégrité

#### FIX-045 : Kill Switch Multi-Couche
- **Actions** : Effacer clés SSH (zero-before-delete), fermer sessions, déconnecter Tailscale (logout), effacer secure storage, supprimer canary tokens
- **Protection** : Confirmation par PIN (PAS biométrie — deepfakes), 6 raisons de déclenchement
- **Résultat** : Destruction complète des données sensibles en <5 secondes

#### FIX-046 : Duress PIN
- **Principe** : Un second PIN configurable qui ouvre une interface factice + envoie une alerte silencieuse
- **Sécurité** : Les DEUX hashes sont toujours comparés (temps constant — pas de timing leak)
- **Résultat** : Protection contre la contrainte physique ("rubber hose attack")

#### FIX-047 : Moving Target Defense
- **Principe** : Port SSH aléatoire (49152-65535), rotation toutes les 6 heures, bannières randomisées
- **Résultat** : L'attaquant ne peut pas cibler un port fixe. Le fingerprinting SSH est brouillé

#### FIX-048 : Fingerprinting Inverse
- **Principe** : Profilage des attaquants par IP, bannières, usernames, ports ciblés
- **Classification** : Botnet (beaucoup d'essais, peu de variété), Scanner (beaucoup de ports), Ciblé (usernames spécifiques)
- **Résultat** : Intelligence sur les attaquants pour adapter les défenses

#### FIX-049 : Défenses Botnets SSH
- **Principe** : Audit régulier de authorized_keys (local + distant), registre des clés connues
- **Résultat** : Détection des clés injectées par les botnets (SSHStalker, AyySSHush, PumaBot)

#### FIX-050 : Monitoring Tailscale ACLs
- **Principe** : Vérification périodique du statut Tailscale, détection wildcard ACLs, nœuds partagés
- **Résultat** : Prévention des mauvaises configurations ACL (ref: TS-2025-006)

#### FIX-051 : Attestation Mutuelle
- **Principe** : Challenge-response basé sur HMAC-SHA256(nonce + SHA256(binaire), clé_partagée)
- **Vérification** : Hash du binaire daemon comparé aux hashes attendus par plateforme
- **Résultat** : Impossible de substituer le daemon par un imposteur

### BH — Comportemental (7 protections)

#### FIX-052 : Rate Limiting Anti-IA
- **Seuils** : 10 req/min → slowdown (200ms/req excédentaire), 50 req/min → blocked
- **Fenêtre** : Glissante, 1 minute
- **Résultat** : Bloque les agents IA exécutant des milliers de requêtes par seconde

#### FIX-053 : Détection Comportementale IA
- **Critères** : Timing trop régulier (<50ms variance), énumération systématique (>70% ls/cat/find), absence de pauses humaines (>5s), commandes dangereuses
- **Score** : 0.0 (humain) à 1.0 (certainement IA). ≥0.7 = block, ≥0.4 = warn
- **Résultat** : Distingue les humains des agents IA automatisés

#### FIX-054 : Segmentation Réseau
- **Principe** : Le bridge n'accède QU'AU PC cible configuré (une seule IP Tailscale)
- **Vérifications** : IP destination = cible autorisée, port = 22, source = Tailscale (100.64.0.0/10)
- **Templates** : ACLs Tailscale (sans wildcard) + règles iptables
- **Résultat** : Empêche le mouvement latéral même si le bridge est compromis

#### FIX-055 : Kill Switch IA-Résistant
- **Watchdog** : Processus indépendant, heartbeat toutes les 30s
- **Auto-kill** : Si heartbeat absent > 2 minutes, kill switch automatique (sans PIN)
- **Résultat** : Un agent IA ne peut pas désactiver le watchdog (résiste à 79% des tentatives)

#### FIX-056 : Défense Supply Chain IA
- **Principe** : Audit automatique de pubspec.lock, détection typosquatting, packages git flaggés
- **Patterns suspects** : flutter- (tiret), flutterr, riverpood, cripto, crytpo
- **Résultat** : Bloque les packages hallucines par l'IA avant le build

#### FIX-057 : Préparation Forensique
- **Collecte** : Intégrité binaire (SHA-256), processus suspects (frida, gdb, mitmproxy...), connexions non-Tailscale, fichiers SSH modifiés récemment
- **Export** : Rapport JSON complet avec toutes les preuves
- **Résultat** : Preuves exploitables pour l'analyse post-incident

#### FIX-058 : Conformité CRA
- **Template** : Notification de vulnérabilité (EU Regulation 2024/2847, Article 14)
- **Deadlines** : 24h (activement exploité) ou 72h (non-exploité)
- **Checklist** : 5 exigences CRA vérifiées (vulnerability handling, notification, updates, secure-by-default, documentation)
- **Résultat** : Préparation à l'entrée en vigueur du CRA (septembre 2026)

## Structure des fichiers

```
code/pieges_decouragement/
├── fix_041_honeypot_ssh.dart                    (167 lignes)
├── fix_042_canary_tokens.dart                   (343 lignes)
├── fix_043_tarpit.dart                          (206 lignes)
├── fix_044_secure_logging.dart                  (294 lignes)
├── fix_045_055_kill_switch.dart                 (325 lignes)
├── fix_046_duress_pin.dart                      (142 lignes)
├── fix_047_048_moving_target_fingerprint.dart   (229 lignes)
├── fix_049_050_botnet_tailscale_monitoring.dart  (281 lignes)
├── fix_051_mutual_attestation.dart              (206 lignes)
├── fix_052_053_ai_detection.dart                (296 lignes)
├── fix_054_network_segmentation.dart            (194 lignes)
├── fix_056_supply_chain.dart                    (222 lignes)
├── fix_057_058_forensics_cra.dart               (332 lignes)
├── test_fix_041.dart
├── test_fix_043.dart
├── test_fix_044.dart
├── test_fix_045_055.dart
├── test_fix_046.dart
├── test_fix_047_048.dart
├── test_fix_052_053.dart
└── test_fix_054_056.dart
```

## Couverture des connaissances

| Fichier knowledge | Sections évaluées | Traitées | N/A | Couverture |
|-------------------|-------------------|----------|-----|------------|
| deception-monitoring.md | 14 | 11 | 3 | 79% |
| ai-defense-strategies.md | 10 | 7 | 3 | 70% |
| **Total** | **24** | **18** | **6** | **75%** |

## Priorités

| Priorité | Count | Gaps |
|----------|-------|------|
| P0 | 2 | GAP-045 (kill switch), GAP-052 (rate limiting IA) |
| P1 | 7 | GAP-042, 043, 044, 050, 053, 054, 055 |
| P2 | 5 | GAP-041, 046, 049, 051, 056 |
| P3 | 4 | GAP-047, 048, 057, 058 |

## Vérification invariant

- Gaps P6 assignés en P2 : **18**
- Fixes P6 écrits : **18**
- Gaps non traités : **0**
- **Invariant respecté** ✓
