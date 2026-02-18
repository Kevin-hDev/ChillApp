// =============================================================
// FIX-054 : Segmentation reseau (anti mouvement lateral)
// GAP-054 : Segmentation reseau absente (P1)
// Cible   : lib/core/security/network_segmentation.dart
// =============================================================
//
// PROBLEME : Le daemon forwarde toute connexion port 22 Tailscale
// vers localhost sans filtrage. Un agent IA compromettant le
// bridge peut pivoter vers le reste du LAN.
//
// SOLUTION :
// 1. Le bridge n'accede QU'AU PC cible configure
// 2. ACLs Tailscale strictes (pas de wildcard)
// 3. Verification cote Flutter que la destination est autorisee
// 4. Template ACL Tailscale et regles iptables pour l'admin
// =============================================================

import 'dart:convert';

/// Configuration de segmentation reseau pour ChillApp.
///
/// Definit l'unique destination autorisee (IP Tailscale du PC cible)
/// et le port SSH associe. En mode strict, tout ce qui ne correspond
/// pas exactement est rejete.
class SegmentationConfig {
  /// IP Tailscale autorisee du PC cible (une seule adresse).
  final String allowedTargetIp;

  /// Port SSH autorise sur le PC cible (defaut : 22).
  final int allowedPort;

  /// En mode strict, tout ecart est bloque. Recommande en production.
  final bool strictMode;

  const SegmentationConfig({
    required this.allowedTargetIp,
    this.allowedPort = 22,
    this.strictMode = true,
  });
}

/// Resultat d'une verification de segmentation.
class SegmentationCheck {
  /// true si la connexion est autorisee.
  final bool allowed;

  /// Raison du blocage (null si autorisee).
  final String? blockedReason;

  const SegmentationCheck({
    required this.allowed,
    this.blockedReason,
  });

  @override
  String toString() => allowed
      ? 'SegmentationCheck(allowed)'
      : 'SegmentationCheck(blocked: $blockedReason)';
}

/// Verificateur de segmentation reseau.
///
/// Toutes les connexions passent par [checkOutgoing] avant
/// d'etre transmises au daemon. Les connexions entrantes sont
/// verifiees par [checkIncoming].
class NetworkSegmentation {
  final SegmentationConfig config;

  /// Plage reseau Tailscale (CGNAT 100.64.0.0/10).
  static const int _tailscaleFirstOctet = 100;
  static const int _tailscaleSecondMin = 64;
  static const int _tailscaleSecondMax = 127;

  NetworkSegmentation({required this.config});

  // ---------------------------------------------------------
  // Verification des connexions sortantes
  // ---------------------------------------------------------

  /// Verifie qu'une connexion sortante est autorisee.
  ///
  /// La destination doit correspondre exactement a [config.allowedTargetIp]
  /// et [config.allowedPort]. Tout autre combinaison est bloquee.
  SegmentationCheck checkOutgoing({
    required String destinationIp,
    required int destinationPort,
  }) {
    // 1. Verifier l'IP de destination
    if (destinationIp != config.allowedTargetIp) {
      return SegmentationCheck(
        allowed: false,
        blockedReason:
            'IP $destinationIp non autorisee — seul ${config.allowedTargetIp} est permis.',
      );
    }

    // 2. Verifier le port de destination
    if (destinationPort != config.allowedPort) {
      return SegmentationCheck(
        allowed: false,
        blockedReason:
            'Port $destinationPort non autorise — seul le port ${config.allowedPort} est permis.',
      );
    }

    return const SegmentationCheck(allowed: true);
  }

  // ---------------------------------------------------------
  // Verification des connexions entrantes
  // ---------------------------------------------------------

