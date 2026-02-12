1. La Partie Technique (Le "Moteur")
Pour que ton application communique avec le réseau sans l'app officielle, elle doit embarquer son propre client.

Bibliothèque utilisée : tsnet (développée par Tailscale en Go).

Rôle : Transforme ton application en un "appareil" (nœud) sur ton réseau privé.

Résultat : Dès que l'app est lancée et authentifiée, elle obtient sa propre adresse IP en 100.x.y.z.

2. Le Flux d'Authentification
C'est ce qui remplace la connexion manuelle.

Le Bouton : Un bouton "Connexion Tailscale" dans ton interface.

La Webview : L'app ouvre une fenêtre sécurisée pour que l'utilisateur se logue (Google, Microsoft, etc.).

Le Jeton (Token) : Tailscale renvoie une clé d'autorisation à l'application.

Activation : L'application utilise cette clé pour activer le tunnel chiffré en arrière-plan.

3. L'Interface de Recopie (Dashboard)
Voici ce que Claude doit créer visuellement dans ton application :
Élément,Fonctionnalité
Status Bar, "Affiche si le tunnel Tailscale est ""Connecté"" ou ""Déconnecté""."
Mon IP, Affiche l'adresse IP Tailscale du téléphone avec un bouton [Copier].
Liste des Nodes, "Affiche tous les autres appareils (PC, Serveurs) du compte."
Détails Nodes, Nom de la machine + IP Tailscale + bouton [Copier].

4. Instructions

Prompt de Développement
"Claude, je souhaite intégrer nativement Tailscale dans mon application mobile (actuellement utilisée pour du SSH/WOL) pour centraliser la gestion des IPs. Voici la marche à suivre :

Moteur Réseau : Utilise la bibliothèque tsnet pour que l'application devienne un nœud autonome du réseau Tailscale.

Auth : Implémente le flux OAuth 2.0 pour l'authentification utilisateur directe dans l'application.

API : Utilise l'API REST de Tailscale pour récupérer la liste (devices) de toutes les machines du réseau de l'utilisateur.

Interface : Crée une page 'Gestion réseau' affichant l'IP du smartphone et la liste des IPs des autres machines.

Action : Chaque adresse IP doit être accompagnée d'un bouton permettant de la copier dans le presse-papier pour une utilisation dans mes formulaires de connexion SSH/WOL."

💡 Note Importante
Une fois l'adresse IP copiée, l'utilisateur n'a plus qu'à la coller dans ta configuration SSH habituelle (qu'il soit en Wi-Fi, 4G ou 5G), car le tunnel tsnet tourne de façon invisible au sein de ton application.
