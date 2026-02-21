// =============================================================
// FIX-020 : Journal d'audit securise des actions de securite
// GAP-020 : Journalisation des actions de securite absente
// Cible  : lib/core/security/security_audit_log.dart (nouveau)
// =============================================================
//
// PROBLEME : Quand quelqu'un desactive le pare-feu, AppArmor ou
// fail2ban via l'app, il n'existe aucune trace de cette action.
// Impossible de retracer une compromission.
//
// SOLUTION :
//   1. Journal d'audit local horodate (format JSON Lines)
//   2. Chaque entree signee avec HMAC-SHA256
//   3. Chaine de hachage (chaque hash inclut le precedent)
//      → toute modification ou suppression est detectee
//   4. Sanitisation automatique (jamais de secrets dans les logs)
// =============================================================

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

// -----------------------------------------------------------
// Types d'actions de securite journalisees
// -----------------------------------------------------------

/// Actions de securite pouvant etre enregistrees dans le journal.
enum SecurityAction {
  firewallEnabled,
  firewallDisabled,
  apparmorEnabled,
  apparmorDisabled,
  fail2banEnabled,
  fail2banDisabled,
  pinSet,
  pinRemoved,
  pinVerifyFailed,
  pinVerifySuccess,
  daemonStarted,
  daemonStopped,
  daemonIntegrityFailed,
  sshConnected,
  sshDisconnected,
  sshRootLoginDisabled,
  sshRootLoginEnabled,
  tailscaleConnected,
  tailscaleDisconnected,
  debuggerDetected,
  injectionDetected,
  lockEnabled,
  lockDisabled,
  killSwitchActivated,
}

// -----------------------------------------------------------
// Modele d'entree de journal
// -----------------------------------------------------------

/// Entree dans le journal d'audit securise.
class AuditEntry {
  final DateTime timestamp;
  final SecurityAction action;
  final String detail;
  final String previousHash;
  final String hash;

  const AuditEntry({
    required this.timestamp,
    required this.action,
    required this.detail,
    required this.previousHash,
    required this.hash,
  });

  /// Serialise l'entree en Map JSON.
  Map<String, dynamic> toJson() => {
        'ts': timestamp.toUtc().toIso8601String(),
        'action': action.name,
        'detail': detail,
        'prev': previousHash,
        'hash': hash,
      };

  /// Reconstruit une entree a partir d'une Map JSON.
  factory AuditEntry.fromJson(Map<String, dynamic> json) {
    return AuditEntry(
      timestamp: DateTime.parse(json['ts'] as String),
      action: SecurityAction.values.firstWhere(
        (a) => a.name == (json['action'] as String),
        orElse: () => SecurityAction.firewallEnabled,
      ),
      detail: json['detail'] as String? ?? '',
      previousHash: json['prev'] as String? ?? '',
      hash: json['hash'] as String? ?? '',
    );
  }
}

// -----------------------------------------------------------
// Journal d'audit principal
// -----------------------------------------------------------

/// Journal d'audit securise avec chaine de hachage HMAC-SHA256.
///
/// Chaque entree inclut un HMAC du contenu + le hash precedent.
/// Toute modification (y compris la suppression d'une ligne)
/// est detectee par [verifyIntegrity].
///
/// Les secrets (PIN, cles, tokens, chemins) sont automatiquement
/// supprimes par [_sanitize] avant ecriture.
///
/// Usage :
/// ```dart
/// final key  = SecurityAuditLog.generateKey();
/// final log  = await SecurityAuditLog.open(
///   path   : '/var/log/chillapp/security_audit.log',
///   hmacKey: key,
/// );
/// await log.log(SecurityAction.firewallDisabled,
///   detail: 'Desactive par l\'utilisateur');
///
/// final corrupted = await log.verifyIntegrity();
/// if (corrupted.isNotEmpty) { /* ALERTE */ }
/// ```
class SecurityAuditLog {
  final File _logFile;
  final Uint8List _hmacKey;
  String _lastHash;

  /// Nombre maximum d'entrees avant rotation du fichier.
  static const int _maxEntries = 10000;

