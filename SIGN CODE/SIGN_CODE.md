# SIGN CODE CHILL_APP

https://signpath.org/ gratuitement :              
                                                                                
  Conditions :                                                                  
  1. Le projet doit être open source avec une licence reconnue (GPL c'est bon)  
  2. Le projet doit être déjà publié sur GitHub (pas juste le code, une release
  avec le .exe)                                                                 
  3. Le projet doit être activement maintenu                                    
  4. Tous les membres de l'équipe doivent avoir l'authentification à 2 facteurs 
  (MFA) sur GitHub
  5. Il faut un pipeline CI/CD (GitHub Actions) pour construire l'app
  automatiquement — SignPath vérifie que le binaire vient bien de ton code
  source
  6. Il faut publier une politique de signature sur la page du projet
  7. Pas de composant propriétaire dans le code

  Le processus :
  1. Tu publies le projet en open source sur GitHub (licence GPL)
  2. Tu configures GitHub Actions pour builder l'app automatiquement
  3. Tu fais une première release
  4. Tu fais la demande sur https://signpath.org/
  5. Ils vérifient et acceptent (ou pas)
  6. Ensuite, chaque release est signée automatiquement via GitHub Actions

  Le problème pour l'instant : le projet n'est pas encore publié en open source
  et il n'y a pas de CI/CD configuré. Il faudrait d'abord :
  - Choisir la licence GPL (v2 ou v3)
  - Mettre le repo en public
  - Configurer GitHub Actions pour builder le .exe Windows (et .tar.gz Linux)
  - Faire une première release
