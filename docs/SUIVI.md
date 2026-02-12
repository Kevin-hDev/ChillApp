# Suivi d'avancement — ChillApp V1

> Dernière mise à jour : 12 février 2026

---

## Légende

- [x] Terminé
- [ ] À faire
- [~] En cours

---

## 1. Initialisation du projet

- [x] Créer le projet Flutter (Windows/Linux/macOS)
- [x] Rédiger SPEC.md (spécification complète)
- [x] Rédiger CLAUDE.md (instructions Claude Code)
- [x] Ajouter les dépendances (Riverpod 3.2.1, go_router 16.2.2, shared_preferences 2.5.4, google_fonts 8.0.1)
- [x] Créer la structure de dossiers (config, core, i18n, features, shared)
- [x] Analyse Flutter : 0 erreur

## 2. Design system

- [x] Design tokens (couleurs sombre + clair)
- [x] Thème Flutter (ThemeData sombre + clair)
- [x] Polices (JetBrains Mono titres, Plus Jakarta Sans corps)
- [x] Rayons de bordure, espacements

## 3. Navigation & structure

- [x] Router go_router (5 routes : /, /ssh, /wol, /info, /settings)
- [x] Point d'entrée (main.dart + ProviderScope)
- [x] App (MaterialApp.router + thème dynamique)

## 4. Internationalisation (i18n)

- [x] Traductions FR/EN complètes (80+ clés)
- [x] Provider de langue (Riverpod)
- [x] Sauvegarde de la langue choisie (SharedPreferences)

## 5. Infrastructure technique

- [x] Détection d'OS (Windows/Linux/macOS)
- [x] Détection de distribution Linux (Debian/Fedora/Arch)
- [x] CommandRunner (exécution de commandes via Process.run)
- [x] PrivilegeManager (élévation admin/sudo/pkexec)

## 6. Widgets partagés

- [x] ChillCard (carte cliquable avec icône)
- [x] ChillButton (bouton avec état de chargement)
- [x] StepIndicator (indicateur d'étape : attente/en cours/ok/erreur)
- [x] StatusBadge (badge configuré/pas configuré)

## 7. Écran Dashboard

- [x] Squelette de l'écran
- [x] Grille de 4 cartes (SSH, WoL, Infos, Réglages)
- [x] Badge d'état sur les cartes SSH et WoL (configuré/pas encore configuré)
- [x] Vérification auto du statut SSH (service actif ?)
- [x] Vérification auto du statut WoL (Magic Packet activé ?)

## 8. Écran Configuration SSH

- [x] Squelette de l'écran + provider Riverpod
- [x] Carte explicative "Qu'est-ce que ça fait ?"
- [x] Liste des étapes avec StepIndicator (progression visible en temps réel)
- [x] Bouton "Tout configurer" + bouton "Réessayer" en cas d'erreur
- [x] Loader animé avec placeholder logo (à remplacer par le personnage)
- [x] Message de patience animé (fade in/out)
- [x] Commandes Windows (7 étapes : client → serveur → démarrage → auto → pare-feu → vérif → infos)
- [x] Commandes Linux (5 étapes : install → démarrage → vérif → pare-feu → infos, auto-détection distro)
- [x] Commandes Mac (3 étapes : remote login → vérif → infos)
- [x] Gestion des erreurs (rouge par étape + message global)
- [x] Affichage des infos de connexion (IP, utilisateur, string de connexion)
- [x] Bouton "Copier" sur chaque info
- [ ] Ajouter le logo/personnage animé (en attente de l'image)

## 9. Écran Configuration WoL

- [x] Squelette de l'écran + provider Riverpod
- [x] Carte explicative "Qu'est-ce que ça fait ?"
- [x] Liste des étapes avec StepIndicator (progression visible en temps réel)
- [x] Bouton "Tout configurer" + bouton "Réessayer" en cas d'erreur
- [x] Loader animé + message de patience (fade in/out)
- [x] Commandes Windows (5 étapes : carte Ethernet → Magic Packet → réveil réseau → démarrage rapide → MAC)
- [x] Commandes Linux (5 étapes : ethtool → carte Ethernet → activer WoL → service systemd → MAC)
- [x] Masquer l'écran sur Mac (message "non disponible")
- [x] Avertissement BIOS (carte ambre, toujours visible)
- [x] Affichage de l'adresse MAC + carte réseau + IP à la fin
- [x] Bouton "Copier" sur chaque info
- [x] Rappel BIOS dans la carte résultat
- [x] Gestion des erreurs (rouge par étape + message global)
- [x] Avertissement Linux (WoL pas toujours fiable selon carte/noyau, conseil dual-boot)
- [ ] Ajouter le logo/personnage animé (en attente de l'image)

## 10. Écran Infos connexion

- [x] Squelette de l'écran + provider Riverpod
- [x] Récupération auto de l'IP (Windows/Linux/Mac)
- [x] Récupération auto de l'adresse MAC (Windows/Linux)
- [x] Récupération auto du nom d'utilisateur
- [x] Récupération auto de la carte réseau (Windows/Linux)
- [x] Bouton "Copier" pour chaque info
- [x] Bouton "Rafraîchir" dans le header
- [x] Chargement auto à l'ouverture de l'écran
- [x] Affichage "Non trouvée" si info indisponible

## 11. Écran Réglages

- [x] Toggle thème sombre/clair (fonctionnel)
- [x] Sélecteur de langue FR/EN (fonctionnel)
- [x] Sauvegarde des préférences (SharedPreferences)

## 12. Tests

- [x] Test de base (l'app démarre)
- [ ] Tests unitaires des providers
- [ ] Tests unitaires du CommandRunner
- [ ] Tests d'interface des écrans

## 13. Build & distribution

- [x] Résoudre le problème de linker Linux (Flutter réinstallé via git + lld-18)
- [ ] Build Windows
- [ ] Build macOS
- [ ] Packaging / installeur

## Notes techniques

- Flutter doit être installé via git (pas snap) pour le build Linux
- Le paquet `lld-18` est requis sur Ubuntu (`sudo apt install lld-18`)
- Le Wake-on-LAN sur Linux peut ne pas fonctionner selon la carte réseau et le noyau — fonctionne mieux quand le PC est éteint depuis Windows (dual-boot)
- La vérification WoL du dashboard utilise `systemctl is-enabled wol-enable.service` (pas besoin de sudo)

---

## Prochaines étapes prioritaires

1. ~~**Écran SSH** — Câbler les commandes et l'interface~~ ✓
2. ~~**Écran WoL** — Câbler les commandes WoL~~ ✓
3. ~~**Écran Infos connexion** — Afficher IP/MAC/utilisateur~~ ✓
4. ~~**Badges dashboard** — Afficher l'état de configuration sur les cartes~~ ✓
5. **Tests** — Ajouter les tests unitaires