  /// Nombre d'entrees conservees apres rotation.
  static const int _keepAfterRotation = 1000;

  int _entryCount;

  SecurityAuditLog._({
    required File logFile,
    required Uint8List hmacKey,
    required String lastHash,
    required int entryCount,
  })  : _logFile = logFile,
        _hmacKey = hmacKey,
        _lastHash = lastHash,
        _entryCount = entryCount;

  // -----------------------------------------------------------------
  // Initialisation
  // -----------------------------------------------------------------

  /// Ouvre ou cree le journal d'audit au chemin indique.
  ///
  /// [path]    : Chemin complet vers le fichier .log
  /// [hmacKey] : Cle HMAC-SHA256 de 32 octets (a stocker en secure storage)
  static Future<SecurityAuditLog> open({
    required String path,
    required List<int> hmacKey,
  }) async {
    if (hmacKey.length < 32) {
      throw ArgumentError(
        'La cle HMAC doit faire au moins 32 octets, recu: ${hmacKey.length}',
      );
    }
    final key = Uint8List.fromList(hmacKey);
    final logFile = File(path);
    String lastHash = '0' * 64; // Hash genesis (point de depart de la chaine)
    int entryCount = 0;

    if (await logFile.exists()) {
      // Recuperer le dernier hash pour poursuivre la chaine
      final lines = await logFile.readAsLines();
      entryCount = lines.where((l) => l.trim().isNotEmpty).length;
      for (int i = lines.length - 1; i >= 0; i--) {
        final line = lines[i].trim();
        if (line.isEmpty) continue;
        try {
          final decoded = jsonDecode(line) as Map<String, dynamic>;
          final h = decoded['hash'] as String?;
          if (h != null && h.length == 64) {
            lastHash = h;
          }
        } catch (_) {
          // Ligne corrompue — on continue avec la ligne precedente
        }
        break;
      }
    } else {
      // Creer le fichier avec permissions restrictives
      await logFile.create(recursive: true);
      if (Platform.isLinux || Platform.isMacOS) {
        await Process.run('chmod', ['600', path]);
      }
    }

    return SecurityAuditLog._(
      logFile: logFile,
      hmacKey: key,
      lastHash: lastHash,
      entryCount: entryCount,
    );
  }

  // -----------------------------------------------------------------
  // Journalisation
  // -----------------------------------------------------------------

  /// Ajoute une entree dans le journal.
  ///
  /// [action] : Action de securite effectuee
  /// [detail] : Description courte (les secrets seront automatiquement
  ///            supprimes avant ecriture)
  Future<void> log(SecurityAction action, {String detail = ''}) async {
    final safeDetail = _sanitize(detail);
    final timestamp = DateTime.now().toUtc();

    // Contenu signe : timestamp | action | detail | hashPrecedent
    final content = '${timestamp.toIso8601String()}'
        '|${action.name}'
        '|$safeDetail'
        '|$_lastHash';

    final entryHash = _computeHmac(content);

    final entry = AuditEntry(
      timestamp: timestamp,
      action: action,
      detail: safeDetail,
      previousHash: _lastHash,
      hash: entryHash,
    );

    // Ecriture en mode append (une entree par ligne)
    await _logFile.writeAsString(
      '${jsonEncode(entry.toJson())}\n',
      mode: FileMode.append,
      encoding: utf8,
      flush: true,
    );

    _lastHash = entryHash;
    _entryCount++;

    // Rotation si necessaire (basee sur le compteur, pas une relecture fichier)
    if (_entryCount > _maxEntries) {
      await _rotateIfNeeded();
    }
  }

  // -----------------------------------------------------------------
  // Verification d'integrite
  // -----------------------------------------------------------------

