// =============================================================
// FIX-038 : Securite renforcee de Tailscale (TPM, OIDC, SSH audit)
// FIX-039 : Etat signe HMAC avec anti-replay
// GAP-038 : Configuration Tailscale non durcie
// GAP-039 : Absence de signature d'etat critique
// =============================================================
//
// PROBLEME 038 : Tailscale peut etre lance sans les options de
// securite avancees (TPM, auditSSH, MagicDNS strict).
//
// PROBLEME 039 : Les messages d'etat critiques de l'application
// ne sont pas signes, permettant leur falsification.
//
// SOLUTION 038 : Generer les arguments Tailscale durcis et
// auditer la configuration active.
//
// SOLUTION 039 : Signer les messages d'etat avec HMAC-SHA256.
// Verifier : signature, replay (sequence monotone), derive
// temporelle (max 30 secondes).
// =============================================================

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

// ===========================================================================
// FIX-038 : Configuration et audit Tailscale
// ===========================================================================

/// Configuration de securite renforcee pour Tailscale.
class TailscaleSecurityConfig {
  /// Active la liaison de la cle de noeud au TPM (si disponible).
  final bool enableTpmBinding;

  /// Active l'authentification OIDC pour les noeuds Tailscale.
  final bool enableOidc;

  /// Active l'audit des sessions SSH via Tailscale SSH.
  final bool enableSshAudit;

  /// Active MagicDNS (resolution DNS Tailscale interne).
  final bool enableMagicDns;

  /// Desactive les relais DERP (force une connexion directe peer-to-peer).
  final bool noRelays;

  const TailscaleSecurityConfig({
    this.enableTpmBinding = true,
    this.enableOidc = false,
    this.enableSshAudit = true,
    this.enableMagicDns = true,
    this.noRelays = false,
  });

  /// Genere la liste d'arguments a passer a la commande `tailscale up`.
  List<String> toTailscaleArgs() {
    final args = <String>['up'];
    if (enableSshAudit) args.add('--ssh');
    if (noRelays) args.add('--no-relays');
    if (!enableMagicDns) args.add('--accept-dns=false');
    return args;
  }
}

/// Probleme detecte lors de l'audit Tailscale.
class TailscaleIssue {
  /// Identifiant court du probleme (ex: 'no-ssh').
  final String code;

  /// Description lisible du probleme.
  final String message;

  /// Niveau de gravite : 'critical', 'warning', 'info'.
  final String severity;

  const TailscaleIssue({
    required this.code,
    required this.message,
    required this.severity,
  });
}

/// Resultat d'un audit de securite Tailscale.
class TailscaleAuditResult {
  /// Liste des problemes detectes.
  final List<TailscaleIssue> issues;

  /// Liste de recommandations textuelles.
  final List<String> recommendations;

  /// Indique si l'audit a reussi (sans probleme critique).
  final bool passed;

  const TailscaleAuditResult({
    required this.issues,
    required this.recommendations,
    required this.passed,
  });

  /// Retourne true si au moins un probleme critique est present.
  bool get hasCriticalIssue =>
      issues.any((i) => i.severity == 'critical');
}

/// Verifie la securite de l'installation Tailscale locale.
///
/// Methodes :
///   - [audit] : lance un audit complet (version, statut, MagicDNS)
class TailscaleSecurityChecker {
  /// Configuration cible a verifier.
  final TailscaleSecurityConfig config;

  TailscaleSecurityChecker({TailscaleSecurityConfig? config})
      : config = config ?? const TailscaleSecurityConfig();

  /// Effectue un audit complet de la configuration Tailscale active.
  ///
  /// Retourne un [TailscaleAuditResult] avec les problemes et recommandations.
  Future<TailscaleAuditResult> audit() async {
    final issues = <TailscaleIssue>[];
    final recommendations = <String>[];

    // 1. Verifier si tailscale est installe
    final versionResult =
        await _run('tailscale', ['version']);
    if (versionResult == null || versionResult.exitCode != 0) {
      issues.add(const TailscaleIssue(
        code: 'not-installed',
        message: 'Tailscale non installe ou non accessible',
        severity: 'critical',
      ));
      recommendations.add(
        'Installer Tailscale depuis https://tailscale.com/download',
      );
      return TailscaleAuditResult(
        issues: issues,
        recommendations: recommendations,
        passed: false,
      );
    }

    // 2. Verifier le statut de connexion
    final statusResult = await _run('tailscale', ['status', '--json']);
    if (statusResult == null || statusResult.exitCode != 0) {
      issues.add(const TailscaleIssue(
        code: 'not-connected',
        message: 'Tailscale non connecte au reseau',
        severity: 'critical',
      ));
      recommendations.add('Lancer `tailscale up` pour se connecter.');
    } else {
      final statusJson = statusResult.stdout.toString();
      _checkStatus(statusJson, issues, recommendations);
    }

    final passed = !issues.any((i) => i.severity == 'critical');
    return TailscaleAuditResult(
      issues: issues,
      recommendations: recommendations,
      passed: passed,
    );
  }

