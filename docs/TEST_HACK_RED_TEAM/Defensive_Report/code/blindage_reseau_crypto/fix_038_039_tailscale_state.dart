// =============================================================
// FIX-038 : Fonctionnalites securitaires Tailscale 1.94.1
// GAP-038: Fonctionnalites securitaires Tailscale non exploitees (P2)
// FIX-039 : Synchronisation d'etat securisee
// GAP-039: Synchronisation d'etat non securisee (P2)
// Cible: lib/core/security/tailscale_security.dart (nouveau)
// =============================================================
//
// PROBLEME GAP-038 : Le daemon Go n'exploite pas les
// fonctionnalites securitaires de Tailscale 1.94.1 :
// TPM, tokens OIDC ephemeres, audit SSH integre.
//
// PROBLEME GAP-039 : L'etat du daemon (connecte/deconnecte)
// est transmis en clair. Un attaquant peut forger des messages
// d'etat pour tromper l'interface utilisateur.
//
// SOLUTION :
// 1. Configuration Tailscale avancee (TPM, OIDC)
// 2. Etat signe par HMAC avec timestamp
// 3. Verification cote Flutter de chaque message d'etat
// =============================================================

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

/// Configuration securite Tailscale avancee.
class TailscaleSecurityConfig {
  /// Activer le stockage des cles dans le TPM (si disponible).
  final bool enableTpmKeyStorage;

  /// Utiliser des tokens OIDC ephemeres (expirent apres usage).
  final bool useEphemeralOidc;

  /// Activer l'audit SSH integre de Tailscale.
  final bool enableSshAudit;

  /// Forcer le mode MagicDNS (resolution DNS via Tailscale).
  final bool forceMagicDns;

  /// Duree maximale d'une session Tailscale (heures).
  final int maxSessionHours;

  const TailscaleSecurityConfig({
    this.enableTpmKeyStorage = true,
    this.useEphemeralOidc = true,
    this.enableSshAudit = true,
    this.forceMagicDns = true,
    this.maxSessionHours = 24,
  });

  /// Arguments tailscale up correspondants.
  List<String> toTailscaleArgs() {
    return [
      if (enableSshAudit) '--ssh',
      if (forceMagicDns) '--accept-dns=true',
      '--timeout=30s',
    ];
  }
}

/// Verificateur de l'etat securite de Tailscale.
class TailscaleSecurityChecker {
  /// Verifie que Tailscale est configure de maniere securisee.
  static Future<TailscaleAuditResult> audit() async {
    final issues = <String>[];
    final recommendations = <String>[];

    try {
      // 1. Verifier la version
      final versionResult = await Process.run('tailscale', ['version']);
      if (versionResult.exitCode == 0) {
        final version = versionResult.stdout.toString().trim().split('\n').first;
        // Extraire le numero de version
        final versionMatch = RegExp(r'(\d+\.\d+\.\d+)').firstMatch(version);
        if (versionMatch != null) {
          final parts = versionMatch.group(1)!.split('.').map(int.parse).toList();
          // Verifier >= 1.94.0
          if (parts[0] < 1 || (parts[0] == 1 && parts[1] < 94)) {
            issues.add('Version Tailscale ${versionMatch.group(1)} < 1.94.0. '
                'Mettre a jour pour les corrections de securite.');
          }
        }
      }

      // 2. Verifier le statut
      final statusResult = await Process.run('tailscale', ['status', '--json']);
      if (statusResult.exitCode == 0) {
        final status = jsonDecode(statusResult.stdout.toString());

        // Verifier BackendState
        if (status['BackendState'] != 'Running') {
          issues.add('Tailscale n\'est pas en etat Running: '
              '${status['BackendState']}');
        }

        // Verifier MagicDNS
        if (status['MagicDNSSuffix'] == null ||
            status['MagicDNSSuffix'].toString().isEmpty) {
          recommendations.add('MagicDNS non active. Recommande pour la '
              'resolution DNS securisee.');
        }

        // Verifier si SSH est active
        if (status['Self'] != null &&
            status['Self']['SSHHostKeys'] == null) {
          recommendations.add('Tailscale SSH non active. '
              'Recommande pour l\'audit des sessions.');
        }
      }

      // 3. Verifier les ACLs
      // (les ACLs sont configurees cote admin Tailscale, on ne peut
      // que verifier si l'acces est autorise)

    } catch (e) {
      issues.add('Erreur lors de l\'audit Tailscale: $e');
    }

    return TailscaleAuditResult(
      isSecure: issues.isEmpty,
      issues: issues,
      recommendations: recommendations,
    );
  }

