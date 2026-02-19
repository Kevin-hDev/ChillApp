// =============================================================
// FIX-031 : Preparation post-quantique (documentation)
// GAP-031: Preparation post-quantique absente (P3)
// FIX-040 : Preparation IETF post-quantique SSH
// GAP-040: Preparation IETF post-quantique SSH absente (P3)
// Cible: lib/core/security/post_quantum_readiness.dart (nouveau)
// =============================================================
//
// CONTEXTE : Les ordinateurs quantiques (Shor's algorithm)
// pourront casser RSA, ECDSA, et DH classiques.
// Le risque "harvest now, decrypt later" est reel : un attaquant
// enregistre le trafic SSH aujourd'hui et le dechiffre dans 10 ans.
//
// ETAT ACTUEL (fevrier 2026) :
// - OpenSSH 9.0+ supporte sntrup761x25519-sha512@openssh.com
// - OpenSSH 10+ supportera ML-KEM (FIPS 203) via draft-kampanakis
// - dartssh2 ne supporte PAS encore les KEX post-quantiques
// - Tailscale utilise WireGuard (Noise protocol) qui est
//   partiellement resistant (ChaCha20-Poly1305 est symetrique)
//
// CE FICHIER : Documentation et verification de l'etat PQ.
// Pas de code de migration (dartssh2 doit d'abord supporter PQ).
// =============================================================

import 'dart:io';
import 'dart:convert';

/// Etat de la preparation post-quantique.
enum PqReadiness {
  /// Pas pret — algorithmes vulnerables utilises.
  notReady,

  /// Partiellement pret — certains composants migres.
  partial,

  /// Pret — tous les composants supportent PQ.
  ready,
}

/// Algorithmes post-quantiques cibles.
class PostQuantumAlgorithms {
  // --- KEX (Key Exchange) ---
  // NIST FIPS 203 : ML-KEM (Module-Lattice-based KEM)
  // OpenSSH 10+ : mlkem768x25519-sha256
  // Hybride : combine ML-KEM avec X25519 pour la securite transitoire
  static const String kexTarget = 'mlkem768x25519-sha256';

  // --- KEX actuel (transitoire) ---
  // OpenSSH 9.0+ : sntrup761x25519-sha512@openssh.com
  // Hybride NTRU Prime + X25519
  static const String kexTransitional = 'sntrup761x25519-sha512@openssh.com';

  // --- Signatures ---
  // NIST FIPS 204 : ML-DSA (Module-Lattice-based Digital Signature)
  // Pas encore dans OpenSSH (prevu pour OpenSSH 11+)
  static const String signatureTarget = 'ml-dsa-65';

  // --- Algorithmes symetriques ---
  // AES-256 et SHA-384+ sont deja resistants (Grover's algorithm
  // ne fait que diviser la securite par 2, donc AES-256 -> 128 bits)
  static const String symmetricNote =
      'AES-256-GCM et ChaCha20-Poly1305 restent securises (128 bits effectifs post-quantique)';

  // --- WireGuard (Tailscale) ---
  // Noise protocol avec Curve25519 (vulnerable a Shor)
  // MAIS le trafic est ephemere (nouvelles cles a chaque session)
  // Rosenpass (pqWireGuard) est en developpement
  static const String wireguardNote =
      'WireGuard utilise Curve25519 (vulnerable). '
      'Rosenpass (PQ WireGuard) est en cours de standardisation. '
      'Le risque est attenue par les sessions ephemeres.';
}

