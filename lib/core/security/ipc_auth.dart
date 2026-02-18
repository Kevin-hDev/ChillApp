// =============================================================
// FIX-012 : IPC authentifie HMAC-SHA256
// GAP-012 : IPC daemon non authentifie ni chiffre (P0)
//
// PROBLEME : Les messages JSON echanges avec le daemon Go
// sont en clair et sans signature. N'importe quel processus
// local peut injecter des commandes (ex: cmd logout, cmd stop).
//
// SOLUTION :
// - Chaque message est signe avec HMAC-SHA256 + cle partagee
// - Un champ _nonce unique empeche le replay d'un message
// - Un champ _timestamp limite la fenetre a 30 secondes
// - La comparaison du MAC est faite en temps constant
// =============================================================

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

/// Protocole IPC authentifie avec HMAC-SHA256, nonce et timestamp.
///
/// Chaque message JSON est enveloppe dans une structure signee.
/// Le daemon Go doit implementer le meme protocole pour accepter
/// les commandes de l'app Flutter.
///
/// Usage :
/// ```dart
/// // Cote emetteur
/// final secret = AuthenticatedIPC.generateSecret();
/// final ipc = AuthenticatedIPC(secret);
/// final signed = ipc.signMessage({'cmd': 'status'});
/// process.stdin.writeln(signed);
///
/// // Cote recepteur (meme secret)
/// final payload = ipc.verifyMessage(receivedLine);
/// if (payload == null) return; // Message invalide, ignorer
/// ```
class AuthenticatedIPC {
  final Uint8List _sharedKey;

  /// Cache des nonces deja utilises (anti-replay).
  final Set<String> _usedNonces = {};

  /// Taille du nonce en octets (128 bits de hasard).
  static const int _nonceSize = 16;

  /// Queue FIFO pour purge ordonnee des nonces (les plus anciens en premier).
  final List<String> _nonceQueue = [];

  /// Nombre maximum de nonces caches avant purge partielle.
  /// A 1 message/seconde, 10 000 entrees = ~2h45 de protection.
  static const int _maxNonceCache = 10000;

  /// Pourcentage du cache purge quand il est plein (les 20% les plus anciens).
  static const int _purgeBatchSize = 2000;

  /// Fenetre de validite temporelle d'un message (30 secondes).
  static const Duration _maxTimeDrift = Duration(seconds: 30);

  /// Cle privee pour signer : nom du champ HMAC dans le message.
  static const String _macField = '_hmac';

  /// Nom du champ nonce dans le message.
  static const String _nonceField = '_nonce';

  /// Nom du champ timestamp dans le message.
  static const String _timestampField = '_timestamp';

  /// Cree un protocole IPC avec la cle partagee fournie.
  ///
  /// La cle doit avoir au moins 32 octets (256 bits).
  /// Utiliser [generateSecret] pour en generer une securisee.
  AuthenticatedIPC(this._sharedKey) {
    if (_sharedKey.length < 32) {
      throw ArgumentError('La cle partagee doit avoir au moins 32 octets');
    }
  }

  // -----------------------------------------------------------------
  // Methodes publiques
  // -----------------------------------------------------------------

  /// Genere une cle partagee aleatoire securisee (256 bits).
  ///
  /// A appeler une seule fois au demarrage. La cle doit etre
  /// transmise au daemon via un canal protege (fichier mode 0600,
  /// variable d'environnement, ou argument de ligne de commande
  /// sur un pipe ferme).
  static Uint8List generateSecret() {
    final rng = Random.secure();
    return Uint8List.fromList(
      List.generate(32, (_) => rng.nextInt(256)),
    );
  }

  /// Signe un message JSON et retourne un Map pret a serialiser.
  ///
  /// Le Map retourne contient tous les champs du [jsonMessage]
  /// plus trois champs ajoutes :
  /// - `_nonce`     : valeur aleatoire base64 (anti-replay)
  /// - `_timestamp` : horodatage ISO-8601 UTC (anti-replay)
  /// - `_hmac`      : MAC HMAC-SHA256 hex (authenticite)
  ///
  /// Le HMAC est calcule sur le JSON serialise de facon deterministe
  /// (avec cles triees) AVANT l'ajout du champ `_hmac` lui-meme.
  Map<String, dynamic> signMessage(Map<String, dynamic> jsonMessage) {
    // Construire le message avec nonce et timestamp
    final message = Map<String, dynamic>.from(jsonMessage);
    message[_nonceField] = _generateNonce();
    message[_timestampField] = DateTime.now().toUtc().toIso8601String();

    // Serialiser de facon deterministe (cles triees) pour le HMAC
    final canonical = _canonicalJson(message);

    // Calculer le HMAC avec la cle de l'instance
    final mac = _computeHmac(canonical, _sharedKey);
    message[_macField] = mac;

    return message;
  }

