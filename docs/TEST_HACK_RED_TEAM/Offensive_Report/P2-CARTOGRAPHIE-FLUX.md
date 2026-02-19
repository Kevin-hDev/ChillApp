# P2 - Cartographie des Flux de Donnees

## Synthese

12 flux de donnees traces, 6 secrets identifies, 5 frontieres de confiance cartographiees. Les flux les plus critiques sont : le stockage du PIN dans SharedPreferences (texte clair), l'IPC non authentifie avec le daemon Tailscale, et les scripts temporaires executes en root via pkexec. L'absence totale de chiffrement au repos et l'IPC en clair sont les faiblesses structurelles dominantes.

## Diagramme des Flux

```
Utilisateur
    |
    v
+------------------+         +------------------+         +-----------------+
| UI Flutter       |--[DF-001: PIN]-->| SharedPrefs    | fichier texte    |
| (lock_screen)    |<-[DF-002: verify]| (disque)       | clair sur disque |
+------------------+         +------------------+         +-----------------+
    |
    |--[DF-003: IPC stdin/stdout]-->+------------------+
    |                               | Daemon Go        |
    |<-[DF-004: auth_url]----------| (chill-tailscale)|
    |                               +--------+---------+
    |                                        |
    |                                  [DF-009: SSH fwd]
    |                                        |
    |                                        v
    |                               +------------------+
    |                               | localhost:22     |
    |                               | (serveur SSH)    |
    |                               +------------------+
    |
    |--[DF-005: script SSH]-->+--[/tmp]-->[pkexec]-->/etc/ssh/sshd_config
    |--[DF-006: script sec]-->+--[/tmp]-->[pkexec]-->pare-feu/DNS/sysctl
    |--[DF-007: script WoL]-->+--[/tmp]-->[pkexec]-->systemd/ethtool
    |
    |--[DF-008: info reseau]-->commandes bash-->UI (affichage IP/MAC)
    |--[DF-010: autostart]-->.desktop / plist / registre
    |--[DF-011: checkup]-->script bash eleve-->JSON temp-->UI
    |
    +--[DF-012: state]-->~/.local/share/chill-app/tailscale/ (cles WireGuard)
```

## Flux de Donnees Critiques

| ID | Nom | Source -> Destination | Classification | Protection |
|----|-----|----------------------|----------------|------------|
| DF-001 | Stockage PIN | NumPad -> SharedPrefs | SECRET | **AUCUNE au repos** |
| DF-003 | IPC Tailscale | Flutter -> Daemon Go | CONFIDENTIEL | **AUCUNE** (stdin/stdout clair) |
| DF-005 | Setup SSH | Script /tmp -> pkexec | CONFIDENTIEL | chmod 700, TOCTOU |
| DF-006 | Commandes securite | Script /tmp -> pkexec | CONFIDENTIEL | chmod 700, TOCTOU |
| DF-009 | SSH forwarding | Tailscale:22 -> localhost:22 | SECRET | WireGuard + SSH |
| DF-012 | Cles Tailscale | tsnet -> filesystem | SECRET | Permissions 0700 |

## Secrets en Transit

| ID | Type | Duree exposition | Extractible ? | Methode |
|----|------|-----------------|---------------|---------|
| SEC-001 | PIN en clair (memoire) | Duree calcul PBKDF2 | Oui | Dump memoire, debugger |
| SEC-002 | Hash + sel PIN (disque) | Permanent | **Oui** | Lecture/suppression fichier |
| SEC-003 | Cles Tailscale (disque) | Permanent | Oui | Lecture repertoire |
| SEC-004 | Scripts eleves (/tmp) | Quelques secondes | Oui | Race condition TOCTOU |
| SEC-005 | Info reseau (UI) | Ecran affiche | Oui | Screenshot, copie |
| SEC-006 | Binaire daemon (disque) | Permanent | **Oui** | Remplacement fichier |

## Frontieres de Confiance

| ID | Nom | Flux | Protection | Risque |
|----|-----|------|------------|--------|
| TB-001 | App -> pkexec | DF-005,006,007 | Dialogue polkit | TOCTOU sur scripts |
| TB-002 | App -> Daemon Go | DF-003,004 | **AUCUNE** | Remplacement binaire |
| TB-003 | Tailscale -> localhost | DF-009 | WireGuard | Noeud compromis = SSH |
| TB-004 | Memoire -> SharedPrefs | DF-001,002 | **AUCUNE** | Lecture/suppression fichier |
| TB-005 | /tmp -> root exec | DF-005,006,007 | chmod 700 | Race condition |

## Observations de l'Attaquant

1. **Le flux le plus juteux** : DF-003 (IPC avec le daemon). Pas de verification d'integrite du binaire, pas d'authentification IPC. Remplacer le binaire = execution de code au demarrage de l'app.

2. **Le secret le plus facile a voler** : SEC-002 (hash PIN dans SharedPreferences). C'est un fichier texte. Le supprimer contourne le lock. Le lire donne le hash pour un brute force offline.

3. **Le flux le plus dangereux** : DF-006 (commandes securite). Un attaquant avec acces a l'interface peut desactiver le pare-feu, activer SMBv1, desactiver AppArmor — tout en un clic.

4. **La frontiere la plus faible** : TB-004 (memoire -> SharedPreferences). Zero protection entre l'app et le stockage sur disque. Tout processus du meme utilisateur peut lire/modifier les preferences.
