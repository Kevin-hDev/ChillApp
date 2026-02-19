# Sprint 3 Security Modules — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implémenter deux modules de sécurité (Kill Switch + Watchdog, AI Detection + Behavioral Analysis) pour ChillApp Sprint 3.

**Architecture:** Chaque module est un fichier Dart autonome dans `lib/core/security/`. Les tests utilisent `flutter_test` avec des sous-classes testables pour éviter les vraies commandes OS. Pattern TDD strict.

**Tech Stack:** Flutter 3.38.7, Dart 3.10.7, flutter_test, dart:io, dart:async, dart:collection, dart:math

---

### Task 1: Créer `lib/core/security/kill_switch.dart`

**Files:**
- Create: `lib/core/security/kill_switch.dart`

**Step 1: Écrire le fichier source**

Contenu exact fourni dans le brief de la tâche.

**Step 2: Analyser**

Run: `dart analyze lib/core/security/kill_switch.dart`
Expected: No issues found

---

### Task 2: Créer `test/unit/security/test_kill_switch.dart`

**Files:**
- Create: `test/unit/security/test_kill_switch.dart`

**Step 1: Écrire les 12 tests**

Couvre: KillReason enum, KillSwitchResult, execute PIN flow, skipConfirmation, onTrigger callback, TestableKillSwitch override, KillSwitchWatchdog lifecycle, heartbeat, stop, trigger, no-trigger-before-timeout.

**Step 2: Lancer les tests**

Run: `flutter test test/unit/security/test_kill_switch.dart`
Expected: 12 tests passing

---

### Task 3: Créer `lib/core/security/ai_detection.dart`

**Files:**
- Create: `lib/core/security/ai_detection.dart`

**Step 1: Écrire le fichier source**

Contenu exact fourni dans le brief.

**Step 2: Analyser**

Run: `dart analyze lib/core/security/ai_detection.dart`
Expected: No issues found

---

### Task 4: Créer `test/unit/security/test_ai_detection.dart`

**Files:**
- Create: `test/unit/security/test_ai_detection.dart`

**Step 1: Écrire les 16 tests**

Couvre: AIRateLimiter (7 tests), BehavioralAnalyzer (9 tests).

**Step 2: Lancer les tests**

Run: `flutter test test/unit/security/test_ai_detection.dart`
Expected: 16 tests passing

---

### Task 5: Validation finale

Run: `dart analyze lib/core/security/kill_switch.dart lib/core/security/ai_detection.dart`
Run: `flutter test test/unit/security/test_kill_switch.dart test/unit/security/test_ai_detection.dart`
Expected: 0 erreurs, tous les tests verts
