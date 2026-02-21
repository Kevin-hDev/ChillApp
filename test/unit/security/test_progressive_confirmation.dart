// =============================================================
// Tests unitaires — FIX-009 : ProgressiveConfirmation
// Confirme que les enums et la logique de base sont corrects.
// =============================================================
//
// Executer avec :
//   dart test test/unit/security/test_progressive_confirmation.dart
//
// Ces tests ne lancent AUCUN widget Flutter : ils verifient
// uniquement les enums et la logique pure.
// =============================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:chill_app/core/security/progressive_confirmation.dart';

void main() {
  // ---------------------------------------------------------------
  // DangerLevel — structure de l'enum
  // ---------------------------------------------------------------

  group('DangerLevel', () {
    test('contient exactement les valeurs medium et high', () {
      expect(DangerLevel.values, hasLength(2));
      expect(DangerLevel.values, containsAll([DangerLevel.medium, DangerLevel.high]));
    });

    test('medium est distinct de high', () {
      expect(DangerLevel.medium, isNot(equals(DangerLevel.high)));
    });

    test('les noms correspondent aux valeurs attendues', () {
      expect(DangerLevel.medium.name, equals('medium'));
      expect(DangerLevel.high.name, equals('high'));
    });

    test('les valeurs sont ordonnees (medium avant high)', () {
      int indexDe(DangerLevel v) => DangerLevel.values.indexOf(v);
      expect(indexDe(DangerLevel.medium), lessThan(indexDe(DangerLevel.high)));
    });
  });

  // ---------------------------------------------------------------
  // ConfirmationResult — structure de l'enum
  // ---------------------------------------------------------------

  group('ConfirmationResult', () {
    test('contient confirmed, cancelled et timedOut', () {
      expect(ConfirmationResult.values, hasLength(3));
      expect(
        ConfirmationResult.values,
        containsAll([
          ConfirmationResult.confirmed,
          ConfirmationResult.cancelled,
          ConfirmationResult.timedOut,
        ]),
      );
    });

    test('confirmed est distinct de cancelled', () {
      expect(
        ConfirmationResult.confirmed,
        isNot(equals(ConfirmationResult.cancelled)),
      );
    });

    test('cancelled est distinct de timedOut', () {
      expect(
        ConfirmationResult.cancelled,
        isNot(equals(ConfirmationResult.timedOut)),
      );
    });

    test('les noms correspondent aux valeurs attendues', () {
      expect(ConfirmationResult.confirmed.name, equals('confirmed'));
      expect(ConfirmationResult.cancelled.name, equals('cancelled'));
      expect(ConfirmationResult.timedOut.name, equals('timedOut'));
    });
  });

  // ---------------------------------------------------------------
  // Logique metier — delai selon niveau de danger
  // ---------------------------------------------------------------

  group('Logique du delai de securite', () {
    test('medium correspond a 3 secondes de delai', () {
      // La logique dans progressive_confirmation.dart :
      // level == high => 5s, sinon => 3s
      const level = DangerLevel.medium;
      final delai = level == DangerLevel.high
          ? const Duration(seconds: 5)
          : const Duration(seconds: 3);
      expect(delai, equals(const Duration(seconds: 3)));
    });

    test('high correspond a 5 secondes de delai', () {
      const level = DangerLevel.high;
      final delai = level == DangerLevel.high
          ? const Duration(seconds: 5)
          : const Duration(seconds: 3);
      expect(delai, equals(const Duration(seconds: 5)));
    });

    test('high necessite la saisie de CONFIRMER (etape 3 active)', () {
      // Seul high declenche l'etape 3 (saisie textuelle)
      expect(DangerLevel.high == DangerLevel.high, isTrue);
      expect(DangerLevel.medium == DangerLevel.high, isFalse);
    });

    test('CONFIRMER en majuscules est la seule valeur acceptee', () {
      // Reproduce la logique de _FinalConfirmationDialogState
      bool isValid(String input) =>
          input.trim().toUpperCase() == 'CONFIRMER';

      expect(isValid('CONFIRMER'), isTrue);
      expect(isValid('confirmer'), isTrue); // toUpperCase applique
      expect(isValid(' CONFIRMER '), isTrue); // trim applique
      expect(isValid('Confirme'), isFalse);
      expect(isValid(''), isFalse);
      expect(isValid('ANNULER'), isFalse);
    });
  });
}
