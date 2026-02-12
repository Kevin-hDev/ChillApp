const Map<String, Map<String, String>> translations = {
  'fr': {
    // Général
    'app.title': 'Chill',
    'app.subtitle': 'Hub de configuration',

    // Navigation
    'nav.dashboard': 'Accueil',
    'nav.ssh': 'Configuration SSH',
    'nav.wol': 'Wake-on-LAN',
    'nav.info': 'Infos connexion',
    'nav.settings': 'Réglages',

    // Dashboard
    'dashboard.welcome': 'Bienvenue sur Chill',
    'dashboard.description': 'Configure tes apps Chill en quelques clics.',
    'dashboard.ssh.title': 'Configuration SSH',
    'dashboard.ssh.desc': 'Installe et active SSH pour ChillShell.',
    'dashboard.wol.title': 'Wake-on-LAN',
    'dashboard.wol.desc': 'Allume ton PC avec ton téléphone.',
    'dashboard.info.title': 'Infos connexion',
    'dashboard.info.desc': 'IP, MAC, nom d\'utilisateur.',

    // SSH Setup
    'ssh.title': 'Configuration SSH',
    'ssh.intro': 'Installe et active le serveur SSH pour que ChillShell puisse se connecter à ce PC.',
    'ssh.explanation.title': 'Qu\'est-ce que ça fait ?',
    'ssh.explanation.content': 'Cette configuration installe un service appelé SSH sur ton ordinateur. '
        'SSH permet à ChillShell (l\'app mobile) de se connecter à ce PC à distance, '
        'comme une télécommande sécurisée. '
        'Concrètement, on va installer le logiciel nécessaire, l\'activer, '
        'et s\'assurer que le pare-feu ne bloque pas la connexion. '
        'Rien de dangereux — c\'est un outil standard utilisé par des millions de personnes.',
    'ssh.configureAll': 'Tout configurer',
    'ssh.patience': 'Cela peut prendre plusieurs minutes',
    'ssh.step.installClient': 'Installer le client OpenSSH',
    'ssh.step.installServer': 'Installer le serveur OpenSSH',
    'ssh.step.install': 'Installer OpenSSH',
    'ssh.step.start': 'Démarrer le service SSH',
    'ssh.step.autostart': 'Activer SSH au démarrage',
    'ssh.step.firewall': 'Configurer le pare-feu',
    'ssh.step.verify': 'Vérifier que SSH fonctionne',
    'ssh.step.info': 'Récupérer les infos de connexion',
    'ssh.step.enableRemoteLogin': 'Activer l\'accès à distance',
    'ssh.result.title': 'Configuration terminée !',
    'ssh.result.ipEthernet': 'Adresse IP Ethernet',
    'ssh.result.ipWifi': 'Adresse IP WiFi',
    'ssh.result.username': 'Ton nom d\'utilisateur',
    'ssh.result.connectEthernet': 'Connexion via Ethernet :',
    'ssh.result.connectWifi': 'Connexion via WiFi :',
    'ssh.error.title': 'Une erreur est survenue',
    'ssh.error.retry': 'Réessayer',

    // WoL Setup
    'wol.title': 'Configuration Wake-on-LAN',
    'wol.intro': 'Active le Wake-on-LAN pour pouvoir allumer ce PC avec ton téléphone via ChillShell.',
    'wol.biosWarning': 'Le BIOS doit être configuré manuellement (consulte le tuto BIOS sur le site).',
    'wol.notAvailableMac': 'Le Wake-on-LAN n\'est pas disponible sur Mac en V1.',
    'wol.configureAll': 'Tout configurer',
    'wol.step.findAdapter': 'Trouver la carte Ethernet',
    'wol.step.enableMagicPacket': 'Activer Wake on Magic Packet',
    'wol.step.enableWake': 'Autoriser le réveil réseau',
    'wol.step.disableFastStartup': 'Désactiver le démarrage rapide',
    'wol.step.persist': 'Rendre le WoL permanent',
    'wol.step.showMac': 'Afficher l\'adresse MAC',
    'wol.step.installEthtool': 'Installer ethtool',
    'wol.step.enableWol': 'Activer le Wake-on-LAN',
    'wol.explanation.title': 'Qu\'est-ce que ça fait ?',
    'wol.explanation.content': 'Le Wake-on-LAN (WoL) permet d\'allumer ton PC avec ton téléphone, tant que tu es connecté au même WiFi. '
        'ChillShell envoie un signal spécial appelé "Magic Packet" à ta carte réseau, '
        'et celle-ci allume ton PC même quand il est éteint. '
        'On va activer cette fonctionnalité sur ta carte réseau '
        'et s\'assurer que ça reste actif après chaque redémarrage. '
        'Ton PC doit être branché en Ethernet (pas en WiFi) pour que ça fonctionne.',
    'wol.patience': 'Cela peut prendre quelques instants',
    'wol.result.title': 'Configuration terminée !',
    'wol.result.mac': 'Ton adresse MAC (entre-la dans ChillShell)',
    'wol.result.adapter': 'Carte réseau',
    'wol.result.ipEthernet': 'Adresse IP Ethernet',
    'wol.result.ipWifi': 'Adresse IP WiFi',
    'wol.result.reminder': 'N\'oublie pas de configurer ton BIOS ! '
        'Le WoL ne fonctionnera pas sans la configuration BIOS. '
        'Consulte le tuto BIOS sur le site ChillShell.',
    'wol.error.retry': 'Réessayer',
    'wol.linuxWarning': 'Sur Linux, le Wake-on-LAN peut ne pas fonctionner selon ta carte réseau '
        'et ton noyau Linux. Le WoL fonctionne de manière plus fiable quand le PC '
        'est éteint depuis Windows. Si tu fais du dual-boot, éteins depuis Windows '
        'avant d\'essayer d\'allumer via WoL.',

    // Tailscale
    'dashboard.tailscale.title': 'Tailscale',
    'dashboard.tailscale.desc': 'Accède à ton PC de n\'importe où.',
    'tailscale.title': 'Tailscale',
    'tailscale.intro': 'Accède à ce PC depuis n\'importe où grâce à Tailscale, intégré directement dans Chill.',
    'tailscale.explanation.title': 'Qu\'est-ce que Tailscale ?',
    'tailscale.explanation.content': 'Tailscale crée un réseau privé entre tes appareils, accessible depuis n\'importe où dans le monde. '
        'Contrairement au WiFi local, Tailscale fonctionne même si tu es dans un café, au travail ou en 4G. '
        'ChillShell peut se connecter à ce PC via son adresse Tailscale, sans configuration de routeur ni ouverture de ports. '
        'C\'est comme un VPN, mais simple et gratuit pour un usage personnel.',
    'tailscale.login.title': 'Se connecter à Tailscale',
    'tailscale.login.desc': 'Connecte-toi avec ton compte Tailscale. Ton navigateur va s\'ouvrir pour l\'authentification.',
    'tailscale.login.button': 'Se connecter',
    'tailscale.login.waiting': 'En attente de connexion... Vérifie ton navigateur.',
    'tailscale.signup.button': 'Créer un compte',
    'tailscale.signup.desc': 'Pas encore de compte Tailscale ? C\'est gratuit.',
    'tailscale.error.retry': 'Réessayer',
    'tailscale.error.daemonNotFound': 'Le moteur Tailscale est introuvable. Réinstalle l\'application.',
    'tailscale.connected.title': 'Connecté',
    'tailscale.connected.selfTitle': 'Ce PC sur Tailscale',
    'tailscale.connected.hostname': 'Nom de la machine',
    'tailscale.connected.ip': 'Adresse Tailscale',
    'tailscale.connected.peersTitle': 'Appareils sur ton réseau',
    'tailscale.connected.noPeers': 'Aucun autre appareil trouvé. Installe Tailscale sur un autre appareil pour le voir ici.',
    'tailscale.connected.online': 'En ligne',
    'tailscale.connected.offline': 'Hors ligne',
    'tailscale.connected.logout': 'Se déconnecter',
    'tailscale.error.title': 'Une erreur est survenue',
    'status.connected': 'Connecté',
    'status.notConnected': 'Non connecté',

    // Connection Info
    'info.title': 'Infos de connexion',
    'info.intro': 'Voici les informations à entrer dans ChillShell.',
    'info.ipEthernet': 'Adresse IP Ethernet',
    'info.ipWifi': 'Adresse IP WiFi',
    'info.mac': 'Adresse MAC',
    'info.username': 'Nom d\'utilisateur',
    'info.adapter': 'Carte réseau',
    'info.copy': 'Copier',
    'info.copied': 'Copié !',
    'info.refresh': 'Rafraîchir',
    'info.notFound': 'Non trouvée',
    'info.recommend.title': 'Recommandé : utilise Tailscale',
    'info.recommend.content': 'Les adresses IP ci-dessus changent régulièrement et ne fonctionnent que sur ton réseau local. '
        'Pour une connexion sécurisée et stable depuis n\'importe où, utilise plutôt ton adresse IP Tailscale. '
        'Rends-toi sur l\'onglet Tailscale pour créer ton compte et te connecter.',
    'info.recommend.button': 'Aller sur Tailscale',

    // Settings
    'settings.title': 'Réglages',
    'settings.theme': 'Thème',
    'settings.themeDark': 'Sombre',
    'settings.themeLight': 'Clair',
    'settings.language': 'Langue',
    'settings.langFr': 'Français',
    'settings.langEn': 'English',
    'settings.lock': 'Verrouillage PIN',
    'settings.lock.desc': 'Protège l\'accès à l\'application',
    'settings.lock.change': 'Changer le PIN',
    'settings.lock.new': 'Choisis un code PIN à 8 chiffres',
    'settings.lock.confirm': 'Confirme ton code PIN',
    'settings.lock.mismatch': 'Les codes PIN ne correspondent pas',
    'settings.lock.enterCurrent': 'Entre ton PIN actuel',
    'settings.lock.warning': 'Choisis un code dont tu te souviendras. '
        'Aucune procédure de réinitialisation n\'est disponible. '
        'Si tu oublies ton PIN, tu devras réinstaller l\'application.',

    // Lock
    'lock.title': 'Déverrouiller Chill',
    'lock.enter': 'Entre ton code PIN',
    'lock.error': 'Code PIN incorrect',
    'lock.tooMany': 'Trop de tentatives. Réessaye dans 30 secondes.',

    // États
    'status.pending': 'En attente',
    'status.running': 'En cours...',
    'status.success': 'OK',
    'status.error': 'Erreur',
    'status.configured': 'Configuré',
    'status.notConfigured': 'Pas encore configuré',
  },
  'en': {
    // General
    'app.title': 'Chill',
    'app.subtitle': 'Configuration Hub',

    // Navigation
    'nav.dashboard': 'Home',
    'nav.ssh': 'SSH Setup',
    'nav.wol': 'Wake-on-LAN',
    'nav.info': 'Connection Info',
    'nav.settings': 'Settings',

    // Dashboard
    'dashboard.welcome': 'Welcome to Chill',
    'dashboard.description': 'Set up your Chill apps in a few clicks.',
    'dashboard.ssh.title': 'SSH Setup',
    'dashboard.ssh.desc': 'Install and activate SSH for ChillShell.',
    'dashboard.wol.title': 'Wake-on-LAN',
    'dashboard.wol.desc': 'Turn on your PC with your phone.',
    'dashboard.info.title': 'Connection Info',
    'dashboard.info.desc': 'IP, MAC, username.',

    // SSH Setup
    'ssh.title': 'SSH Setup',
    'ssh.intro': 'Install and activate the SSH server so ChillShell can connect to this PC.',
    'ssh.explanation.title': 'What does this do?',
    'ssh.explanation.content': 'This setup installs a service called SSH on your computer. '
        'SSH allows ChillShell (the mobile app) to connect to this PC remotely, '
        'like a secure remote control. '
        'We will install the necessary software, activate it, '
        'and make sure the firewall doesn\'t block the connection. '
        'Nothing dangerous — it\'s a standard tool used by millions of people.',
    'ssh.configureAll': 'Configure All',
    'ssh.patience': 'This may take a few minutes',
    'ssh.step.installClient': 'Install OpenSSH client',
    'ssh.step.installServer': 'Install OpenSSH server',
    'ssh.step.install': 'Install OpenSSH',
    'ssh.step.start': 'Start SSH service',
    'ssh.step.autostart': 'Enable SSH on startup',
    'ssh.step.firewall': 'Configure firewall',
    'ssh.step.verify': 'Verify SSH is running',
    'ssh.step.info': 'Retrieve connection info',
    'ssh.step.enableRemoteLogin': 'Enable remote login',
    'ssh.result.title': 'Setup complete!',
    'ssh.result.ipEthernet': 'Ethernet IP Address',
    'ssh.result.ipWifi': 'WiFi IP Address',
    'ssh.result.username': 'Your username',
    'ssh.result.connectEthernet': 'Connect via Ethernet:',
    'ssh.result.connectWifi': 'Connect via WiFi:',
    'ssh.error.title': 'An error occurred',
    'ssh.error.retry': 'Retry',

    // WoL Setup
    'wol.title': 'Wake-on-LAN Setup',
    'wol.intro': 'Enable Wake-on-LAN to turn on this PC with your phone via ChillShell.',
    'wol.biosWarning': 'BIOS must be configured manually (see the BIOS tutorial on the website).',
    'wol.notAvailableMac': 'Wake-on-LAN is not available on Mac in V1.',
    'wol.configureAll': 'Configure All',
    'wol.step.findAdapter': 'Find Ethernet adapter',
    'wol.step.enableMagicPacket': 'Enable Wake on Magic Packet',
    'wol.step.enableWake': 'Enable network wake',
    'wol.step.disableFastStartup': 'Disable Fast Startup',
    'wol.step.persist': 'Make WoL persistent',
    'wol.step.showMac': 'Show MAC address',
    'wol.step.installEthtool': 'Install ethtool',
    'wol.step.enableWol': 'Enable Wake-on-LAN',
    'wol.explanation.title': 'What does this do?',
    'wol.explanation.content': 'Wake-on-LAN (WoL) lets you turn on your PC with your phone, as long as you\'re on the same WiFi. '
        'ChillShell sends a special signal called a "Magic Packet" to your network card, '
        'which powers on your PC even when it\'s off. '
        'We will enable this feature on your network card '
        'and make sure it stays active after each reboot. '
        'Your PC must be connected via Ethernet (not WiFi) for this to work.',
    'wol.patience': 'This may take a moment',
    'wol.result.title': 'Setup complete!',
    'wol.result.mac': 'Your MAC address (enter it in ChillShell)',
    'wol.result.adapter': 'Network adapter',
    'wol.result.ipEthernet': 'Ethernet IP Address',
    'wol.result.ipWifi': 'WiFi IP Address',
    'wol.result.reminder': 'Don\'t forget to configure your BIOS! '
        'WoL won\'t work without the BIOS configuration. '
        'Check the BIOS tutorial on the ChillShell website.',
    'wol.error.retry': 'Retry',
    'wol.linuxWarning': 'On Linux, Wake-on-LAN may not work depending on your network card '
        'and Linux kernel. WoL works more reliably when the PC is shut down from Windows. '
        'If you dual-boot, shut down from Windows before trying to wake via WoL.',

    // Tailscale
    'dashboard.tailscale.title': 'Tailscale',
    'dashboard.tailscale.desc': 'Access your PC from anywhere.',
    'tailscale.title': 'Tailscale',
    'tailscale.intro': 'Access this PC from anywhere with Tailscale, built right into Chill.',
    'tailscale.explanation.title': 'What is Tailscale?',
    'tailscale.explanation.content': 'Tailscale creates a private network between your devices, accessible from anywhere in the world. '
        'Unlike local WiFi, Tailscale works even if you\'re at a cafe, at work, or on cellular data. '
        'ChillShell can connect to this PC via its Tailscale address, without router configuration or opening ports. '
        'It\'s like a VPN, but simple and free for personal use.',
    'tailscale.login.title': 'Connect to Tailscale',
    'tailscale.login.desc': 'Sign in with your Tailscale account. Your browser will open for authentication.',
    'tailscale.login.button': 'Sign in',
    'tailscale.login.waiting': 'Waiting for sign-in... Check your browser.',
    'tailscale.signup.button': 'Create account',
    'tailscale.signup.desc': 'No Tailscale account yet? It\'s free.',
    'tailscale.error.retry': 'Try again',
    'tailscale.error.daemonNotFound': 'Tailscale engine not found. Reinstall the application.',
    'tailscale.connected.title': 'Connected',
    'tailscale.connected.selfTitle': 'This PC on Tailscale',
    'tailscale.connected.hostname': 'Machine name',
    'tailscale.connected.ip': 'Tailscale address',
    'tailscale.connected.peersTitle': 'Devices on your network',
    'tailscale.connected.noPeers': 'No other devices found. Install Tailscale on another device to see it here.',
    'tailscale.connected.online': 'Online',
    'tailscale.connected.offline': 'Offline',
    'tailscale.connected.logout': 'Sign out',
    'tailscale.error.title': 'An error occurred',
    'status.connected': 'Connected',
    'status.notConnected': 'Not connected',

    // Connection Info
    'info.title': 'Connection Info',
    'info.intro': 'Here is the information to enter in ChillShell.',
    'info.ipEthernet': 'Ethernet IP Address',
    'info.ipWifi': 'WiFi IP Address',
    'info.mac': 'MAC Address',
    'info.username': 'Username',
    'info.adapter': 'Network adapter',
    'info.copy': 'Copy',
    'info.copied': 'Copied!',
    'info.refresh': 'Refresh',
    'info.notFound': 'Not found',
    'info.recommend.title': 'Recommended: use Tailscale',
    'info.recommend.content': 'The IP addresses above change regularly and only work on your local network. '
        'For a secure and stable connection from anywhere, use your Tailscale IP address instead. '
        'Go to the Tailscale tab to create your account and connect.',
    'info.recommend.button': 'Go to Tailscale',

    // Settings
    'settings.title': 'Settings',
    'settings.theme': 'Theme',
    'settings.themeDark': 'Dark',
    'settings.themeLight': 'Light',
    'settings.language': 'Language',
    'settings.langFr': 'Français',
    'settings.langEn': 'English',
    'settings.lock': 'PIN Lock',
    'settings.lock.desc': 'Protect access to the application',
    'settings.lock.change': 'Change PIN',
    'settings.lock.new': 'Choose an 8-digit PIN',
    'settings.lock.confirm': 'Confirm your PIN',
    'settings.lock.mismatch': 'PINs do not match',
    'settings.lock.enterCurrent': 'Enter your current PIN',
    'settings.lock.warning': 'Choose a code you will remember. '
        'No reset procedure is available. '
        'If you forget your PIN, you will need to reinstall the application.',

    // Lock
    'lock.title': 'Unlock Chill',
    'lock.enter': 'Enter your PIN',
    'lock.error': 'Incorrect PIN',
    'lock.tooMany': 'Too many attempts. Try again in 30 seconds.',

    // States
    'status.pending': 'Pending',
    'status.running': 'Running...',
    'status.success': 'OK',
    'status.error': 'Error',
    'status.configured': 'Configured',
    'status.notConfigured': 'Not yet configured',
  },
};
