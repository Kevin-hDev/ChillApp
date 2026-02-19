# P2 — Points de Renforcement

**Projet** : ChillApp (hub de configuration desktop Linux/Windows/macOS)
**Date** : 18 fevrier 2026
**Entree** : P1_audit.yaml (13 protections existantes, posture FAIBLE)

---

## Synthese

**58 gaps identifies. 8 critiques (P0), 18 urgents (P1), 20 importants (P2), 12 en backlog (P3).**

L'analyse croisee des 13 protections existantes avec les 111 sections des 9 bases de connaissances revele 58 points de renforcement. Les 4 categories entierement vides (NW, AR, DC, BH) concentrent 44 gaps (76% du total). Les 8 gaps P0 exigent une correction immediate car ils representent des failles critiques ouvertes.

---

## Gaps par Categorie

| Categorie | Gaps | P0 | P1 | P2 | P3 |
|-----------|------|----|----|----|----|
| RT (Runtime Dart) | 7 | 1 | 1 | 3 | 2 |
| FW (Framework Flutter) | 7 | 1 | 3 | 3 | 0 |
| OS (Systeme) | 6 | 0 | 3 | 2 | 1 |
| AR (Anti-Reverse) | 6 | 1 | 4 | 1 | 0 |
| SC (Stockage/Crypto) | 5 | 1 | 1 | 2 | 1 |
| NW (Reseau) | 9 | 3 | 2 | 2 | 2 |
| DC (Deception) | 11 | 1 | 4 | 4 | 2 |
| BH (Comportemental) | 7 | 1 | 3 | 1 | 2 |
| **Total** | **58** | **8** | **18** | **20** | **12** |

---

## Gaps par Phase Cible

| Phase | Categorie(s) | Gaps | Effort estime |
|-------|-------------|------|---------------|
| **P3** — Blindage code Dart | RT | 7 | ~8 heures |
| **P4** — Blindage framework | FW + OS + AR | 19 | ~36 heures |
| **P5** — Blindage reseau/crypto | SC + NW | 14 | ~26 heures |
| **P6** — Pieges/decouragement | DC + BH | 18 | ~42 heures |
| **Total** | | **58** | **~112 heures** |

---

## Top 8 des Gaps Critiques (P0)

Ces 8 gaps doivent etre traites en priorite absolue :

| # | ID | Cat. | Titre | Localisation |
|---|----|------|-------|--------------|
| 1 | GAP-001 | RT | Secrets PIN en memoire non effacables | lock_provider.dart:86 |
| 2 | GAP-012 | FW | IPC daemon non authentifie ni chiffre | tailscale_provider.dart |
| 3 | GAP-024 | AR | Verification d'integrite du daemon Go absente | tailscale_provider.dart |
| 4 | GAP-027 | SC | SharedPreferences en texte clair | lock_provider.dart |
| 5 | GAP-032 | NW | Pas de fail closed — fallback possible | tailscale_provider.dart |
| 6 | GAP-033 | NW | Configuration dartssh2 non durcie | config SSH |
| 7 | GAP-035 | NW | Protocole IPC non securise (JSON brut) | tailscale_provider.dart |
| 8 | GAP-045 | DC | Kill switch / remote wipe absent | nouveau composant |
| 9 | GAP-052 | BH | Rate limiting anti-agent IA absent | nouveau composant |

---

## Top 10 des Gaps Urgents (P1)

| # | ID | Cat. | Titre |
|---|----|------|-------|
| 1 | GAP-002 | RT | runZonedGuarded absent |
| 2 | GAP-010 | FW | Anti-DLL Hijacking Windows |
| 3 | GAP-011 | FW | Anti-injection librairie Linux/macOS |
| 4 | GAP-017 | OS | Firewall SSH non restreint a Tailscale |
| 5 | GAP-019 | OS | Signature de code absente |
| 6 | GAP-020 | OS | Journalisation securite absente |
| 7 | GAP-021 | AR | Obfuscation Dart absente |
| 8 | GAP-022 | AR | Obfuscation litteraux absente |
| 9 | GAP-023 | AR | Anti-debugging desktop absent |
| 10 | GAP-028 | SC | Allocation FFI pour secrets absente |

---

## Matrice de Priorisation