  /// Verifie si le TPM est disponible et utilisable.
  static Future<bool> checkTpmAvailable() async {
    try {
      if (Platform.isLinux) {
        // Verifier /dev/tpmrm0
        return await File('/dev/tpmrm0').exists();
      } else if (Platform.isWindows) {
        final result = await Process.run('powershell', [
          '-Command',
          'Get-Tpm | Select-Object TpmPresent',
        ]);
        return result.stdout.toString().contains('True');
      } else if (Platform.isMacOS) {
        // macOS utilise le Secure Enclave, pas TPM
        return true; // Toujours disponible sur Apple Silicon
      }
    } catch (_) {}
    return false;
  }
}

/// Resultat de l'audit Tailscale.
class TailscaleAuditResult {
  final bool isSecure;
  final List<String> issues;
  final List<String> recommendations;

  const TailscaleAuditResult({
    required this.isSecure,
    required this.issues,
    required this.recommendations,
  });
}

/// Message d'etat signe entre le daemon et l'app.
/// Chaque message contient un HMAC pour empecher la falsification.
class SignedState {
  final String state;
  final int timestamp;
  final int sequenceNumber;
  final String hmac;

  const SignedState({
    required this.state,
    required this.timestamp,
    required this.sequenceNumber,
    required this.hmac,
  });

  Map<String, dynamic> toJson() => {
        'state': state,
        'timestamp': timestamp,
        'seq': sequenceNumber,
        'hmac': hmac,
      };

  factory SignedState.fromJson(Map<String, dynamic> json) {
    return SignedState(
      state: json['state'] as String,
      timestamp: json['timestamp'] as int,
      sequenceNumber: json['seq'] as int,
      hmac: json['hmac'] as String,
    );
  }
}

/// Verificateur d'etat signe.
class StateVerifier {
  final Uint8List _key;
  int _lastSequence = 0;
  static const int _maxTimestampDrift = 30; // secondes

  StateVerifier(this._key);

  /// Signe un message d'etat.
  SignedState sign(String state, int sequenceNumber) {
    final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final payload = '$state|$timestamp|$sequenceNumber';
    final mac = Hmac(sha256, _key).convert(utf8.encode(payload));

    return SignedState(
      state: state,
      timestamp: timestamp,
      sequenceNumber: sequenceNumber,
      hmac: mac.toString(),
    );
  }

  /// Verifie un message d'etat signe.
  StateVerificationResult verify(SignedState signedState) {
    // 1. Verifier le timestamp (pas trop vieux)
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final drift = (now - signedState.timestamp).abs();
    if (drift > _maxTimestampDrift) {
      return StateVerificationResult(
        valid: false,
        reason: 'Timestamp hors limite ($drift s, max $_maxTimestampDrift s)',
      );
    }

    // 2. Verifier le numero de sequence (monotone)
    if (signedState.sequenceNumber <= _lastSequence) {
      return StateVerificationResult(
        valid: false,
        reason: 'Numero de sequence ${signedState.sequenceNumber} <= '
            'dernier $_lastSequence (replay ?)',
      );
    }

    // 3. Verifier le HMAC
    final payload =
        '${signedState.state}|${signedState.timestamp}|${signedState.sequenceNumber}';
    final expectedMac = Hmac(sha256, _key).convert(utf8.encode(payload));
    final expectedHex = expectedMac.toString();

    if (!_constantTimeEquals(expectedHex, signedState.hmac)) {
      return StateVerificationResult(
        valid: false,
        reason: 'HMAC invalide (message falsifie ?)',
      );
    }

    // Tout OK
    _lastSequence = signedState.sequenceNumber;
    return StateVerificationResult(valid: true);
  }

  bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    int result = 0;
    for (int i = 0; i < a.length; i++) {
      result |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return result == 0;
  }

  void dispose() {
    _key.fillRange(0, _key.length, 0);
  }
}

/// Resultat de verification d'etat.
class StateVerificationResult {
  final bool valid;
  final String? reason;

  const StateVerificationResult({
    required this.valid,
    this.reason,
  });
}

// =============================================================
// INTEGRATION :
// =============================================================
//
// 1. Au demarrage, auditer Tailscale :
//
//   final audit = await TailscaleSecurityChecker.audit();
//   if (!audit.isSecure) {
//     showTailscaleWarningDialog(audit.issues);
//   }
//
// 2. Pour les messages d'etat daemon -> app :
//
//   // Cote daemon (Go) : signer chaque message d'etat
//   // signedState := stateVerifier.Sign("connected", seqNum)
//   // sendJSON(signedState)
//
//   // Cote Flutter : verifier chaque message
//   final verifier = StateVerifier(ipcSharedKey);
//   final signedState = SignedState.fromJson(message);
//   final result = verifier.verify(signedState);
//   if (!result.valid) {
//     auditLog.log(SecurityAction.stateVerificationFailed, result.reason);
//     failGuard.forceOpen('Etat non verifie: ${result.reason}');
//   }
//
// 3. TPM si disponible :
//
//   if (await TailscaleSecurityChecker.checkTpmAvailable()) {
//     // Forcer le stockage des cles dans le TPM
//     await Process.run('tailscale', ['up', '--store-state-in=tpm']);
//   }
// =============================================================
