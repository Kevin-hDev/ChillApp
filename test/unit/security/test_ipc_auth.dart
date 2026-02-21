// =============================================================
// Tests unitaires — FIX-012 : AuthenticatedIPC (HMAC-SHA256)
// Protocole IPC signe avec nonce et timestamp anti-replay
// =============================================================
//
// Executer avec :
//   dart test test/unit/security/test_ipc_auth.dart
//
// =============================================================

import 'dart:convert';
import 'package:test/test.dart';
import 'package:chill_app/core/security/ipc_auth.dart';

void main() {
  late AuthenticatedIPC ipc;

  setUp(() {
    final secretBytes = AuthenticatedIPC.generateSecret();
    ipc = AuthenticatedIPC(secretBytes);
  });

  // ---------------------------------------------------------------
  // generateSecret
  // ---------------------------------------------------------------

  group('generateSecret', () {
    test('produit exactement 32 octets', () {
      final secret = AuthenticatedIPC.generateSecret();
      expect(secret.length, equals(32), reason: '256 bits = 32 octets');
    });

    test('deux appels produisent des secrets differents', () {
      final s1 = AuthenticatedIPC.generateSecret();
      final s2 = AuthenticatedIPC.generateSecret();
      expect(s1, isNot(equals(s2)), reason: 'Secrets aleatoires differents');
    });

    test('lance ArgumentError si la cle fait moins de 32 octets', () {
      expect(
        () => AuthenticatedIPC(List.filled(16, 0).sublist(0) as dynamic),
        throwsA(anything),
      );
    });
  });

  // ---------------------------------------------------------------
  // signMessage
  // ---------------------------------------------------------------

  group('signMessage', () {
    test('retourne un Map contenant _hmac, _nonce, _timestamp', () {
      final signed = ipc.signMessage({'cmd': 'status'});

      expect(signed.containsKey('_hmac'), isTrue, reason: 'Champ _hmac present');
      expect(signed.containsKey('_nonce'), isTrue, reason: 'Champ _nonce present');
      expect(signed.containsKey('_timestamp'), isTrue, reason: 'Champ _timestamp present');
    });

    test('conserve tous les champs du message original', () {
      final payload = {'cmd': 'login', 'host': 'vpn.example.com', 'port': 41641};
      final signed = ipc.signMessage(payload);

      expect(signed['cmd'], equals('login'));
      expect(signed['host'], equals('vpn.example.com'));
      expect(signed['port'], equals(41641));
    });

    test('le champ _hmac est une chaine hexadecimale de 64 caracteres', () {
      final signed = ipc.signMessage({'action': 'test'});
      final mac = signed['_hmac'] as String;

      expect(mac.length, equals(64), reason: 'HMAC-SHA256 = 64 hex chars');
      expect(
        RegExp(r'^[0-9a-f]{64}$').hasMatch(mac),
        isTrue,
        reason: 'Caracteres hexadecimaux uniquement',
      );
    });

    test('le champ _nonce est en base64 (non vide)', () {
      final signed = ipc.signMessage({'x': 1});
      final nonce = signed['_nonce'] as String;

      expect(nonce.isNotEmpty, isTrue);
      expect(() => base64Decode(nonce), returnsNormally);
    });

    test('deux appels successifs produisent des nonces differents', () {
      final s1 = ipc.signMessage({'cmd': 'ping'});
      final s2 = ipc.signMessage({'cmd': 'ping'});

      expect(s1['_nonce'], isNot(equals(s2['_nonce'])), reason: 'Nonces aleatoires uniques');
    });

    test('le timestamp est un ISO-8601 UTC valide', () {
      final signed = ipc.signMessage({'x': 0});
      final rawTs = signed['_timestamp'] as String;

      final parsed = DateTime.tryParse(rawTs);
      expect(parsed, isNotNull, reason: 'Timestamp parseable');
      expect(parsed!.isUtc, isTrue, reason: 'Timestamp en UTC');
    });
  });

  // ---------------------------------------------------------------
  // verifyMessage — cas valides
  // ---------------------------------------------------------------

  group('verifyMessage — messages valides', () {
    test('accepte un message signe avec la bonne cle', () {
      final signed = ipc.signMessage({'cmd': 'connect'});
      final ok = ipc.verifyMessage(signed);
      expect(ok, isTrue, reason: 'Message signe valide = accepte');
    });

    test('accepte des messages JSON complexes (listes, imbrication)', () {
      final payload = {
        'cmd': 'batch',
        'items': ['a', 'b', 'c'],
        'meta': {'version': 2, 'debug': false},
      };
      final signed = ipc.signMessage(payload);
      final ok = ipc.verifyMessage(signed);
      expect(ok, isTrue, reason: 'Message complexe accepte');
    });
  });

  // ---------------------------------------------------------------
  // verifyMessage — rejets de securite
  // ---------------------------------------------------------------

  group('verifyMessage — rejets de securite', () {
    test('rejette un message dont le _hmac est altere', () {
      final signed = Map<String, dynamic>.from(
        ipc.signMessage({'cmd': 'logout'}),
      );
      final mac = signed['_hmac'] as String;
      signed['_hmac'] = mac.replaceRange(0, 1, mac[0] == 'a' ? 'b' : 'a');

      final ok = ipc.verifyMessage(signed);
      expect(ok, isFalse, reason: 'HMAC altere => rejete');
    });

    test('rejette un message dont le contenu a ete modifie', () {
      final signed = Map<String, dynamic>.from(
        ipc.signMessage({'cmd': 'connect'}),
      );
      signed['cmd'] = 'logout';

      final ok = ipc.verifyMessage(signed);
      expect(ok, isFalse, reason: 'Payload modifie => HMAC invalide => rejete');
    });

    test('rejette si le champ _hmac est absent', () {
      final signed = Map<String, dynamic>.from(
        ipc.signMessage({'cmd': 'status'}),
      );
      signed.remove('_hmac');

      final ok = ipc.verifyMessage(signed);
      expect(ok, isFalse, reason: '_hmac absent => rejete');
    });

    test('rejette avec une mauvaise cle partagee', () {
      final signed = ipc.signMessage({'cmd': 'status'});

      // Autre instance avec une cle differente
      final otherSecret = AuthenticatedIPC.generateSecret();
      final otherIpc = AuthenticatedIPC(otherSecret);
      final ok = otherIpc.verifyMessage(signed);
      expect(ok, isFalse, reason: 'Mauvaise cle => HMAC invalide => rejete');
    });

    test('anti-replay : rejette un message deja vu (meme nonce)', () {
      final signed = ipc.signMessage({'cmd': 'ping'});

      final first = ipc.verifyMessage(signed);
      final second = ipc.verifyMessage(signed);

      expect(first, isTrue, reason: 'Premier passage accepte');
      expect(second, isFalse, reason: 'Replay rejete (nonce deja vu)');
    });

    test('rejette si le champ _nonce est absent', () {
      final signed = Map<String, dynamic>.from(
        ipc.signMessage({'cmd': 'test'}),
      );
      signed.remove('_nonce');
      final ok = ipc.verifyMessage(signed);
      expect(ok, isFalse, reason: '_nonce absent => rejete');
    });

    test('rejette si le champ _timestamp est absent', () {
      final signed = Map<String, dynamic>.from(
        ipc.signMessage({'cmd': 'test'}),
      );
      signed.remove('_timestamp');
      final ok = ipc.verifyMessage(signed);
      expect(ok, isFalse, reason: '_timestamp absent => rejete');
    });

    test('rejette un message avec un timestamp trop ancien (> 30s)', () {
      final signed = Map<String, dynamic>.from(
        ipc.signMessage({'cmd': 'test'}),
      );
      final oldTs = DateTime.now().toUtc()
          .subtract(const Duration(seconds: 61))
          .toIso8601String();
      signed['_timestamp'] = oldTs;
      final ok = ipc.verifyMessage(signed);
      expect(ok, isFalse, reason: 'Timestamp trop ancien => rejete');
    });
  });

  // ---------------------------------------------------------------
  // Robustesse generique
  // ---------------------------------------------------------------

  group('robustesse', () {
    test('verifyMessage retourne false sur un Map vide', () {
      final ok = ipc.verifyMessage({});
      expect(ok, isFalse);
    });

    test('verifyMessage retourne false si _hmac est une chaine vide', () {
      final signed = Map<String, dynamic>.from(
        ipc.signMessage({'cmd': 'x'}),
      );
      signed['_hmac'] = '';
      final ok = ipc.verifyMessage(signed);
      expect(ok, isFalse);
    });

    test('signMessage + verifyMessage : aller-retour complet', () {
      final payload = {
        'cmd': 'status',
        'extra': {'flag': true, 'count': 42},
      };
      final signed = ipc.signMessage(payload);
      final ok = ipc.verifyMessage(signed);
      expect(ok, isTrue, reason: 'Aller-retour signe/verifie sans perte');
    });

    test('dispose efface la cle et vide le cache', () {
      final signed = ipc.signMessage({'cmd': 'test'});
      ipc.dispose();
      // Apres dispose, la cle est zeroisee => HMAC ne matche plus
      final ok = ipc.verifyMessage(signed);
      expect(ok, isFalse, reason: 'Apres dispose, les messages ne sont plus verifies');
    });
  });
}
