// Test unitaire pour FIX-031/040 — PostQuantumReadiness
// Lance avec : flutter test test/unit/security/test_post_quantum_readiness.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:chill_app/core/security/post_quantum_readiness.dart';

void main() {
  // ============================================================
  // PqReadiness enum
  // ============================================================

  group('PqReadiness — enum', () {
    test('contient la valeur notReady', () {
      expect(PqReadiness.values, contains(PqReadiness.notReady));
    });

    test('contient la valeur partial', () {
      expect(PqReadiness.values, contains(PqReadiness.partial));
    });

    test('contient la valeur ready', () {
      expect(PqReadiness.values, contains(PqReadiness.ready));
    });

    test('contient exactement 3 valeurs', () {
      expect(PqReadiness.values.length, 3);
    });

    test('notReady a le bon nom', () {
      expect(PqReadiness.notReady.name, 'notReady');
    });

    test('partial a le bon nom', () {
      expect(PqReadiness.partial.name, 'partial');
    });

    test('ready a le bon nom', () {
      expect(PqReadiness.ready.name, 'ready');
    });
  });

  // ============================================================
  // PostQuantumAlgorithms — constantes
  // ============================================================

  group('PostQuantumAlgorithms — constantes', () {
    test('kexTarget est mlkem768x25519-sha256', () {
      expect(PostQuantumAlgorithms.kexTarget, 'mlkem768x25519-sha256');
    });

    test('kexTransitional est sntrup761x25519-sha512@openssh.com', () {
      expect(
        PostQuantumAlgorithms.kexTransitional,
        'sntrup761x25519-sha512@openssh.com',
      );
    });

    test('signatureTarget est ml-dsa-65', () {
      expect(PostQuantumAlgorithms.signatureTarget, 'ml-dsa-65');
    });

    test('symmetricNote mentionne AES-256-GCM', () {
      expect(PostQuantumAlgorithms.symmetricNote, contains('AES-256-GCM'));
    });

    test('symmetricNote mentionne ChaCha20-Poly1305', () {
      expect(PostQuantumAlgorithms.symmetricNote, contains('ChaCha20-Poly1305'));
    });

    test('symmetricNote mentionne 128 bits', () {
      expect(PostQuantumAlgorithms.symmetricNote, contains('128 bits'));
    });

    test('wireguardNote mentionne WireGuard', () {
      expect(PostQuantumAlgorithms.wireguardNote, contains('WireGuard'));
    });

    test('wireguardNote mentionne Curve25519', () {
      expect(PostQuantumAlgorithms.wireguardNote, contains('Curve25519'));
    });

    test('wireguardNote mentionne Rosenpass', () {
      expect(PostQuantumAlgorithms.wireguardNote, contains('Rosenpass'));
    });

    test('kexTarget ne contient pas d\'algorithme classique vulnerable', () {
      // ML-KEM est post-quantique : ne doit pas etre diffie-hellman classique
      expect(PostQuantumAlgorithms.kexTarget, isNot(startsWith('diffie-hellman')));
    });
  });

  // ============================================================
  // PqAssessment — construction et champs
  // ============================================================

  group('PqAssessment — construction et champs', () {
    test('construction avec tous les champs requis', () {
      final date = DateTime(2026, 2, 18);
      final assessment = PqAssessment(
        readiness: PqReadiness.notReady,
        findings: ['Constat A', 'Constat B'],
        requiredActions: ['Action 1'],
        assessmentDate: date,
      );

      expect(assessment.readiness, PqReadiness.notReady);
      expect(assessment.findings, ['Constat A', 'Constat B']);
      expect(assessment.requiredActions, ['Action 1']);
      expect(assessment.assessmentDate, date);
    });

    test('champ readiness est accessible', () {
      final assessment = PqAssessment(
        readiness: PqReadiness.partial,
        findings: [],
        requiredActions: [],
        assessmentDate: DateTime.now(),
      );
      expect(assessment.readiness, PqReadiness.partial);
    });

    test('champ findings est accessible et peut etre vide', () {
      final assessment = PqAssessment(
        readiness: PqReadiness.ready,
        findings: [],
        requiredActions: [],
        assessmentDate: DateTime.now(),
      );
      expect(assessment.findings, isEmpty);
    });

    test('champ requiredActions est accessible', () {
      final assessment = PqAssessment(
        readiness: PqReadiness.notReady,
        findings: ['f1'],
        requiredActions: ['action1', 'action2'],
        assessmentDate: DateTime.now(),
      );
      expect(assessment.requiredActions.length, 2);
    });

    test('champ assessmentDate est accessible', () {
      final now = DateTime.now();
      final assessment = PqAssessment(
        readiness: PqReadiness.notReady,
        findings: [],
        requiredActions: [],
        assessmentDate: now,
      );
      expect(assessment.assessmentDate, now);
    });

    test('findings peut contenir plusieurs entrees', () {
      final assessment = PqAssessment(
        readiness: PqReadiness.partial,
        findings: ['f1', 'f2', 'f3', 'f4'],
        requiredActions: [],
        assessmentDate: DateTime.now(),
      );
      expect(assessment.findings.length, 4);
    });
  });

  // ============================================================
  // PostQuantumChecker.assess()
  // ============================================================

  group('PostQuantumChecker.assess()', () {
    test('retourne un PqAssessment (objet non nul)', () async {
      final assessment = await PostQuantumChecker.assess();
      // ignore: unnecessary_null_comparison
      expect(assessment, isNotNull);
    });

    test('readiness est une valeur valide de PqReadiness', () async {
      final assessment = await PostQuantumChecker.assess();
      expect(PqReadiness.values, contains(assessment.readiness));
    });

    test('findings est non vide (au minimum les constats fixes)', () async {
      final assessment = await PostQuantumChecker.assess();
      // Les constats sur dartssh2, WireGuard et AES-256 sont toujours presents
      expect(assessment.findings, isNotEmpty);
    });

    test('findings contient un constat sur dartssh2', () async {
      final assessment = await PostQuantumChecker.assess();
      final hasDartssh2 = assessment.findings.any(
        (f) => f.contains('dartssh2'),
      );
      expect(hasDartssh2, isTrue);
    });

    test('findings contient un constat sur WireGuard', () async {
      final assessment = await PostQuantumChecker.assess();
      final hasWireguard = assessment.findings.any(
        (f) => f.contains('WireGuard'),
      );
      expect(hasWireguard, isTrue);
    });

    test('findings contient un constat sur AES-256/ChaCha20', () async {
      final assessment = await PostQuantumChecker.assess();
      final hasSymmetric = assessment.findings.any(
        (f) => f.contains('AES-256') || f.contains('ChaCha20'),
      );
      expect(hasSymmetric, isTrue);
    });

    test('requiredActions est non vide', () async {
      final assessment = await PostQuantumChecker.assess();
      expect(assessment.requiredActions, isNotEmpty);
    });

    test('requiredActions contient une action dartssh2', () async {
      final assessment = await PostQuantumChecker.assess();
      final hasDartssh2Action = assessment.requiredActions.any(
        (a) => a.contains('dartssh2'),
      );
      expect(hasDartssh2Action, isTrue);
    });

    test('assessmentDate est proche de maintenant (moins de 30 secondes)', () async {
      final before = DateTime.now();
      final assessment = await PostQuantumChecker.assess();
      final after = DateTime.now();

      expect(
        assessment.assessmentDate.isAfter(
          before.subtract(const Duration(seconds: 1)),
        ),
        isTrue,
      );
      expect(
        assessment.assessmentDate.isBefore(
          after.add(const Duration(seconds: 30)),
        ),
        isTrue,
      );
    });

    test('readiness ne peut pas etre ready (dartssh2 ne supporte pas PQ)', () async {
      // En fevrier 2026, dartssh2 ne supporte pas PQ.
      // Le statut ready ne peut pas etre atteint avec la logique actuelle.
      final assessment = await PostQuantumChecker.assess();
      expect(assessment.readiness, isNot(PqReadiness.ready));
    });
  });

  // ============================================================
  // PostQuantumChecker.generateReport()
  // ============================================================

  group('PostQuantumChecker.generateReport()', () {
    test('retourne une String non vide', () async {
      final report = await PostQuantumChecker.generateReport();
      expect(report, isNotEmpty);
    });

    test('contient le titre principal', () async {
      final report = await PostQuantumChecker.generateReport();
      expect(report, contains('Evaluation Post-Quantique'));
    });

    test('contient la section Constats', () async {
      final report = await PostQuantumChecker.generateReport();
      expect(report, contains('## Constats'));
    });

    test('contient la section Actions Requises', () async {
      final report = await PostQuantumChecker.generateReport();
      expect(report, contains('## Actions Requises'));
    });

    test('contient la section Strategie de Migration', () async {
      final report = await PostQuantumChecker.generateReport();
      expect(report, contains('## Strategie de Migration'));
    });

    test('contient la Phase 1', () async {
      final report = await PostQuantumChecker.generateReport();
      expect(report, contains('### Phase 1'));
    });

    test('contient la Phase 2', () async {
      final report = await PostQuantumChecker.generateReport();
      expect(report, contains('### Phase 2'));
    });

    test('contient la Phase 3', () async {
      final report = await PostQuantumChecker.generateReport();
      expect(report, contains('### Phase 3'));
    });

    test('contient la Phase 4', () async {
      final report = await PostQuantumChecker.generateReport();
      expect(report, contains('### Phase 4'));
    });

    test('contient la date au format ISO8601', () async {
      final report = await PostQuantumChecker.generateReport();
      // La date ISO 8601 contient un T entre la date et l'heure
      expect(report, contains('Date:'));
      expect(report, matches(RegExp(r'Date: \d{4}-\d{2}-\d{2}T')));
    });

    test('contient le champ Etat', () async {
      final report = await PostQuantumChecker.generateReport();
      expect(report, contains('Etat:'));
    });

    test('contient la mention de dartssh2 dans le rapport', () async {
      final report = await PostQuantumChecker.generateReport();
      expect(report, contains('dartssh2'));
    });

    test('contient la mention de ML-KEM', () async {
      final report = await PostQuantumChecker.generateReport();
      expect(report, contains('ML-KEM'));
    });

    test('contient la mention de Rosenpass', () async {
      final report = await PostQuantumChecker.generateReport();
      expect(report, contains('Rosenpass'));
    });

    test('contient la mention de ML-DSA', () async {
      final report = await PostQuantumChecker.generateReport();
      expect(report, contains('ML-DSA'));
    });

    test('le rapport fait plus de 500 caracteres (rapport substantiel)', () async {
      final report = await PostQuantumChecker.generateReport();
      expect(report.length, greaterThan(500));
    });
  });
}