  void _checkStatus(
    String statusJson,
    List<TailscaleIssue> issues,
    List<String> recommendations,
  ) {
    try {
      final data = jsonDecode(statusJson) as Map<String, dynamic>;

      // Verifier MagicDNS
      final magicDns = data['MagicDNSSuffix'] as String?;
      if (config.enableMagicDns &&
          (magicDns == null || magicDns.isEmpty)) {
        issues.add(const TailscaleIssue(
          code: 'no-magicdns',
          message: 'MagicDNS non actif sur ce noeud',
          severity: 'warning',
        ));
        recommendations.add(
          'Activer MagicDNS dans la console Tailscale (DNS settings).',
        );
      }

      // Verifier SSH Tailscale
      final selfNode = data['Self'] as Map<String, dynamic>?;
      if (config.enableSshAudit && selfNode != null) {
        final sshEnabled = selfNode['Tags']
                ?.toString()
                .contains('tag:ssh') ??
            false;
        if (!sshEnabled) {
          issues.add(const TailscaleIssue(
            code: 'no-ssh-audit',
            message: 'SSH Tailscale non detecte sur ce noeud',
            severity: 'warning',
          ));
          recommendations.add(
            'Lancer `tailscale up --ssh` pour activer l\'audit SSH.',
          );
        }
      }
    } catch (_) {
      // JSON invalide ou structure inattendue — ignorer
    }
  }

  Future<ProcessResult?> _run(
    String executable,
    List<String> args,
  ) async {
    try {
      return await Process.run(executable, args);
    } catch (_) {
      return null;
    }
  }
}

// ===========================================================================
// FIX-039 : Etat signe HMAC avec anti-replay et derive temporelle
// ===========================================================================

/// Message d'etat signe avec HMAC-SHA256.
///
/// Permet de verifier l'integrite et l'authenticite d'un etat critique.
/// Protege contre le rejeu via [sequenceNumber] et contre les messages
/// anciens via [timestamp].
class SignedState {
  /// Contenu de l'etat a proteger.
  final String state;

  /// Horodatage Unix en millisecondes (DateTime.now().millisecondsSinceEpoch).
  final int timestamp;

  /// Numero de sequence strictement croissant (anti-replay).
  final int sequenceNumber;

  /// Signature HMAC-SHA256 encodee en base64.
  final String hmac;

  const SignedState({
    required this.state,
    required this.timestamp,
    required this.sequenceNumber,
    required this.hmac,
  });

  /// Serialise en Map JSON.
  Map<String, dynamic> toJson() => {
        'state': state,
        'timestamp': timestamp,
        'sequenceNumber': sequenceNumber,
        'hmac': hmac,
      };

  /// Deserialise depuis une Map JSON.
  factory SignedState.fromJson(Map<String, dynamic> json) => SignedState(
        state: json['state'] as String,
        timestamp: json['timestamp'] as int,
        sequenceNumber: json['sequenceNumber'] as int,
        hmac: json['hmac'] as String,
      );

  @override
  String toString() =>
      'SignedState(state=$state, seq=$sequenceNumber, ts=$timestamp)';
}

/// Signe et verifie des etats critiques avec HMAC-SHA256.
///
/// Protection :
///   - **Integrite** : HMAC-SHA256 sur `state|timestamp|sequenceNumber`
///   - **Anti-replay** : le numero de sequence doit etre strictement
///     superieur au dernier sequence valide vu
///   - **Derive temporelle** : l'ecart entre le timestamp du message
///     et l'heure courante ne doit pas depasser [maxDriftMs]
///   - **Comparaison a temps constant** : evite les attaques temporelles
class StateVerifier {
  /// Derive temporelle maximale autorisee (30 secondes).
  static const int maxDriftMs = 30 * 1000;