  /// Verifie qu'une connexion entrante provient du reseau Tailscale.
  ///
  /// Toute connexion hors de la plage 100.64.0.0/10 est bloquee.
  /// Cette plage est la plage CGNAT reservee a Tailscale.
  SegmentationCheck checkIncoming({required String sourceIp}) {
    final parts = sourceIp.split('.');

    if (parts.length != 4) {
      return const SegmentationCheck(
        allowed: false,
        blockedReason: 'Format IP invalide',
      );
    }

    final octets = <int>[];
    for (final part in parts) {
      final value = int.tryParse(part);
      if (value == null || value < 0 || value > 255) {
        return const SegmentationCheck(
          allowed: false,
          blockedReason: 'Octet IP invalide',
        );
      }
      octets.add(value);
    }

    // Verifier plage 100.64.0.0/10 → premier octet = 100,
    // deuxieme octet entre 64 et 127 inclus.
    if (octets[0] != _tailscaleFirstOctet ||
        octets[1] < _tailscaleSecondMin ||
        octets[1] > _tailscaleSecondMax) {
      return SegmentationCheck(
        allowed: false,
        blockedReason:
            'IP $sourceIp hors du reseau Tailscale (100.64.0.0/10)',
      );
    }

    return const SegmentationCheck(allowed: true);
  }

  // ---------------------------------------------------------
  // Verification que l'IP cible est dans Tailscale
  // ---------------------------------------------------------

  /// Verifie que l'IP configuree est une IP Tailscale valide.
  ///
  /// Utile pour valider la configuration avant de la sauvegarder.
  bool isTargetIpValid() {
    return checkIncoming(sourceIp: config.allowedTargetIp).allowed;
  }

  // ---------------------------------------------------------
  // Generation de templates (statiques)
  // ---------------------------------------------------------

  /// Genere un template ACL Tailscale a deployer dans la console admin.
  ///
  /// Les ACLs resultantes autorisent uniquement le flux SSH
  /// entre le bridge ChillApp et le PC cible. Tout le reste
  /// est refuse implicitement.
  static String generateAclTemplate({
    required String appTag,
    required String targetTag,
    required int sshPort,
  }) {
    final acl = {
      'acls': [
        {
          'action': 'accept',
          'src': ['tag:$appTag'],
          'dst': ['tag:$targetTag:$sshPort'],
        },
        // Le reste est refuse implicitement par Tailscale
      ],
      'tagOwners': {
        'tag:$appTag': ['autogroup:admin'],
        'tag:$targetTag': ['autogroup:admin'],
      },
      'ssh': [
        {
          'action': 'accept',
          'src': ['tag:$appTag'],
          'dst': ['tag:$targetTag'],
          'users': ['autogroup:nonroot'],
        },
      ],
      // Pas de wildcard, pas d'acces Internet, pas d'exit node
    };

    return const JsonEncoder.withIndent('  ').convert(acl);
  }

  /// Genere des regles iptables pour le PC cible.
  ///
  /// Autorise uniquement le SSH depuis l'IP Tailscale du bridge.
  /// Refuse le SSH depuis toute autre source.
  /// Empeche le bridge de scanner le LAN local.
  static String generateIptablesRules({
    required String tailscaleIp,
    required int sshPort,
  }) {
    return '''#!/bin/bash
# Regles iptables pour segmentation ChillApp
# Installer sur le PC cible — necessite les droits root

# Accepter SSH uniquement depuis le bridge Tailscale
iptables -A INPUT -p tcp -s $tailscaleIp --dport $sshPort -j ACCEPT

# Refuser SSH depuis toute autre source
iptables -A INPUT -p tcp --dport $sshPort -j DROP

# Sur le bridge : bloquer tout acces au LAN local
iptables -A OUTPUT -d 192.168.0.0/16 -j DROP
iptables -A OUTPUT -d 10.0.0.0/8 -j DROP
iptables -A OUTPUT -d 172.16.0.0/12 -j DROP

# Autoriser uniquement la plage Tailscale en sortie
iptables -A OUTPUT -d 100.64.0.0/10 -j ACCEPT
''';
  }
}
