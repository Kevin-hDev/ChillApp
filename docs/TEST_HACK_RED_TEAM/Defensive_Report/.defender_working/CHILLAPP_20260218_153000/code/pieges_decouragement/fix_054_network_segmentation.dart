// =============================================================
// FIX-054 : Segmentation reseau (anti mouvement lateral)
// GAP-054: Segmentation reseau absente (P1)
// Cible: lib/core/security/network_segmentation.dart (nouveau)
// =============================================================
//
// PROBLEME : Le daemon forwarde toute connexion port 22 Tailscale
// vers localhost sans filtrage. Un agent IA compromettant le
// bridge peut pivoter vers le reste du LAN.
//
// SOLUTION :
// 1. Le bridge ne doit acceder QU'AU PC cible configure
// 2. ACLs Tailscale strictes sans wildcard
// 3. Verification cote daemon que la destination est autorisee
// 4. Template ACL Tailscale pour l'admin
// =============================================================

import 'dart:io';
import 'dart:convert';

/// Configuration de segmentation reseau.
class SegmentationConfig {
  /// IP Tailscale autorisee du PC cible (unique).
  final String allowedTargetIp;

  /// Port SSH autorise sur le PC cible.
  final int allowedPort;

  /// Autoriser uniquement les connexions sortantes vers le PC cible.
  final bool strictMode;

  const SegmentationConfig({
    required this.allowedTargetIp,
    this.allowedPort = 22,
    this.strictMode = true,
  });
}

/// Resultat de la verification de segmentation.
class SegmentationCheck {
  final bool allowed;
  final String? blockedReason;

  const SegmentationCheck({
    required this.allowed,
    this.blockedReason,
  });
}

/// Verificateur de segmentation reseau.
class NetworkSegmentation {
  final SegmentationConfig config;

  NetworkSegmentation({required this.config});

  /// Verifie qu'une connexion sortante est autorisee.
  SegmentationCheck checkOutgoing({
    required String destinationIp,
    required int destinationPort,
  }) {
    // 1. Verifier que la destination est l'IP autorisee
    if (destinationIp != config.allowedTargetIp) {
      return SegmentationCheck(
        allowed: false,
        blockedReason: 'IP $destinationIp non autorisee. '
            'Seul ${config.allowedTargetIp} est autorise.',
      );
    }

    // 2. Verifier le port
    if (destinationPort != config.allowedPort) {
      return SegmentationCheck(
        allowed: false,
        blockedReason: 'Port $destinationPort non autorise. '
            'Seul le port ${config.allowedPort} est autorise.',
      );
    }

    return const SegmentationCheck(allowed: true);
  }

  /// Verifie qu'une connexion entrante est depuis Tailscale.
  SegmentationCheck checkIncoming({
    required String sourceIp,
  }) {
    // Doit etre une IP Tailscale (100.64.0.0/10)
    final parts = sourceIp.split('.');
    if (parts.length != 4) {
      return const SegmentationCheck(
        allowed: false,
        blockedReason: 'IP source invalide',
      );
    }
    final bytes = parts.map(int.tryParse).toList();
    if (bytes.any((b) => b == null)) {
      return const SegmentationCheck(
        allowed: false,
        blockedReason: 'IP source invalide',
      );
    }
    if (bytes[0] != 100 || bytes[1]! < 64 || bytes[1]! > 127) {
      return SegmentationCheck(
        allowed: false,
        blockedReason: 'IP source $sourceIp n\'est pas dans le reseau Tailscale',
      );
    }

    return const SegmentationCheck(allowed: true);
  }

  /// Template ACL Tailscale recommande.
  /// A deployer dans la console admin Tailscale.
  static String generateAclTemplate({
    required String appTag,
    required String targetTag,
    required int sshPort,
  }) {
    return jsonEncode({
      'acls': [
        {
          'action': 'accept',
          'src': ['tag:$appTag'],
          'dst': ['tag:$targetTag:$sshPort'],
        },
        // Bloquer tout le reste implicitement
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
      // Pas de wildcard, pas de acces Internet
      // Pas de exit node autorise
    });
  }

  /// Genere des regles iptables pour le PC cible.
  static String generateIptablesRules({
    required String tailscaleIp,
    required int sshPort,
  }) {
    return '''#!/bin/bash
# Regles iptables pour segmentation ChillApp
# Autoriser uniquement le SSH depuis le bridge Tailscale

# Accepter SSH depuis le bridge
iptables -A INPUT -p tcp -s $tailscaleIp --dport $sshPort -j ACCEPT

# Refuser SSH depuis toute autre source
iptables -A INPUT -p tcp --dport $sshPort -j DROP

# Empecher le bridge de scanner le LAN
# (a appliquer sur le bridge)
iptables -A OUTPUT -d 192.168.0.0/16 -j DROP
iptables -A OUTPUT -d 10.0.0.0/8 -j DROP
iptables -A OUTPUT -d 172.16.0.0/12 -j DROP
# Autoriser uniquement Tailscale
iptables -A OUTPUT -d 100.64.0.0/10 -j ACCEPT
''';
  }
}

// =============================================================
// INTEGRATION :
// =============================================================
//
// 1. Dans le daemon Go, avant chaque forwarding :
//   segmentation := NetworkSegmentation{AllowedTarget: "100.64.x.x"}
//   if !segmentation.CheckOutgoing(destIP, destPort) {
//     log.Warn("Blocked: unauthorized destination")
//     return
//   }
//
// 2. Dans l'app Flutter, configurer l'IP cible :
//   final seg = NetworkSegmentation(config: SegmentationConfig(
//     allowedTargetIp: userConfiguredTargetIp,
//   ));
//
// 3. Deployer les ACLs Tailscale :
//   final aclTemplate = NetworkSegmentation.generateAclTemplate(
//     appTag: 'chillapp-bridge',
//     targetTag: 'chillapp-target',
//     sshPort: 22,
//   );
//   // Copier dans la console admin Tailscale
// =============================================================
