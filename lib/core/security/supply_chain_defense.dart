// =============================================================
// FIX-056 : Defense Supply Chain IA (slopsquatting)
// GAP-056 : Defense supply chain IA absente (P2)
// Cible   : lib/core/security/supply_chain_defense.dart
// =============================================================
//
// PROBLEME : 20 % des packages suggeres par IA sont hallucines.
// Risque de slopsquatting (faux packages malveillants sur pub.dev).
//
// SOLUTION :
// 1. Audit du fichier pubspec.lock
// 2. Detection des packages typosquatted (noms suspects)
// 3. Verification de la source (pub.dev, git, path, sdk)
// 4. Integrable dans le CI/CD
// =============================================================

import 'dart:io';

/// Resultat de l'audit d'un package individuel.
class PackageAuditResult {
  /// Nom du package audite.
  final String name;

  /// Version du package.
  final String version;

  /// Niveau de severite : 'critical', 'warning', 'info', 'ok'.
  final String severity;

  /// Message explicatif.
  final String message;

  const PackageAuditResult({
    required this.name,
    required this.version,
    required this.severity,
    required this.message,
  });

  /// Retourne true si le resultat est critique (blocage build recommande).
  bool get isCritical => severity == 'critical';

  /// Retourne true si le resultat est un avertissement.
  bool get isWarning => severity == 'warning';

  @override
  String toString() => '[$severity] $name $version: $message';
}

/// Auditeur de la chaine d'approvisionnement Dart.
///
/// Analyse le fichier `pubspec.lock` pour detecter :
/// - Le typosquatting (noms proches de packages populaires)
/// - Les packages venant de sources non officielles (git, path)
/// - Les packages inconnus (pas dans la liste de confiance)
class SupplyChainDefense {
  /// Packages connus et verifies pour ChillApp.
  ///
  /// Ajouter chaque nouveau package apres verification manuelle sur pub.dev
  /// (auteur verifie, date de creation, nombre de likes).
  static const Set<String> trustedPackages = {
    // UI / Framework
    'flutter_riverpod',
    'riverpod',
    'go_router',
    'google_fonts',
    'cupertino_icons',
    // Persistance
    'shared_preferences',
    // Securite / Cryptographie
    'crypto',
    'pointycastle',
    // Reseau / SSH
    'dartssh2',
    'url_launcher',
    // Utilitaires
    'path_provider',
    'path',
    'collection',
    'meta',
    'intl',
    'async',
    'characters',
    // Lints
    'flutter_lints',
  };

  /// Patterns de noms suspects (typosquatting connu).
  ///
  /// Ces patterns imitent des packages populaires avec de legeres
  /// differences (tirets, doubles lettres, fautes de frappe).
  static const List<String> suspiciousPatterns = [
    'flutter-', // Tiret au lieu d'underscore (invalide sur pub.dev)
    'flutterr', // Double lettre r
    'riverpood', // Typo de riverpod
    'riverpot', // Autre typo
    'cripto', // Typo de crypto
    'crytpo', // Inversion de lettres
    'crypt0', // Zero a la place de o
    'go_routerr', // Double lettre
    'shared-preferences', // Tiret au lieu d'underscore
    'dartssh', // Nom tronque
    'dartssh3', // Version inexistante
  ];

  // ---------------------------------------------------------
  // Audit principal
  // ---------------------------------------------------------

  /// Audite le fichier `pubspec.lock` situe a [lockFilePath].
  ///
  /// Retourne une liste de [PackageAuditResult]. Si aucun probleme
  /// n'est detecte, retourne un seul resultat 'ok'.
  ///
  /// Severites :
  /// - `critical` : Possible typosquatting → bloquer le build
  /// - `warning`  : Source git (non officielle)
  /// - `info`     : Package inconnu ou source path
  /// - `ok`       : Tout est intact
  static Future<List<PackageAuditResult>> auditPubspecLock(
    String lockFilePath,
  ) async {
    final results = <PackageAuditResult>[];
    final file = File(lockFilePath);

    if (!await file.exists()) {
      return [
        const PackageAuditResult(
          name: 'pubspec.lock',
          version: '',
          severity: 'critical',
          message: 'Fichier pubspec.lock introuvable',
        ),
      ];
    }

    final content = await file.readAsString();
    final packages = _parsePubspecLock(content);

    for (final pkg in packages) {
      _auditPackage(pkg, results);
    }

    // Resume si tout est OK
    if (results.isEmpty) {
      results.add(PackageAuditResult(
        name: 'audit',
        version: '',
        severity: 'ok',
        message: '${packages.length} packages verifies — aucun probleme detecte',
      ));
    }

    return results;
  }

