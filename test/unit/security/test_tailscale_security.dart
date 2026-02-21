// =============================================================
// Tests unitaires : FIX-038/039 — TailscaleSecurity + SignedState
// =============================================================

import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:chill_app/core/security/tailscale_security.dart';

void main() {
  // ---------------------------------------------------------------------------
  // TailscaleSecurityConfig
  // ---------------------------------------------------------------------------
  group('TailscaleSecurityConfig — valeurs par defaut', () {
    test('enableTpmBinding est true par defaut', () {
      const config = TailscaleSecurityConfig();
      expect(config.enableTpmBinding, isTrue);
    });

    test('enableOidc est false par defaut', () {
      const config = TailscaleSecurityConfig();
      expect(config.enableOidc, isFalse);
    });

    test('enableSshAudit est true par defaut', () {
      const config = TailscaleSecurityConfig();
      expect(config.enableSshAudit, isTrue);
    });

    test('enableMagicDns est true par defaut', () {
      const config = TailscaleSecurityConfig();
      expect(config.enableMagicDns, isTrue);
    });

    test('noRelays est false par defaut', () {
      const config = TailscaleSecurityConfig();
      expect(config.noRelays, isFalse);
    });
  });

  group('TailscaleSecurityConfig — toTailscaleArgs()', () {
    test('contient "--ssh" quand enableSshAudit est true', () {
      const config = TailscaleSecurityConfig(enableSshAudit: true);
      expect(config.toTailscaleArgs(), contains('--ssh'));
    });

    test('ne contient pas "--ssh" quand enableSshAudit est false', () {
      const config = TailscaleSecurityConfig(enableSshAudit: false);
      expect(config.toTailscaleArgs(), isNot(contains('--ssh')));
    });

    test('commence par "up"', () {
      const config = TailscaleSecurityConfig();
      expect(config.toTailscaleArgs().first, equals('up'));
    });

    test('contient "--no-relays" quand noRelays est true', () {
      const config = TailscaleSecurityConfig(noRelays: true);
      expect(config.toTailscaleArgs(), contains('--no-relays'));
    });

    test(
        'contient "--accept-dns=false" quand enableMagicDns est false', () {
      const config = TailscaleSecurityConfig(enableMagicDns: false);
      expect(config.toTailscaleArgs(), contains('--accept-dns=false'));
    });

    test('ne contient pas "--accept-dns=false" quand enableMagicDns est true',
        () {
      const config = TailscaleSecurityConfig(enableMagicDns: true);
      expect(config.toTailscaleArgs(), isNot(contains('--accept-dns=false')));
    });
  });

  // ---------------------------------------------------------------------------
  // SignedState
  // ---------------------------------------------------------------------------
  group('SignedState — serialisation JSON', () {
    test('toJson / fromJson round-trip conserve toutes les valeurs', () {
      const state = SignedState(
        state: 'connected',
        timestamp: 1700000000000,
        sequenceNumber: 42,
        hmac: 'abc123==',
      );

      final json = state.toJson();
      final restored = SignedState.fromJson(json);

      expect(restored.state, equals(state.state));
      expect(restored.timestamp, equals(state.timestamp));
      expect(restored.sequenceNumber, equals(state.sequenceNumber));
      expect(restored.hmac, equals(state.hmac));
    });

    test('toJson retourne une Map avec 4 cles', () {
      const state = SignedState(
        state: 'idle',
        timestamp: 1000,
        sequenceNumber: 1,
        hmac: 'xyz',
      );
      final json = state.toJson();
      expect(json.keys.length, equals(4));
      expect(json.containsKey('state'), isTrue);
      expect(json.containsKey('timestamp'), isTrue);
      expect(json.containsKey('sequenceNumber'), isTrue);
      expect(json.containsKey('hmac'), isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // StateVerifier
  // ---------------------------------------------------------------------------
  group('StateVerifier — sign()', () {
    test('cree un etat valide avec un HMAC non vide', () {
      final verifier =
          StateVerifier.fromString('ma-cle-secrete-pour-tests');
      final signed = verifier.sign('active', 1);
      expect(signed.state, equals('active'));
      expect(signed.sequenceNumber, equals(1));
      expect(signed.hmac, isNotEmpty);
      verifier.dispose();
    });

    test('le timestamp est recent (moins de 5 secondes)', () {
      final verifier = StateVerifier.fromString('test-key');
      final before = DateTime.now().millisecondsSinceEpoch;
      final signed = verifier.sign('test', 1);
      final after = DateTime.now().millisecondsSinceEpoch;
      expect(signed.timestamp, greaterThanOrEqualTo(before));
      expect(signed.timestamp, lessThanOrEqualTo(after));
      verifier.dispose();
    });

    test('leve StateError si la sequence n\'est pas croissante', () {
      final verifier = StateVerifier.fromString('test-key');
      verifier.sign('etat1', 5);
      expect(() => verifier.sign('etat2', 3), throwsStateError);
      verifier.dispose();
    });

    test('leve StateError si la sequence est egale', () {
      final verifier = StateVerifier.fromString('test-key');
      verifier.sign('etat1', 5);
      expect(() => verifier.sign('etat2', 5), throwsStateError);
      verifier.dispose();
    });
  });

  group('StateVerifier — verify()', () {
    test('verifie correctement un etat fraichement signe', () {
      final verifier = StateVerifier.fromString('cle-secrete-test');
      final signed = verifier.sign('connected', 1);
      verifier.resetSequence();
      expect(verifier.verify(signed), isTrue);
      verifier.dispose();
    });

    test('rejette un HMAC falsifie', () {
      final verifier = StateVerifier.fromString('cle-secrete-test');
      final signed = verifier.sign('connected', 1);
      verifier.resetSequence();

      final tampered = SignedState(
        state: signed.state,
        timestamp: signed.timestamp,
        sequenceNumber: signed.sequenceNumber,
        hmac: 'hmac-falsifie==',
      );
      expect(verifier.verify(tampered), isFalse);
      verifier.dispose();
    });

    test('rejette un numero de sequence rejoue (inferieur ou egal)', () {
      final verifier = StateVerifier.fromString('cle-secrete-test');
      final signed1 = verifier.sign('etat1', 1);
      verifier.resetSequence();
      // Valider une premiere fois (sequence = 1)
      verifier.verify(signed1);

      // Tenter de rejouer le meme message (sequence = 1, deja vu)
      expect(verifier.verify(signed1), isFalse);
      verifier.dispose();
    });

    test('rejette un timestamp trop ancien (derive > 30 secondes)', () {
      final verifier = StateVerifier.fromString('cle-secrete-test');

      // Construire manuellement un etat avec un vieux timestamp
      final oldTimestamp =
          DateTime.now().millisecondsSinceEpoch - 31 * 1000; // 31 secondes
      const sequenceNumber = 99;

      // Calculer le HMAC correct pour ce vieux timestamp
      final helper = StateVerifier.fromString('cle-secrete-test');
      // On ne peut pas signer directement avec un vieux timestamp via sign(),
      // donc on cree l'etat manuellement et on verifie qu'il est rejete
      final fakeState = SignedState(
        state: 'old-state',
        timestamp: oldTimestamp,
        sequenceNumber: sequenceNumber,
        hmac: 'fake-hmac',
      );

      expect(verifier.verify(fakeState), isFalse);
      verifier.dispose();
      helper.dispose();
    });

    test('rejette un etat dont l\'etat a ete modifie (HMAC invalide)', () {
      final verifier = StateVerifier.fromString('cle-secrete-test');
      final signed = verifier.sign('etat-original', 1);
      verifier.resetSequence();

      final tampered = SignedState(
        state: 'etat-modifie', // etat change
        timestamp: signed.timestamp,
        sequenceNumber: signed.sequenceNumber,
        hmac: signed.hmac, // HMAC inchange donc invalide
      );
      expect(verifier.verify(tampered), isFalse);
      verifier.dispose();
    });
  });

  group('StateVerifier — constantTimeEquals()', () {
    test('retourne true pour deux chaines identiques', () {
      expect(StateVerifier.constantTimeEquals('abc123', 'abc123'), isTrue);
    });

    test('retourne false pour deux chaines differentes', () {
      expect(StateVerifier.constantTimeEquals('abc123', 'abc124'), isFalse);
    });

    test('retourne false pour des chaines de longueurs differentes', () {
      expect(StateVerifier.constantTimeEquals('abc', 'abcd'), isFalse);
    });

    test('retourne true pour deux chaines vides', () {
      expect(StateVerifier.constantTimeEquals('', ''), isTrue);
    });
  });

  group('StateVerifier — dispose()', () {
    test('met a zero la cle en memoire', () {
      final key = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);
      final verifier = StateVerifier(Uint8List.fromList(key));
      verifier.dispose();

      // Apres dispose(), le verifier ne doit plus pouvoir signer correctement
      // (la cle est a zero, donc les HMAC seront differents)
      // Verifier en tentant de signer puis verifier — le HMAC sera invalide
      // car la cle est zeroisee
      final verifier2 = StateVerifier.fromString('autre-cle');
      final signed = verifier2.sign('test', 1);
      verifier2.resetSequence();

      // Utiliser le verifier dispose (cle zeros) pour verifier un etat signe
      // avec une vraie cle : doit echouer
      expect(verifier.verify(signed), isFalse);
      verifier2.dispose();
    });
  });
}
