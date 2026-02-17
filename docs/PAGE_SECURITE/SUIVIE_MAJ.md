# Suivi des mises a jour — Page Securite OS

> Source : Analyse de `CYBERSEC_DESKTOP_CONSOLIDATED.md`
> Date de debut : 2026-02-17

---

## Nouveaux toggles ajoutes

### Windows (2 nouveaux → total : 10 toggles)

| Toggle | Fichier | Status |
|--------|---------|--------|
| LSA Protection (RunAsPPL) | `security_commands.dart` | OK |
| Core Isolation / HVCI | `security_commands.dart` | OK |
| DNS securise (Quad9) | `security_commands.dart` | OK |

### Linux (3 nouveaux → total : 10 toggles)

| Toggle | Fichier | Status |
|--------|---------|--------|
| CrowdSec (protection collaborative) | `security_commands.dart` | OK |
| AppArmor | `security_commands.dart` | OK |
| DNS securise (Quad9) | `security_commands.dart` | OK |

### macOS (1 nouveau → total : 8 toggles)

| Toggle | Fichier | Status |
|--------|---------|--------|
| DNS securise (Quad9) | `security_commands.dart` | OK |

---

## Nouveaux points de checkup (3 nouveaux)

| Point | OS | Fichier | Status |
|-------|----|---------|--------|
| LSA Protection (RunAsPPL) | Windows | `security_commands.dart` | OK |
| SIP (System Integrity Protection) | macOS | `security_commands.dart` | OK |
| AppArmor / SELinux | Linux | `security_commands.dart` | OK |

---

## Fichiers modifies

| Fichier | Modifications | Status |
|---------|---------------|--------|
| `lib/features/security/security_commands.dart` | +5 toggles (check/enable/disable) + 3 checkup | OK |
| `lib/features/security/security_provider.dart` | Nouveaux toggles + severites + install CrowdSec | OK |
| `lib/features/security/security_screen.dart` | Nouveaux widgets toggle dans l'UI | OK |
| `lib/i18n/translations.dart` | Traductions FR + EN pour tous les ajouts | OK |

---

## Elements exclus (decision utilisateur)

- Lockdown Mode macOS → Trop restrictif pour un utilisateur lambda
- PowerShell v2 removal → Peut casser certains logiciels anciens

---

## Corrections de bugs (2026-02-17)

> 5 toggles Linux ne pouvaient pas etre desactives apres activation.

| Toggle | Cause racine | Correction | Status |
|--------|-------------|------------|--------|
| AppArmor | La verification lisait le module kernel (`/sys/module/apparmor/parameters/enabled`) qui reste actif meme apres arret du service | Verification via `systemctl is-active apparmor` | CORRIGE |
| Parametres reseau securises (sysctl) | La desactivation supprimait le fichier config mais ne reintialisait pas les valeurs live du kernel | Ajout de `sysctl -w` pour remettre chaque parametre a sa valeur par defaut | CORRIGE |
| Permissions fichiers sensibles | Pas de fonction de desactivation possible (on ne relache pas les permissions) | Toggle a sens unique : affiche un checkmark quand actif, pas de switch pour desactiver | CORRIGE |
| DNS Securise (Quad9) | La verification lisait `/etc/resolv.conf` (cache dynamique) au lieu du fichier de config | Verification via `grep ^DNS=.*9.9.9.9` dans `/etc/systemd/resolved.conf` uniquement | CORRIGE |
| Login root par mot de passe | Le pattern sed `^#*PermitRootLogin` ne matchait pas `# PermitRootLogin` (espace apres #) + fichiers `sshd_config.d/` ignores | Regex elargi `^\s*#?\s*PermitRootLogin` avec flag `-E` + scan de `sshd_config.d/*.conf` | CORRIGE |

### Fichiers modifies pour les corrections

| Fichier | Modifications |
|---------|---------------|
| `security_commands.dart` | AppArmor check, sysctl disable, DNS check, root login enable/disable |
| `security_provider.dart` | Permissions toggle retourne false si `!enable` |
| `security_screen.dart` | Nouveau widget `_StatusOnlyToggle` pour permissions |

---

## Points de checkup manquants ajoutes (2026-02-17)

> Plusieurs toggles n'avaient pas de verification correspondante dans le rapport de checkup.

### Linux (3 ajouts → total : 13 points)

| Point | Verification | Status |
|-------|-------------|--------|
| DNS securise (Quad9) | `grep ^DNS=.*9.9.9.9` dans resolved.conf | OK |
| CrowdSec | `command -v cscli` + `systemctl is-active crowdsec` | OK |
| Mises a jour automatiques | `unattended-upgrades` ou `dnf-automatic-install.timer` | OK |

### Windows (3 ajouts → total : 10 points)

| Point | Verification | Status |
|-------|-------------|--------|
| Integrite memoire (HVCI) | Registre HVCI Enabled | OK |
| DNS securise (Quad9) | `Get-DnsClientServerAddress` contient 9.9.9.9 | OK |
| Audit des connexions | `auditpol /get` Success+Failure | OK |

### macOS (1 ajout → total : 9 points)

| Point | Verification | Status |
|-------|-------------|--------|
| DNS securise (Quad9) | `networksetup -getdnsservers` contient 9.9.9.9 | OK |

### Audit toggles Windows/macOS

> Verification que les toggles n'ont pas le meme bug "impossible de desactiver" que Linux.
> Resultat : **aucun probleme detecte**. Tous les toggles Windows/macOS lisent et ecrivent la meme source.

---

## Compilation

- `flutter analyze` : 0 erreurs (verifie le 2026-02-17, apres ajout checkup manquants)