  /// Verifie un message signe et retourne `true` si valide.
  ///
  /// La verification echoue (retourne false) si :
  /// - Le champ `_hmac` est absent ou incorrect
  /// - Le champ `_nonce` est absent ou deja vu (replay)
  /// - Le champ `_timestamp` est absent ou hors fenetre (30s)
  /// - Le JSON est malforme
  bool verifyMessage(Map<String, dynamic> signedMessage) {
    try {
      // Extraire le MAC recu
      final receivedMac = signedMessage[_macField] as String?;
      if (receivedMac == null) return false;

      // Reconstruire le message SANS le champ _hmac pour la verification
      final messageWithoutMac = Map<String, dynamic>.from(signedMessage);
      messageWithoutMac.remove(_macField);

      // Serialiser de facon identique a signMessage
      final canonical = _canonicalJson(messageWithoutMac);

      // Calculer le MAC attendu
      final expectedMac = _computeHmac(canonical, _sharedKey);

      // Comparaison en temps constant (protection timing attack)
      if (!_constantTimeEquals(expectedMac, receivedMac)) {
        return false; // HMAC invalide
      }

      // Verifier le nonce (anti-replay)
      final nonce = signedMessage[_nonceField] as String?;
      if (nonce == null || nonce.isEmpty) return false;
      if (_usedNonces.contains(nonce)) return false; // Replay detecte

      // Verifier le timestamp (fenetre de 30 secondes)
      final rawTs = signedMessage[_timestampField] as String?;
      if (rawTs == null) return false;
      final timestamp = DateTime.tryParse(rawTs);
      if (timestamp == null) return false;

      final age = DateTime.now().toUtc().difference(timestamp.toUtc());
      if (age.abs() > _maxTimeDrift) return false; // Message trop ancien/futur

      // Enregistrer le nonce pour empecher le replay
      _usedNonces.add(nonce);
      _nonceQueue.add(nonce);

      // Purge FIFO partielle : supprimer les 20% les plus anciens
      // (jamais tout le cache, pour eviter une fenetre de replay)
      if (_usedNonces.length > _maxNonceCache) {
        final toRemove = _nonceQueue.sublist(0, _purgeBatchSize);
        for (final old in toRemove) {
          _usedNonces.remove(old);
        }
        _nonceQueue.removeRange(0, _purgeBatchSize);
      }

      return true;
    } catch (_) {
      return false; // Tout echec = message invalide
    }
  }

  /// Efface la cle partagee et le cache de nonces de la memoire.
  void dispose() {
    _sharedKey.fillRange(0, _sharedKey.length, 0);
    _usedNonces.clear();
    _nonceQueue.clear();
  }

  // -----------------------------------------------------------------
  // Helpers prives
  // -----------------------------------------------------------------

  /// Genere un nonce aleatoire encode en base64 (128 bits).
  String _generateNonce() {
    final rng = Random.secure();
    final bytes = Uint8List.fromList(
      List.generate(_nonceSize, (_) => rng.nextInt(256)),
    );
    return base64Encode(bytes);
  }

  /// Calcule HMAC-SHA256 et retourne le resultat en hexadecimal.
  String _computeHmac(String data, List<int> key) {
    final hmac = Hmac(sha256, key);
    return hmac.convert(utf8.encode(data)).toString();
  }

  /// Serialise un Map en JSON deterministe (cles triees alphabetiquement).
  ///
  /// Necessaire pour que l'emetteur et le recepteur calculent
  /// exactement le meme HMAC, independamment de l'ordre des cles.
  static String _canonicalJson(Map<String, dynamic> map) {
    final sortedMap = _sortMapKeys(map);
    return jsonEncode(sortedMap);
  }

  /// Tri recursif des cles d'un Map (pour JSON canonique).
  static dynamic _sortMapKeys(dynamic value) {
    if (value is Map) {
      final sorted = <String, dynamic>{};
      final keys = value.keys.cast<String>().toList()..sort();
      for (final key in keys) {
        sorted[key] = _sortMapKeys(value[key]);
      }
      return sorted;
    }
    if (value is List) {
      return value.map(_sortMapKeys).toList();
    }
    return value;
  }

  /// Comparaison en temps constant (protection contre timing attacks).
  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    int diff = 0;
    for (int i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}
