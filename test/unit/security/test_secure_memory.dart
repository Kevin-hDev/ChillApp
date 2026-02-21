// Test for FIX-001 : Secure memory cleanup
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:chill_app/core/security/secure_memory.dart';

void main() {
  group('SecureBytes', () {
    test('stores and returns data correctly', () {
      final secret = SecureBytes.fromString('12345678');
      expect(secret.bytes, isNotEmpty);
      expect(secret.length, equals(8));
      secret.dispose();
    });

    test('dispose zeroes the memory', () {
      final secret = SecureBytes.fromList([1, 2, 3, 4, 5, 6, 7, 8]);
      final bytesRef = secret.bytes; // Reference to the same Uint8List
      secret.dispose();
      // After dispose, the content must be all zeros
      expect(bytesRef.every((b) => b == 0), isTrue);
    });

    test('access after dispose throws StateError', () {
      final secret = SecureBytes.fromString('test');
      secret.dispose();
      expect(() => secret.bytes, throwsStateError);
    });

    test('double dispose has no effect', () {
      final secret = SecureBytes.fromString('test');
      secret.dispose();
      secret.dispose(); // No exception
      expect(secret.isDisposed, isTrue);
    });

    test('fromList constructor stores correct bytes', () {
      final data = [10, 20, 30, 40];
      final secret = SecureBytes.fromList(data);
      expect(secret.length, equals(4));
      expect(secret.bytes[0], equals(10));
      expect(secret.bytes[3], equals(40));
      secret.dispose();
    });

    test('length constructor creates zero-filled buffer', () {
      final secret = SecureBytes(16);
      expect(secret.length, equals(16));
      expect(secret.bytes.every((b) => b == 0), isTrue);
      secret.dispose();
    });
  });

  group('SecureUint8ListExtension', () {
    test('secureZero zeroes all content', () {
      final data = Uint8List.fromList([10, 20, 30, 40]);
      data.secureZero();
      expect(data.every((b) => b == 0), isTrue);
    });

    test('secureZero works on empty list', () {
      final data = Uint8List(0);
      data.secureZero(); // No exception
      expect(data.length, equals(0));
    });
  });

  group('constantTimeEquals', () {
    test('returns true for identical lists', () {
      expect(constantTimeEquals([1, 2, 3], [1, 2, 3]), isTrue);
    });

    test('returns false for different lists', () {
      expect(constantTimeEquals([1, 2, 3], [1, 2, 4]), isFalse);
    });

    test('returns false for different lengths', () {
      expect(constantTimeEquals([1, 2], [1, 2, 3]), isFalse);
    });

    test('returns true for empty lists', () {
      expect(constantTimeEquals([], []), isTrue);
    });

    test('works with Uint8List', () {
      final a = Uint8List.fromList([0xAB, 0xCD, 0xEF]);
      final b = Uint8List.fromList([0xAB, 0xCD, 0xEF]);
      expect(constantTimeEquals(a, b), isTrue);
    });

    test('returns false when first bytes differ', () {
      final a = Uint8List.fromList([0x01, 0xCD, 0xEF]);
      final b = Uint8List.fromList([0xFF, 0xCD, 0xEF]);
      expect(constantTimeEquals(a, b), isFalse);
    });
  });
}
