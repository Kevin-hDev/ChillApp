# Guide Configuration SonarCloud — Chill Desktop

**Objectif :** Scanner le projet Chill Desktop avec SonarCloud pour l'analyse de qualité + sécurité.

---

## ✅ Étape 1 : Créer un Compte SonarCloud (Gratuit pour Open Source)

1. **Aller sur** : https://sonarcloud.io/
2. **Cliquer sur** "Start now" ou "Log in"
3. **Se connecter avec GitHub** (recommandé pour projets open source)
   - Autoriser SonarCloud à accéder à tes repos
4. **Créer une organisation** :
   - Nom : Ex: `kevin-huynh-dev` ou `chillshell-project`
   - Key : Ex: `kevin-huynh-dev` (sera utilisé dans `sonar-project.properties`)
   - Choisir "Free plan" pour open source

---

## ✅ Étape 2 : Créer le Projet

1. **Dans SonarCloud**, cliquer sur "+" → "Analyze new project"
2. **Choisir "Manually"** (pas via GitHub CI/CD pour l'instant)
3. **Remplir** :
   - Project key : `chill-desktop` (déjà configuré dans `sonar-project.properties`)
   - Display name : `Chill Desktop`
   - Visibility : Public (pour open source)
4. **Cliquer sur** "Set Up"

---

## ✅ Étape 3 : Obtenir le Token

1. **Après création du projet**, SonarCloud affiche les instructions
2. **Choisir** "Locally" (analyse locale)
3. **Générer un token** :
   - Name : Ex: `chill-desktop-local-scan`
   - Type : User Token
   - **Copier le token** (ex: `squ_abc123...`) — **NE PAS le commiter !**

---

## ✅ Étape 4 : Mettre à Jour la Configuration

**Éditer** `sonar-project.properties` :

```properties
sonar.organization=VOTRE_ORGANISATION_ICI
```

Remplacer `VOTRE_ORGANISATION_ICI` par le **key** de ton organisation (ex: `kevin-huynh-dev`).

---

## ✅ Étape 5 : Lancer le Scan

**Dans le terminal** (depuis `/home/huynh-kevin/projects/ChillApp`) :

```bash
# Option 1 : Token en variable d'environnement (recommandé)
export SONAR_TOKEN="squ_abc123..."
sonar-scanner

# Option 2 : Token en argument (moins sécurisé)
sonar-scanner -Dsonar.token="squ_abc123..."
```

**Le scan prendra quelques minutes** et analysera :
- 51 fichiers Dart/Flutter
- 1 fichier Go (daemon Tailscale)
- 2 fichiers Shell
- 5 fichiers YAML

---

## ✅ Étape 6 : Voir les Résultats

1. **Le scanner affichera l'URL** : Ex: https://sonarcloud.io/dashboard?id=chill-desktop
2. **Ouvrir dans le navigateur** pour voir :
   - **Quality Gate** (Pass/Fail)
   - **Bugs** détectés
   - **Vulnerabilities** (sécurité)
   - **Code Smells** (qualité)
   - **Security Hotspots** (points à vérifier)
   - **Coverage** (si tests)
   - **Duplications** (code dupliqué)

---

## 📊 Résultats Attendus

Basé sur les scans précédents (Semgrep + Flutter analyze), on s'attend à :
- ✅ **0 vulnerabilities** (déjà validé par Semgrep + Flutter analyze)
- ✅ **0 bugs** (code propre)
- ⚠️ Possiblement quelques **Code Smells** (améliorations qualité)
- ⚠️ Possiblement quelques **Security Hotspots** à vérifier manuellement

---

## 🔒 Sécurité du Token

**⚠️ IMPORTANT :**
- ❌ **NE JAMAIS commiter le token** dans git
- ✅ **Ajouter** `.sonar/` et `*.sonar` dans `.gitignore`
- ✅ **Utiliser** des variables d'environnement ou des secrets

**Pour CI/CD plus tard** (GitHub Actions) :
- Stocker le token dans **GitHub Secrets** (`SONAR_TOKEN`)
- Utiliser le workflow SonarCloud officiel

---

## 🆘 Besoin d'Aide ?

**Si problème pendant le scan :**
1. Vérifier que l'organisation est correcte dans `sonar-project.properties`
2. Vérifier que le token est valide (pas expiré)
3. Vérifier les logs du scanner (`sonar-scanner -X` pour mode verbose)
4. Consulter la documentation : https://docs.sonarcloud.io/

---

## 📝 Notes

- **SonarCloud est gratuit** pour les projets open source publics
- **Limite** : 100k lignes de code par projet (Chill est ~5-10k LOC → OK)
- **Analyses illimitées** pour open source
- **Support Dart/Flutter** via plugin community (détection automatique)

---

**Après avoir suivi ces étapes, reviens me dire si le scan a fonctionné !** 🚀
