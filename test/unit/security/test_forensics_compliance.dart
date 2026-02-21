// Tests unitaires pour FIX-057/058 — Forensics & CRA Compliance
// Lance avec : flutter test test/unit/security/test_forensics_compliance.dart
//
// Verifie les enums, la serialisation ForensicEvidence,
// le rapport ForensicsCollector et les templates CRA.
// Les tests evitent tout I/O reel quand c'est possible.

import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:chill_app/core/security/forensics_compliance.dart';

void main() {
  // ===========================================================================
  // ForensicEvidenceType enum
  // ===========================================================================

  group('ForensicEvidenceType enum', () {
    test('contient exactement 5 valeurs', () {
      expect(ForensicEvidenceType.values.length, 5);
    });

    test('contient les 5 types attendus', () {
      expect(ForensicEvidenceType.values, containsAll([
        ForensicEvidenceType.binaryIntegrity,
        ForensicEvidenceType.networkAnomaly,
        ForensicEvidenceType.fileAnomaly,
        ForensicEvidenceType.processAnomaly,
        ForensicEvidenceType.logAnomaly,
      ]));
    });

    test('chaque type a un nom string distinct', () {
      final names = ForensicEvidenceType.values.map((e) => e.name).toSet();
      expect(names.length, ForensicEvidenceType.values.length);
    });
  });

  // ===========================================================================
  // ForensicEvidence — serialisation toJson
  // ===========================================================================

  group('ForensicEvidence — serialisation toJson', () {
    late DateTime fixedDate;
    late ForensicEvidence evidence;

    setUp(() {
      fixedDate = DateTime(2026, 2, 18, 15, 0, 0);
      evidence = ForensicEvidence(
        type: ForensicEvidenceType.binaryIntegrity,
        collectedAt: fixedDate,
        description: 'Hash SHA-256 du binaire principal',
        data: {
          'path': '/usr/bin/chill_app',
          'sha256': 'abc123def456',
          'size': 4096,
        },
      );
    });

    test('toJson contient le champ type', () {
      final json = evidence.toJson();
      expect(json.containsKey('type'), isTrue);
    });

    test('toJson contient le champ collected_at', () {
      final json = evidence.toJson();
      expect(json.containsKey('collected_at'), isTrue);
    });

    test('toJson contient le champ description', () {
      final json = evidence.toJson();
      expect(json.containsKey('description'), isTrue);
    });

    test('toJson contient le champ data', () {
      final json = evidence.toJson();
      expect(json.containsKey('data'), isTrue);
    });

    test('type est serialise comme son nom (string)', () {
      final json = evidence.toJson();
      expect(json['type'], 'binaryIntegrity');
    });

    test('collected_at est serialise en ISO 8601', () {
      final json = evidence.toJson();
      final parsed = DateTime.parse(json['collected_at'] as String);
      expect(parsed.year, fixedDate.year);
      expect(parsed.month, fixedDate.month);
      expect(parsed.day, fixedDate.day);
    });

    test('description est preservee telle quelle', () {
      final json = evidence.toJson();
      expect(json['description'], 'Hash SHA-256 du binaire principal');
    });

    test('data contient les sous-champs corrects', () {
      final json = evidence.toJson();
      final data = json['data'] as Map<String, dynamic>;
      expect(data['path'], '/usr/bin/chill_app');
      expect(data['sha256'], 'abc123def456');
      expect(data['size'], 4096);
    });

    test('toJson est serialisable en JSON standard', () {
      final json = evidence.toJson();
      // Ne doit pas lever d'exception
      expect(() => jsonEncode(json), returnsNormally);
    });

    test('chaque ForensicEvidenceType produit un type string correct', () {
      for (final t in ForensicEvidenceType.values) {
        final e = ForensicEvidence(
          type: t,
          collectedAt: DateTime.now(),
          description: 'test',
          data: {},
        );
        expect(e.toJson()['type'], t.name);
      }
    });

    test('data vide est serialise comme map vide', () {
      final e = ForensicEvidence(
        type: ForensicEvidenceType.logAnomaly,
        collectedAt: DateTime.now(),
        description: 'rien',
        data: {},
      );
      expect(e.toJson()['data'], isA<Map>());
      expect((e.toJson()['data'] as Map).isEmpty, isTrue);
    });
  });

  // ===========================================================================
  // ForensicsCollector — generateReport()
  // ===========================================================================

  group('ForensicsCollector — generateReport()', () {
    late ForensicsCollector collector;

    setUp(() {
      collector = ForensicsCollector();
    });

    test('generateReport() retourne une chaine non vide', () {
      final report = collector.generateReport();
      expect(report.isNotEmpty, isTrue);
    });

    test('generateReport() retourne du JSON valide', () {
      final report = collector.generateReport();
      expect(() => jsonDecode(report), returnsNormally);
    });

    test('le rapport contient la cle forensic_report', () {
      final report = jsonDecode(collector.generateReport()) as Map<String, dynamic>;
      expect(report.containsKey('forensic_report'), isTrue);
    });

    test('forensic_report contient generated_at', () {
      final root = jsonDecode(collector.generateReport()) as Map<String, dynamic>;
      final inner = root['forensic_report'] as Map<String, dynamic>;
      expect(inner.containsKey('generated_at'), isTrue);
    });

    test('forensic_report contient platform', () {
      final root = jsonDecode(collector.generateReport()) as Map<String, dynamic>;
      final inner = root['forensic_report'] as Map<String, dynamic>;
      expect(inner.containsKey('platform'), isTrue);
    });

    test('forensic_report contient evidence_count', () {
      final root = jsonDecode(collector.generateReport()) as Map<String, dynamic>;
      final inner = root['forensic_report'] as Map<String, dynamic>;
      expect(inner.containsKey('evidence_count'), isTrue);
    });

    test('forensic_report contient evidence (liste)', () {
      final root = jsonDecode(collector.generateReport()) as Map<String, dynamic>;
      final inner = root['forensic_report'] as Map<String, dynamic>;
      expect(inner.containsKey('evidence'), isTrue);
      expect(inner['evidence'], isA<List>());
    });

    test('evidence_count est un entier non negatif', () {
      final root = jsonDecode(collector.generateReport()) as Map<String, dynamic>;
      final inner = root['forensic_report'] as Map<String, dynamic>;
      final count = inner['evidence_count'] as int;
      expect(count, greaterThanOrEqualTo(0));
    });

    test('generated_at est une date ISO 8601 valide', () {
      final root = jsonDecode(collector.generateReport()) as Map<String, dynamic>;
      final inner = root['forensic_report'] as Map<String, dynamic>;
      final dateStr = inner['generated_at'] as String;
      expect(() => DateTime.parse(dateStr), returnsNormally);
    });

    test('le rapport est indenté (contient des sauts de ligne)', () {
      final report = collector.generateReport();
      expect(report.contains('\n'), isTrue);
    });
  });

  // ===========================================================================
  // ForensicsCollector — collectAll()
  // ===========================================================================

  group('ForensicsCollector — collectAll()', () {
    test('collectAll() ne leve pas d exception', () async {
      final collector = ForensicsCollector();
      expect(() async => await collector.collectAll(), returnsNormally);
    });

    test('collectAll() retourne une liste (meme vide)', () async {
      final collector = ForensicsCollector();
      final result = await collector.collectAll();
      expect(result, isA<List<ForensicEvidence>>());
    });

    test('collectAll() multiple fois ne crash pas', () async {
      final collector = ForensicsCollector();
      await collector.collectAll();
      final second = await collector.collectAll();
      expect(second, isA<List<ForensicEvidence>>());
    });

    test('la liste retournee par collectAll est non modifiable', () async {
      final collector = ForensicsCollector();
      final result = await collector.collectAll();
      // Une liste unmodifiable doit lever UnsupportedError si on tente d'ajouter
      expect(
        () => result.add(ForensicEvidence(
          type: ForensicEvidenceType.logAnomaly,
          collectedAt: DateTime.now(),
          description: 'fake',
          data: {},
        )),
        throwsUnsupportedError,
      );
    });

    test('evidence_count dans le rapport correspond a la taille de la liste', () async {
      final collector = ForensicsCollector();
      final evidence = await collector.collectAll();
      final report = jsonDecode(collector.generateReport()) as Map<String, dynamic>;
      final inner = report['forensic_report'] as Map<String, dynamic>;
      expect(inner['evidence_count'], evidence.length);
    });
  });

  // ===========================================================================
  // CraCompliance — vulnerabilityNotificationTemplate()
  // ===========================================================================

  group('CraCompliance — vulnerabilityNotificationTemplate()', () {
    late Map<String, dynamic> template;

    setUp(() {
      template = CraCompliance.vulnerabilityNotificationTemplate(
        productName: 'ChillApp',
        vulnerabilityId: 'CVE-2026-0001',
        description: 'Injection via champ SSH',
        severity: 'HIGH',
        status: 'investigating',
      );
    });

    test('retourne un Map non vide', () {
      expect(template.isNotEmpty, isTrue);
    });

    test('contient notification_type', () {
      expect(template.containsKey('notification_type'), isTrue);
    });

    test('contient product', () {
      expect(template.containsKey('product'), isTrue);
    });

    test('contient vulnerability', () {
      expect(template.containsKey('vulnerability'), isTrue);
    });

    test('contient timeline', () {
      expect(template.containsKey('timeline'), isTrue);
    });

    test('contient status', () {
      expect(template.containsKey('status'), isTrue);
      expect(template['status'], 'investigating');
    });

    test('contient cra_reference', () {
      expect(template.containsKey('cra_reference'), isTrue);
    });

    test('cra_reference contient EU 2024/2847', () {
      final ref = template['cra_reference'] as String;
      expect(ref.contains('2024/2847'), isTrue);
    });

    test('product.name correspond au parametre productName', () {
      final product = template['product'] as Map<String, dynamic>;
      expect(product['name'], 'ChillApp');
    });

    test('vulnerability.id correspond au parametre vulnerabilityId', () {
      final vuln = template['vulnerability'] as Map<String, dynamic>;
      expect(vuln['id'], 'CVE-2026-0001');
    });

    test('vulnerability.severity correspond au parametre severity', () {
      final vuln = template['vulnerability'] as Map<String, dynamic>;
      expect(vuln['severity'], 'HIGH');
    });

    test('timeline.reported_at est une date ISO 8601 valide', () {
      final timeline = template['timeline'] as Map<String, dynamic>;
      final reported = timeline['reported_at'] as String;
      expect(() => DateTime.parse(reported), returnsNormally);
    });

    test('contact.manufacturer vaut ChillApp Team', () {
      final contact = template['contact'] as Map<String, dynamic>;
      expect(contact['manufacturer'], 'ChillApp Team');
    });

    test('notification_deadline est present et non vide', () {
      final deadline = template['notification_deadline'];
      expect(deadline, isNotNull);
      expect((deadline as String).isNotEmpty, isTrue);
    });

    test('le template est serialisable en JSON', () {
      expect(() => jsonEncode(template), returnsNormally);
    });

    test('fonctionne avec des parametres differents', () {
      final t2 = CraCompliance.vulnerabilityNotificationTemplate(
        productName: 'TestApp',
        vulnerabilityId: 'CVE-2026-9999',
        description: 'Autre faille',
        severity: 'CRITICAL',
        status: 'fixed',
      );
      final product = t2['product'] as Map<String, dynamic>;
      final vuln = t2['vulnerability'] as Map<String, dynamic>;
      expect(product['name'], 'TestApp');
      expect(vuln['id'], 'CVE-2026-9999');
      expect(vuln['severity'], 'CRITICAL');
      expect(t2['status'], 'fixed');
    });
  });

  // ===========================================================================
  // CraCompliance — complianceChecklist()
  // ===========================================================================

  group('CraCompliance — complianceChecklist()', () {
    late List<Map<String, dynamic>> checklist;

    setUp(() {
      checklist = CraCompliance.complianceChecklist();
    });

    test('retourne une liste non vide', () {
      expect(checklist.isNotEmpty, isTrue);
    });

    test('chaque element contient requirement', () {
      for (final item in checklist) {
        expect(item.containsKey('requirement'), isTrue,
            reason: 'Manque "requirement" dans $item');
      }
    });

    test('chaque element contient article', () {
      for (final item in checklist) {
        expect(item.containsKey('article'), isTrue,
            reason: 'Manque "article" dans $item');
      }
    });

    test('chaque element contient status', () {
      for (final item in checklist) {
        expect(item.containsKey('status'), isTrue,
            reason: 'Manque "status" dans $item');
      }
    });

    test('chaque element contient details', () {
      for (final item in checklist) {
        expect(item.containsKey('details'), isTrue,
            reason: 'Manque "details" dans $item');
      }
    });

    test('contient un element avec Article 13', () {
      final articles = checklist.map((e) => e['article'] as String).toList();
      expect(articles.any((a) => a.contains('13')), isTrue);
    });

    test('contient un element avec Article 14', () {
      final articles = checklist.map((e) => e['article'] as String).toList();
      expect(articles.any((a) => a.contains('14')), isTrue);
    });

    test('contient un element avec Article 31', () {
      final articles = checklist.map((e) => e['article'] as String).toList();
      expect(articles.any((a) => a.contains('31')), isTrue);
    });

    test('tous les champs requirement sont des chaines non vides', () {
      for (final item in checklist) {
        final req = item['requirement'] as String;
        expect(req.isNotEmpty, isTrue);
      }
    });

    test('la checklist est serialisable en JSON', () {
      expect(() => jsonEncode(checklist), returnsNormally);
    });

    test('contient au moins 5 elements de conformite', () {
      expect(checklist.length, greaterThanOrEqualTo(5));
    });
  });
}