  /// Verifie l'integrite de toute la chaine de hachage.
  ///
  /// Retourne la liste des indices de lignes corrompues ou invalides.
  /// Une liste vide signifie que le journal est intact.
  Future<List<int>> verifyIntegrity() async {
    final corrupted = <int>[];
    if (!await _logFile.exists()) return corrupted;

    final lines = await _logFile.readAsLines();
    String previousHash = '0' * 64;

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;

      try {
        final decoded = jsonDecode(line) as Map<String, dynamic>;
        final entry = AuditEntry.fromJson(decoded);

        // Verifier la continuite de la chaine
        if (entry.previousHash != previousHash) {
          corrupted.add(i);
          previousHash = entry.hash;
          continue;
        }

        // Verifier le HMAC de l'entree
        final content = '${entry.timestamp.toUtc().toIso8601String()}'
            '|${entry.action.name}'
            '|${entry.detail}'
            '|${entry.previousHash}';

        final expectedHash = _computeHmac(content);

        if (entry.hash != expectedHash) {
          corrupted.add(i);
        }

        previousHash = entry.hash;
      } catch (_) {
        corrupted.add(i);
      }
    }

    return corrupted;
  }

  // -----------------------------------------------------------------
  // Lecture
  // -----------------------------------------------------------------

  /// Lit les [count] dernieres entrees du journal.
  Future<List<AuditEntry>> readLast(int count) async {
    if (!await _logFile.exists()) return [];

    final lines = await _logFile.readAsLines();
    final start = lines.length > count ? lines.length - count : 0;

    final entries = <AuditEntry>[];
    for (final line in lines.sublist(start)) {
      if (line.trim().isEmpty) continue;
      try {
        entries.add(
          AuditEntry.fromJson(jsonDecode(line) as Map<String, dynamic>),
        );
      } catch (_) {
        // Ligne non parseable — on la saute
      }
    }
    return entries;
  }

  // -----------------------------------------------------------------
  // Utilitaires statiques
  // -----------------------------------------------------------------

  /// Genere une cle HMAC aleatoire de 32 octets.
  /// A stocker dans le secure storage de l'application.
  static List<int> generateKey() {
    final rng = Random.secure();
    return List.generate(32, (_) => rng.nextInt(256));
  }

  /// Supprime les informations sensibles du texte avant journalisation.
  ///
  /// Supprime :
  /// - Chemins absolus Unix/Windows
  /// - Adresses IP (hors plage Tailscale 100.x.x.x)
  /// - Tokens / cles base64 de 32 caracteres ou plus
  ///
  /// Tronque le texte a 200 caracteres.
  static String sanitize(String input) => _sanitize(input);

  // -----------------------------------------------------------------
  // Helpers prives
  // -----------------------------------------------------------------

  /// Calcule le HMAC-SHA256 du contenu avec la cle interne.
  String _computeHmac(String content) {
    final hmac = Hmac(sha256, _hmacKey);
    return hmac.convert(utf8.encode(content)).toString();
  }

  /// Sanitisation interne (appelee avant toute ecriture).
  static String _sanitize(String input) {
    var safe = input;

    // Supprimer les chemins absolus (Unix et Windows)
    safe = safe.replaceAll(
      RegExp(r'(/home/[^\s]+|/Users/[^\s]+|C:\\Users\\[^\s]+)'),
      '[PATH]',
    );

    // Supprimer les adresses IP (sauf plage Tailscale 100.x.x.x)
    safe = safe.replaceAll(
      RegExp(r'\b(?!100\.)\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b'),
      '[IP]',
    );

    // Supprimer ce qui ressemble a un token ou une cle (>= 32 caracteres base64)
    safe = safe.replaceAll(
      RegExp(r'[A-Za-z0-9+/=]{32,}'),
      '[REDACTED]',
    );

    // Tronquer les messages trop longs
    if (safe.length > 200) {
      safe = '${safe.substring(0, 200)}...';
    }

    return safe;
  }

  /// Rotation du fichier log quand il depasse [_maxEntries] lignes.
  Future<void> _rotateIfNeeded() async {
    final lines = await _logFile.readAsLines();

    // Archiver le fichier courant
    final archivePath =
        '${_logFile.path}.${DateTime.now().millisecondsSinceEpoch}.bak';
    await _logFile.copy(archivePath);

    // Conserver uniquement les dernieres lignes
    final kept = lines.sublist(lines.length - _keepAfterRotation);
    await _logFile.writeAsString(
      '${kept.join('\n')}\n',
      encoding: utf8,
      flush: true,
    );

    _entryCount = _keepAfterRotation;
  }
}