  /// Audite une liste de packages en memoire (sans fichier disque).
  ///
  /// Utile pour les tests et la validation CI qui construit la
  /// liste de packages programmatiquement.
  static List<PackageAuditResult> auditPackageList(
    List<Map<String, String>> packages,
  ) {
    final results = <PackageAuditResult>[];

    for (final pkgMap in packages) {
      final pkg = _PackageInfo(
        name: pkgMap['name'] ?? '',
        version: pkgMap['version'] ?? 'unknown',
        source: pkgMap['source'] ?? 'unknown',
      );
      _auditPackage(pkg, results);
    }

    if (results.isEmpty) {
      results.add(PackageAuditResult(
        name: 'audit',
        version: '',
        severity: 'ok',
        message:
            '${packages.length} packages verifies — aucun probleme detecte',
      ));
    }

    return results;
  }

  // ---------------------------------------------------------
  // Logique d'audit d'un package
  // ---------------------------------------------------------

  static void _auditPackage(
    _PackageInfo pkg,
    List<PackageAuditResult> results,
  ) {
    // 1. Patterns suspects (typosquatting)
    for (final pattern in suspiciousPatterns) {
      if (pkg.name.contains(pattern)) {
        results.add(PackageAuditResult(
          name: pkg.name,
          version: pkg.version,
          severity: 'critical',
          message: 'Nom suspect (possible typosquatting) : contient "$pattern"',
        ));
        break; // Un seul critical par package
      }
    }

    // 2. Package inconnu (hors liste de confiance et hors SDK)
    if (!trustedPackages.contains(pkg.name) &&
        !pkg.name.startsWith('flutter_') &&
        !pkg.name.startsWith('flutter') &&
        pkg.source != 'sdk') {
      results.add(PackageAuditResult(
        name: pkg.name,
        version: pkg.version,
        severity: 'info',
        message: 'Package absent de la liste de confiance',
      ));
    }

    // 3. Source git (non officielle)
    if (pkg.source == 'git') {
      results.add(PackageAuditResult(
        name: pkg.name,
        version: pkg.version,
        severity: 'warning',
        message: 'Package installe depuis git (pas pub.dev)',
      ));
    }

    // 4. Source path (local)
    if (pkg.source == 'path') {
      results.add(PackageAuditResult(
        name: pkg.name,
        version: pkg.version,
        severity: 'info',
        message: 'Package local (source: path) — verifier en production',
      ));
    }
  }

  // ---------------------------------------------------------
  // Parser pubspec.lock
  // ---------------------------------------------------------

  /// Parse simplifiee du format YAML de pubspec.lock.
  ///
  /// Extrait : nom, version et source de chaque package.
  /// Les sections `packages:` et `sdks:` sont ignorees.
  static List<_PackageInfo> _parsePubspecLock(String content) {
    final packages = <_PackageInfo>[];
    String? currentPackage;
    String? currentVersion;
    String? currentSource;

    bool inPackagesSection = false;

    for (final rawLine in content.split('\n')) {
      final line = rawLine.trimRight();

      // Entrer dans la section "packages:"
      if (line == 'packages:') {
        inPackagesSection = true;
        continue;
      }

      // Quitter la section packages si on revient a la racine
      if (inPackagesSection && !line.startsWith(' ') && line.isNotEmpty) {
        inPackagesSection = false;
      }

      if (!inPackagesSection) continue;

      // Nom du package : 2 espaces d'indentation + nom + ":"
      if (line.startsWith('  ') && !line.startsWith('   ') &&
          line.trim().endsWith(':')) {
        // Sauvegarder le package precedent
        if (currentPackage != null) {
          packages.add(_PackageInfo(
            name: currentPackage,
            version: currentVersion ?? 'unknown',
            source: currentSource ?? 'unknown',
          ));
        }
        currentPackage = line.trim().replaceAll(':', '');
        currentVersion = null;
        currentSource = null;
        continue;
      }

      // Version : "    version: "x.y.z""
      if (line.contains('    version:')) {
        currentVersion =
            line.split(':').last.trim().replaceAll('"', '').replaceAll("'", '');
      }

      // Source : "    source: hosted|git|path|sdk"
      if (line.contains('    source:')) {
        currentSource =
            line.split(':').last.trim().replaceAll('"', '').replaceAll("'", '');
      }
    }

    // Dernier package non encore sauvegarde
    if (currentPackage != null) {
      packages.add(_PackageInfo(
        name: currentPackage,
        version: currentVersion ?? 'unknown',
        source: currentSource ?? 'unknown',
      ));
    }

    return packages;
  }
}

/// Informations internes d'un package extrait de pubspec.lock.
class _PackageInfo {
  final String name;
  final String version;
  final String source;

  const _PackageInfo({
    required this.name,
    required this.version,
    required this.source,
  });
}