```
              | Effort faible  | Effort moyen   | Effort eleve
-----------+----------------+----------------+---------------
Critique    | GAP-002 (P0)   | GAP-001 (P0)   | GAP-012 (P0*)
            | GAP-021 (P0)   | GAP-024 (P0)   | GAP-027 (P0*)
            |                | GAP-033 (P0)   | GAP-035 (P0*)
            |                | GAP-032 (P0)   |
-----------+----------------+----------------+---------------
Haut        | GAP-011 (P0*)  | GAP-010 (P1)   | GAP-029 (P2)
            | GAP-022 (P1)   | GAP-023 (P1)   | GAP-044 (P2)
            | GAP-034 (P1)   | GAP-028 (P1)   |
            | GAP-042 (P1)   | GAP-043 (P1)   |
-----------+----------------+----------------+---------------
Moyen       | GAP-036 (P1*)  | GAP-015 (P2)   | GAP-041 (P2)
            | GAP-049 (P2)   | GAP-016 (P2)   | GAP-046 (P2)
            | GAP-056 (P2)   | GAP-025 (P2)   |
-----------+----------------+----------------+---------------
Bas         | GAP-005 (P2*)  | GAP-047 (P3)   | GAP-057 (P3)
            | GAP-006 (P3)   | GAP-048 (P3)   | GAP-058 (P3)
            | GAP-031 (P3)   |                |
            | GAP-040 (P3)   |                |

* Priorite ajustee par la matrice
```

---

## Plan de Blindage

### Ordre d'execution : P3 → P4 → P5 → P6

```
P3 (7 gaps, ~8h)     P4 (19 gaps, ~36h)     P5 (14 gaps, ~26h)     P6 (18 gaps, ~42h)
+----------------+    +------------------+    +------------------+    +------------------+
| RT Runtime     |    | FW Framework     |    | SC Stockage      |    | DC Deception     |
| - Memoire PIN  |--->| - IPC securise   |--->| - Keystore       |--->| - Kill switch    |
| - ZonedGuarded |    | - Anti-injection |    | - FFI allocation |    | - Canary tokens  |
| - Isolates     |    | - Anti-debug     |    | - Rotation cles  |    | - Secure logging |
| - Ext. types   |    | - Obfuscation    |    | NW Reseau        |    | BH Comportement  |
| - Nonce mgr    |    | OS Systeme       |    | - Fail closed    |    | - Anti-IA rate   |
|                |    | - Firewall       |    | - Config dartssh2|    | - Behavioral ML  |
|                |    | - Packaging      |    | - IPC protocol   |    | - Segmentation   |
|                |    | AR Anti-Reverse  |    | - Heartbeat      |    | - Duress PIN     |
|                |    | - Daemon hash    |    | - sshd template  |    | - Attestation    |
+----------------+    +------------------+    +------------------+    +------------------+
```

### Focus par phase

**P3 — Code d'abord** : Corriger les fondations. Les secrets en memoire (GAP-001) et l'error handling (GAP-002) sont les premieres choses a blinder avant de construire dessus.

**P4 — Cadre ensuite** : L'IPC daemon (GAP-012), l'integrite du daemon (GAP-024) et l'anti-injection (GAP-010/011) sont critiques. Sans cela, toutes les autres protections sont contournables via le daemon.

**P5 — Stockage et reseau** : Migrer SharedPreferences vers un keystore securise (GAP-027) et durcir dartssh2 (GAP-033). Ce sont les deux faiblesses structurelles majeures.

**P6 — Defense active** : Le kill switch (GAP-045), la detection IA (GAP-052/053) et le secure logging (GAP-044) transforment la posture de passive a active.

---

## Sections Non Applicables (25 sections)

| Raison | Nombre | Exemples |
|--------|--------|----------|
| Mobile uniquement (Android/iOS) | 12 | FLAG_SECURE, Play Integrity, AndroidNativeGuard, MIE |
| Informationnelle (pas d'action) | 5 | GC proprietes, contexte IA, IPv4 corrige dans SDK |
| Hors scope (pas de pub.dev, pas de build natif) | 3 | Publication pub.dev, Build Hooks, protection IDE IA |
| Usage P7 uniquement | 6 | cross-validation-patterns.md (6 sections) |

---

## Comptage Final

```
Sections knowledge totales :         111
  - Applicables desktop :              78
    - Deja couvertes (PROT-xxx) :       9  (8.6%)
    - A renforcer (GAP-xxx) :          58  (74.4%)
    - Combinee avec autre GAP :        11  (14.1%)
  - Non applicables :                  25
  - Informationnelles :                 8

Cible apres blindage :  67/78 sections couvertes = 85.9%
```

---

**Rapport genere par** : Defensive Hardening v1.0.0
**Session** : CHILLAPP_20260218_153000
