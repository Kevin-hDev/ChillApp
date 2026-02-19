# P1 - Rapport de Reconnaissance

## Synthese

ChillApp est un hub de configuration desktop (Linux/Windows/macOS) qui installe SSH, configure Wake-on-LAN, integre Tailscale et durcit la securite OS. L'application execute massivement des commandes systeme avec privileges eleves (pkexec, RunAs, osascript) via des scripts temporaires. Un daemon Go pre-compile gere Tailscale et forwarde le trafic SSH. Le PIN de verrouillage est stocke dans SharedPreferences (texte clair sur disque). La surface d'attaque est dominee par l'execution de commandes privilegiees et l'absence de sandbox desktop.

## Stack Technique

| Composant | Version | Role | Risque Securite |
|-----------|---------|------|-----------------|
| Flutter | 3.38.7 | Framework UI desktop | BASSE |
| Dart | 3.10.7 | Langage principal | BASSE |
| shared_preferences | ^2.5.4 | Stockage PIN, preferences | **CRITIQUE** - texte clair |
| crypto | ^3.0.7 | PBKDF2/SHA-256 pour PIN | HAUTE - implementation custom |
| tsnet (Go) | latest | Daemon Tailscale | **CRITIQUE** - binaire non verifie |
| google_fonts | ^8.0.1 | Polices runtime | BASSE - telecharge depuis Internet |

## Points d'Entree Identifies (16)

| ID | Type | Localisation | Exposition | Risque |
|----|------|-------------|------------|--------|
| EP-001 | Execution commandes | command_runner.dart:36 | Process local | CRITIQUE |
| EP-002 | Elevation pkexec | command_runner.dart:106 | Root local | CRITIQUE |
| EP-003 | Elevation PowerShell | command_runner.dart:82-99 | Admin local | CRITIQUE |
| EP-004 | Elevation osascript | command_runner.dart:107-128 | Admin local | CRITIQUE |
| EP-005 | IPC daemon Tailscale | tailscale_provider.dart:293 | Process local | HAUTE |
| EP-006 | Port 22 Tailscale | main.go:158 | Reseau Tailscale | CRITIQUE |
| EP-007 | SharedPreferences | lock_provider.dart:57 | Fichier local | HAUTE |
| EP-008 | Scripts temp root | ssh_setup_provider.dart:285 | Root via /tmp | CRITIQUE |
| EP-009 | Autostart .desktop | settings_provider.dart:94 | Persistance | HAUTE |
| EP-010 | Ouverture URL | tailscale_provider.dart:300 | Navigateur | MOYENNE |
| EP-011 | Service systemd | wol_setup_provider.dart:304 | Service systeme | HAUTE |
| EP-012 | Modification sshd_config | ssh_setup_provider.dart:274 | Config systeme | HAUTE |
| EP-013 | Modification DNS | security_commands.dart:662 | Config systeme | HAUTE |
| EP-014 | Registre Windows | security_commands.dart | Config systeme | HAUTE |
| EP-015 | Parametres sysctl | security_commands.dart:372 | Kernel params | HAUTE |
| EP-016 | Info reseau | network_info.dart:34 | Commandes bash | MOYENNE |

## Surface d'Attaque

| Categorie | Elements | Niveau |
|-----------|----------|--------|
| Reseau | SSH:22, Tailscale/WireGuard:41641, WoL:9 | CRITIQUE |
| Stockage | SharedPreferences (texte clair), Tailscale state dir | CRITIQUE |
| Crypto | PBKDF2 custom, SHA-256 legacy | HAUTE |
| Desktop | Pas de sandbox, elevation privileges, scripts /tmp | CRITIQUE |
| Supply Chain | 3 binaires Go non signes (~100Mo), google_fonts | HAUTE |
| Humain | PIN 8 chiffres, pas de biometrie desktop | MOYENNE |

## Cibles Prioritaires (8)

| # | Cible | Criticite | Pourquoi |
|---|-------|-----------|----------|
| TGT-001 | Execution commandes | CRITIQUE | Point unique de controle OS |
| TGT-002 | Module securite OS | CRITIQUE | Peut desactiver toutes les protections |
| TGT-003 | Configuration SSH | CRITIQUE | Scripts root, modification sshd_config |
| TGT-004 | Daemon Tailscale | CRITIQUE | Binaire non verifie, SSH forwarding |
| TGT-005 | Systeme PIN | HAUTE | SharedPreferences texte clair |
| TGT-006 | Configuration WoL | HAUTE | Service systemd, exposition MAC |
| TGT-007 | Autostart | HAUTE | Persistance .desktop non echappee |
| TGT-008 | Info reseau | MOYENNE | Collecte d'infos systeme |

## Observations de l'Attaquant

1. **L'app est un outil d'admin avec acces root** — elle modifie le pare-feu, DNS, SSH, registre, services systemd
2. **Scripts temporaires en root** — pattern "ecrire dans /tmp puis pkexec" partout (TOCTOU)
3. **Daemon Go = bombe supply chain** — 3 binaires de 33Mo sans verification d'integrite
4. **SharedPreferences = coffre-fort en carton** — supprimer le hash PIN = contournement du lock
5. **Le module securite peut se retourner** — les toggles permettent de desactiver les protections
6. **Vecteur d'attaque principal** — remplacement du binaire Tailscale -> execution de code -> SSH forwarding
