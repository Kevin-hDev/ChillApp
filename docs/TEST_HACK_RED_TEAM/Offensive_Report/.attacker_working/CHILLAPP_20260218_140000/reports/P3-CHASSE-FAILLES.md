# P3 - Chasse aux Failles

## Synthese

19 vulnerabilites decouvertes : 3 CRITIQUES, 7 HAUTES, 5 MOYENNES, 3 BASSES, 1 INFO. Les failles les plus devastatrices sont l'absence de verification d'integrite du binaire daemon Tailscale (supply chain), le contournement du lock PIN par suppression de fichier, et la possibilite de desactiver toutes les protections OS via le module securite.

## Vulnerabilites par Severite

### CRITIQUES (3)

| ID | Titre | CVSS | CWE | Fichier:Ligne |
|----|-------|------|-----|---------------|
| VULN-001 | Binaire daemon sans verification d'integrite | 9.3 | CWE-494 | tailscale_provider.dart:141 |
| VULN-002 | Contournement PIN par suppression SharedPrefs | 8.1 | CWE-312 | lock_provider.dart:65 |
| VULN-003 | Module securite desactive toutes les protections | 8.5 | CWE-269 | security_commands.dart:30 |

### HAUTES (7)

| ID | Titre | CVSS | CWE | Fichier:Ligne |
|----|-------|------|-----|---------------|
| VULN-004 | TOCTOU scripts root /tmp | 7.0 | CWE-367 | ssh_setup_provider.dart:287 |
| VULN-005 | .desktop chemin non echappe | 7.3 | CWE-78 | settings_provider.dart:98 |
| VULN-006 | Cles Tailscale non chiffrees | 7.5 | CWE-312 | main.go:69 |
| VULN-007 | IPC daemon non authentifie | 7.1 | CWE-419 | tailscale_provider.dart:294 |
| VULN-008 | PIN memoire non effacable | 6.8 | CWE-316 | lock_provider.dart:143 |
| VULN-009 | SSH forwarding sans filtrage | 7.5 | CWE-284 | main.go:181 |
| VULN-010 | Rate limiting client-side | 6.5 | CWE-307 | lock_provider.dart:215 |

### MOYENNES (5)

| ID | Titre | CVSS | CWE | Fichier:Ligne |
|----|-------|------|-----|---------------|
| VULN-011 | Info reseau dans clipboard | 4.3 | CWE-200 | copyable_info.dart:1 |
| VULN-012 | Processus orphelins timeout | 5.3 | CWE-404 | command_runner.dart:27 |
| VULN-013 | Pas d'obfuscation | 4.0 | CWE-693 | pubspec.yaml:1 |
| VULN-014 | google_fonts sans pinning | 4.8 | CWE-295 | pubspec.yaml:16 |
| VULN-015 | plist XML non echappe | 5.5 | CWE-78 | settings_provider.dart:116 |

### BASSES (3)

| ID | Titre | CVSS | CWE | Fichier:Ligne |
|----|-------|------|-----|---------------|
| VULN-016 | Pas d'anti-debug | 3.1 | CWE-489 | main.dart:1 |
| VULN-017 | Migration SHA-256 legacy | 3.7 | CWE-916 | lock_provider.dart:186 |
| VULN-018 | WoL sans authentification | 3.1 | CWE-306 | wol_setup_provider.dart:228 |

### INFO (1)

| ID | Titre | CVSS | CWE | Fichier:Ligne |
|----|-------|------|-----|---------------|
| VULN-019 | Pas de migration post-quantique | 0.0 | CWE-327 | main.go:158 |

## Statistiques : 3 CRITIQUE / 7 HAUTE / 5 MOYENNE / 3 BASSE / 1 INFO = 19 total