/// Verificateur de l'etat post-quantique du systeme.
class PostQuantumChecker {
  /// Verifie la version d'OpenSSH et le support PQ.
  static Future<PqAssessment> assess() async {
    final findings = <String>[];
    final actions = <String>[];
    var readiness = PqReadiness.notReady;

    // 1. Verifier la version OpenSSH
    try {
      final result = await Process.run('ssh', ['-V']);
      // ssh -V ecrit sur stderr
      final version = result.stderr.toString().trim();
      final match = RegExp(r'OpenSSH_(\d+)\.(\d+)').firstMatch(version);

      if (match != null) {
        final major = int.parse(match.group(1)!);
        final minor = int.parse(match.group(2)!);

        findings.add('OpenSSH version: $major.$minor');

        if (major >= 10) {
          findings.add('ML-KEM (FIPS 203) supporte via mlkem768x25519-sha256');
          readiness = PqReadiness.partial;
        } else if (major >= 9) {
          findings.add('sntrup761x25519-sha512 disponible (transitoire)');
          readiness = PqReadiness.partial;
        } else {
          findings.add('Aucun support KEX post-quantique');
          actions.add('Mettre a jour OpenSSH vers >= 9.0 pour le KEX hybride');
        }
      }
    } catch (_) {
      findings.add('OpenSSH non installe ou non accessible');
    }

    // 2. Verifier dartssh2
    findings.add('dartssh2: Aucun support PQ (fevrier 2026)');
    actions.add('Surveiller https://github.com/TerminalStudio/dartssh2 '
        'pour le support ML-KEM');
    actions.add('Alternative: utiliser le binaire ssh natif en fallback '
        'quand dartssh2 ne peut pas negocier PQ');

    // 3. Verifier Tailscale/WireGuard
    findings.add('WireGuard: Curve25519 (vulnerable long terme)');
    actions.add('Surveiller le projet Rosenpass pour PQ WireGuard');
    actions.add('Les sessions ephemeres de Tailscale attenuent le risque');

    // 4. Verifier les algorithmes symetriques
    findings.add('AES-256/ChaCha20: OK (resistants post-quantique)');

    // 5. Recommandation d'hybridation
    if (readiness != PqReadiness.ready) {
      actions.add(
        'PRIORITE: Quand dartssh2 supportera PQ, activer '
        'l\'hybridation ml-kem768x25519-sha256 + curve25519-sha256 '
        'pour une defense en profondeur',
      );
    }

    return PqAssessment(
      readiness: readiness,
      findings: findings,
      requiredActions: actions,
      assessmentDate: DateTime.now(),
    );
  }

  /// Genere un rapport PQ humainement lisible.
  static Future<String> generateReport() async {
    final assessment = await assess();
    final buf = StringBuffer();

    buf.writeln('# Evaluation Post-Quantique — ChillApp');
    buf.writeln('Date: ${assessment.assessmentDate.toIso8601String()}');
    buf.writeln('Etat: ${assessment.readiness.name.toUpperCase()}');
    buf.writeln();

    buf.writeln('## Constats');
    for (final f in assessment.findings) {
      buf.writeln('- $f');
    }
    buf.writeln();

    buf.writeln('## Actions Requises');
    for (int i = 0; i < assessment.requiredActions.length; i++) {
      buf.writeln('${i + 1}. ${assessment.requiredActions[i]}');
    }
    buf.writeln();

    buf.writeln('## Strategie de Migration');
    buf.writeln();
    buf.writeln('### Phase 1 (Immediate)');
    buf.writeln('- Utiliser curve25519-sha256 + aes256-gcm (FIX-033)');
    buf.writeln('- Interdire les algorithmes SHA-1 et CBC');
    buf.writeln();
    buf.writeln('### Phase 2 (OpenSSH >= 9.0 cote serveur)');
    buf.writeln('- Activer sntrup761x25519-sha512 sur le serveur SSH');
    buf.writeln('- dartssh2 ne peut pas encore negocier ce KEX');
    buf.writeln('- Utiliser le binaire ssh natif comme fallback PQ');
    buf.writeln();
    buf.writeln('### Phase 3 (dartssh2 + ML-KEM)');
    buf.writeln('- Quand dartssh2 supportera ML-KEM (FIPS 203)');
    buf.writeln('- Activer mlkem768x25519-sha256 en priorite');
    buf.writeln('- Maintenir l\'hybridation avec X25519 en backup');
    buf.writeln();
    buf.writeln('### Phase 4 (Full PQ)');
    buf.writeln('- ML-DSA pour les signatures (FIPS 204)');
    buf.writeln('- Rosenpass pour WireGuard/Tailscale');
    buf.writeln('- Supprimer les algorithmes classiques vulnerables');

    return buf.toString();
  }
}

/// Resultat de l'evaluation PQ.
class PqAssessment {
  final PqReadiness readiness;
  final List<String> findings;
  final List<String> requiredActions;
  final DateTime assessmentDate;

  const PqAssessment({
    required this.readiness,
    required this.findings,
    required this.requiredActions,
    required this.assessmentDate,
  });
}

// =============================================================
// INTEGRATION :
// =============================================================
//
// 1. Afficher l'etat PQ dans l'ecran Securite :
//
//   final assessment = await PostQuantumChecker.assess();
//   // Afficher readiness, findings, actions
//
// 2. Generer un rapport PQ :
//
//   final report = await PostQuantumChecker.generateReport();
//   // Sauvegarder dans un fichier ou afficher
//
// 3. Surveillance dartssh2 :
//   - Verifier regulierement les releases de dartssh2
//   - Quand ML-KEM est supporte, mettre a jour SshHardenedAlgorithms
//     (FIX-033) pour inclure le KEX hybride
//
// 4. Surveillance Tailscale :
//   - Tailscale envisage le support Rosenpass (PQ WireGuard)
//   - Quand disponible, activer dans TailscaleSecurityConfig
//     (FIX-038)
// =============================================================
