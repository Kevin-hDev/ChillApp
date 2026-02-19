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

## Points d'Entree Identifies

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

## Cibles Prioritaires

| # | Cible | Criticite | Pourquoi |
|---|-------|-----------|----------|
| TGT-001 | Execution commandes | CRITIQUE | Point unique de controle OS |
| TGT-002 | Module securite OS | CRITIQUE | 1558 lignes de commandes privilegiees, peut desactiver les protections |
| TGT-003 | Configuration SSH | CRITIQUE | Scripts root, modification sshd_config |
| TGT-004 | Daemon Tailscale | CRITIQUE | Binaire non verifie, SSH forwarding, IPC non authentifie |
| TGT-005 | Systeme PIN | HAUTE | SharedPreferences texte clair, contournement possible |
| TGT-006 | Configuration WoL | HAUTE | Service systemd, exposition MAC |
| TGT-007 | Autostart | HAUTE | Persistance .desktop non echappee |
| TGT-008 | Info reseau | MOYENNE | Collecte d'infos systeme |

## Observations de l'Attaquant

**Ce qui attire l'oeil immediatement :**

1. **L'app est un outil d'ADMIN avec acces root** — elle ne fait pas que lire le systeme, elle le MODIFIE. Pare-feu, DNS, SSH, registre, services systemd... tout est modifiable. Un attaquant qui compromet cette app a plus de pouvoir qu'un utilisateur normal.

2. **Scripts temporaires executes en root** — le pattern "ecrire un script dans /tmp puis l'executer via pkexec" est utilise partout (SSH setup, WoL, securite). Meme avec les mitigations TOCTOU (chmod 700, createTemp), la fenetre de race existe.

3. **Le daemon Go est une bombe supply chain** — 3 binaires pre-compiles de 33Mo sans AUCUNE verification d'integrite. Si un attaquant remplace le binaire, il obtient une execution de code au demarrage de l'app, avec forwarding SSH en bonus.

4. **SharedPreferences = coffre-fort en carton** — le PIN est "protege" par PBKDF2, mais le fichier est en texte clair. Un attaquant peut simplement SUPPRIMER les cles `pin_hash` et `pin_salt` pour desactiver le verrou. Pas besoin de cracker le hash.

5. **Le module securite peut se retourner contre l'utilisateur** — les toggles permettent de DESACTIVER le pare-feu, activer RDP, reactiver SMBv1. Si un attaquant obtient l'acces a l'interface, il peut degrader toute la securite du systeme.

6. **Ou commencerait-on l'attaque ?** Du remplacement du binaire Tailscale (supply chain) vers l'execution en tant que daemon privilegie, puis exploitation du SSH forwarding pour obtenir un shell sur la machine cible.