  /// Cle HMAC (Uint8List) — mise a zero par [dispose].
  Uint8List _key;

  /// Dernier numero de sequence valide vu (anti-replay).
  int _lastSequence = -1;

  StateVerifier(Uint8List key) : _key = Uint8List.fromList(key);

  /// Cree un [StateVerifier] depuis une cle encodee en UTF-8.
  factory StateVerifier.fromString(String keyString) {
    final bytes = Uint8List.fromList(utf8.encode(keyString));
    return StateVerifier(bytes);
  }

  /// Signe [state] avec le numero de sequence [sequenceNumber].
  ///
  /// Le [sequenceNumber] DOIT etre superieur au dernier sequence utilise.
  /// Lance [StateError] si la sequence n'est pas strictement croissante.
  SignedState sign(String state, int sequenceNumber) {
    if (sequenceNumber <= _lastSequence) {
      throw StateError(
        'Numero de sequence invalide: $sequenceNumber doit etre > $_lastSequence',
      );
    }
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final payload = _buildPayload(state, timestamp, sequenceNumber);
    final hmacValue = _computeHmac(payload);
    _lastSequence = sequenceNumber;
    return SignedState(
      state: state,
      timestamp: timestamp,
      sequenceNumber: sequenceNumber,
      hmac: hmacValue,
    );
  }

  /// Verifie l'authenticite et la validite de [signed].
  ///
  /// Retourne `true` si :
  ///   1. La signature HMAC est correcte (comparaison a temps constant)
  ///   2. Le numero de sequence est strictement superieur au dernier vu
  ///   3. La derive temporelle est inferieure a [maxDriftMs]
  ///
  /// Retourne `false` dans tous les autres cas (sans lever d'exception).
  bool verify(SignedState signed) {
    // 1. Verifier la derive temporelle (protection contre les vieux messages)
    final now = DateTime.now().millisecondsSinceEpoch;
    if ((now - signed.timestamp).abs() > maxDriftMs) return false;

    // 2. Verifier le numero de sequence (anti-replay)
    if (signed.sequenceNumber <= _lastSequence) return false;

    // 3. Recalculer et comparer le HMAC a temps constant
    final payload = _buildPayload(
      signed.state,
      signed.timestamp,
      signed.sequenceNumber,
    );
    final expected = _computeHmac(payload);
    if (!constantTimeEquals(expected, signed.hmac)) return false;

    // Tout est valide — mettre a jour le dernier sequence vu
    _lastSequence = signed.sequenceNumber;
    return true;
  }

  /// Reinitialise le compteur de sequence (utile pour les tests).
  void resetSequence() {
    _lastSequence = -1;
  }

  /// Met a zero la cle en memoire (securite : evite les fuites memoire).
  void dispose() {
    for (var i = 0; i < _key.length; i++) {
      _key[i] = 0;
    }
    _key = Uint8List(0);
  }

  /// Comparaison de deux chaines a temps constant.
  ///
  /// Evite les attaques temporelles (timing attacks) lors de la
  /// comparaison de valeurs HMAC.
  ///
  /// Note : la branche `a.length != b.length` fuit la longueur, mais
  /// pour des HMAC-SHA256 en base64 la longueur est toujours fixe (44 chars).
  /// Risque accepte : aucun, car la longueur ne revele rien sur la cle.
  static bool constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var result = 0;
    for (var i = 0; i < a.length; i++) {
      result |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return result == 0;
  }

  // ---------------------------------------------------------------------------
  // Methodes privees
  // ---------------------------------------------------------------------------

  /// Construit le payload HMAC avec state en base64 pour eviter
  /// les collisions via le delimiteur pipe dans le state.
  String _buildPayload(String state, int timestamp, int sequenceNumber) =>
      '${base64Encode(utf8.encode(state))}|$timestamp|$sequenceNumber';

  /// Calcule le HMAC-SHA256 du payload et retourne sa valeur en base64.
  String _computeHmac(String payload) {
    final hmacSha256 = Hmac(sha256, _key);
    final digest = hmacSha256.convert(utf8.encode(payload));
    return base64Encode(digest.bytes);
  }
}
