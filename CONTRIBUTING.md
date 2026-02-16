# Contributing to Chill Desktop

Thank you for considering contributing to **Chill Desktop**! 🎉

Whether you want to report a bug, suggest a feature, improve documentation, or submit code, your help is greatly appreciated.

---

## 🚨 Security Issues First

**Found a security vulnerability?**

🚫 **DO NOT open a public GitHub issue** — this immediately endangers all users.

📧 **Email privately:** Chill_app@outlook.fr
Subject: `[SECURITY] Vulnerability in Chill`

See [SECURITY.md](SECURITY.md) for the full responsible disclosure procedure.

---

## 📋 Before You Contribute

1. **Read ⚠️_READ_THIS_FIRST.md** — Understand Chill's security model and limitations
2. **Read SECURITY.md** — Familiarize yourself with security measures and audits
3. **Check existing issues** — Your idea/bug might already be tracked
4. **Read this guide** — Follow our conventions

---

## 🐛 Reporting Bugs

**Use GitHub Issues** for non-security bugs.

### Good Bug Report Template

```markdown
**Describe the bug**
Clear description of what went wrong.

**To Reproduce**
1. Go to '...'
2. Click on '...'
3. See error

**Expected behavior**
What you expected to happen.

**Environment:**
- Chill version: [e.g., 1.0.0]
- OS: [e.g., Windows 11, Ubuntu 22.04, macOS 14]
- OS version details: [e.g., kernel version, build number]

**Logs/Screenshots**
Attach error logs, screenshots, or terminal output.

**Additional context**
Any other relevant info.
```

### What Makes a Good Bug Report

- ✅ Clear title (e.g., "SSH setup fails at step 3 on Arch Linux")
- ✅ Reproducible steps
- ✅ Expected vs actual behavior
- ✅ Environment details (OS, Chill version)
- ✅ Error messages or logs
- ❌ Vague descriptions ("it doesn't work")
- ❌ Missing environment info

---

## 💡 Suggesting Features

**Use GitHub Issues** with the label `enhancement`.

### Good Feature Request Template

```markdown
**Feature description**
Clear description of the feature.

**Use case**
Why is this needed? What problem does it solve?

**Proposed solution**
How would it work?

**Alternatives considered**
Other approaches you thought about.

**Security implications**
Any security considerations? (Admin privileges needed? Network access?)

**Platform compatibility**
Does it work on Windows/Linux/macOS, or is it OS-specific?
```

### Feature Guidelines

- ✅ Aligns with Chill's mission (SSH/WoL/Tailscale/OS Security configuration)
- ✅ Works across platforms when possible (or clearly OS-specific)
- ✅ Security-conscious (no backdoors, no telemetry, local-first)
- ✅ Respects GPL v3 (keep it free and open)
- ❌ Adds telemetry or phoning-home
- ❌ Requires proprietary dependencies
- ❌ Unnecessarily complex for minimal benefit

---

## 🔧 Contributing Code

### 1. Fork & Clone

```bash
# Fork the repo on GitHub, then:
git clone https://github.com/YOUR_USERNAME/ChillApp.git
cd ChillApp
```

### 2. Create a Branch

```bash
git checkout -b feature/my-feature
# or
git checkout -b fix/issue-123
```

**Branch naming:**
- `feature/` — New features
- `fix/` — Bug fixes
- `docs/` — Documentation only
- `refactor/` — Code refactoring
- `test/` — Tests only
- `security/` — Security fixes

### 3. Set Up Your Environment

**Install Flutter (Desktop):**
```bash
# Flutter 3.27+ required
flutter --version

# Enable desktop support
flutter config --enable-windows-desktop  # Windows
flutter config --enable-linux-desktop    # Linux
flutter config --enable-macos-desktop    # macOS
```

**Install Dependencies:**
```bash
flutter pub get
```

**Build Tailscale Daemon (if modifying Tailscale integration):**
```bash
cd tailscale-daemon
./scripts/build-tailscale.sh  # macOS/Linux
# or
.\scripts\build-tailscale.bat  # Windows
```

**Run the App:**
```bash
flutter run -d windows  # Windows
flutter run -d linux    # Linux
flutter run -d macos    # macOS
```

### 4. Code Standards

**Architecture:**
- Follow feature-first structure: `lib/features/<feature>/`
- Use Riverpod for state management (`StateNotifierProvider`)
- Prefer immutable state (use `copyWith()`)
- Single responsibility: services for logic, providers for state, screens for UI

**Dart/Flutter:**
- Use `dart format lib/` before committing
- Run `flutter analyze` — must pass with 0 issues
- Follow [Effective Dart](https://dart.dev/guides/language/effective-dart)
- Use `const` constructors when possible
- Avoid `dynamic` — prefer explicit types

**Translations (i18n):**
- All user-facing text must use i18n keys
- Add keys to **both** `lib/i18n/app_en.arb` and `lib/i18n/app_fr.arb`
- Run `flutter gen-l10n` after modifying ARB files
- Never hardcode text in UI

**Security:**
- Never hardcode credentials, keys, or secrets
- Use `flutter_secure_storage` for sensitive data (if needed)
- Validate all user inputs
- Sanitize command arguments (prevent injection)
- Use single execution point (CommandRunner) for system commands
- Add security-related changes to PR checklist

**Tests:**
- Write tests for new features (unit tests required, widget tests encouraged)
- Run `flutter test` — all tests must pass
- Aim for meaningful coverage (not just numbers)

### 5. Commit Messages

Follow [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>(<scope>): <subject>

<body>

<footer>
```

**Types:**
- `feat:` — New feature
- `fix:` — Bug fix
- `docs:` — Documentation only
- `style:` — Code style (formatting, no logic change)
- `refactor:` — Code refactoring
- `test:` — Adding/fixing tests
- `chore:` — Maintenance (dependencies, build)
- `security:` — Security fix

**Examples:**
```bash
git commit -m "feat(wol): add MAC address validation"
git commit -m "fix(ssh): prevent command injection on Linux pkexec"
git commit -m "docs: update CONTRIBUTING.md with code standards"
git commit -m "security: upgrade dependency X to patch CVE-2026-1234"
```

**Include Co-Authored-By** if collaborating:
```
feat(dashboard): add Tailscale status badge

Co-Authored-By: Name <email@example.com>
```

### 6. Testing

**Run all checks before submitting:**

```bash
# Format code
dart format lib/

# Analyze code
flutter analyze

# Run tests
flutter test

# Generate i18n (if you modified ARB files)
flutter gen-l10n

# Build (verify no build errors)
flutter build windows  # or linux/macos
```

**All must pass:**
- ✅ `flutter analyze` — 0 issues
- ✅ `flutter test` — all tests pass
- ✅ Code formatted (`dart format`)
- ✅ No secrets/keys in code

### 7. Pull Request

**Before opening PR:**
- [ ] Code formatted (`dart format lib/`)
- [ ] `flutter analyze` passes (0 issues)
- [ ] `flutter test` passes (all tests)
- [ ] New features have tests
- [ ] i18n updated (FR + EN ARB files)
- [ ] CHANGELOG.md updated
- [ ] No secrets/keys in code
- [ ] **If security-related:** SECURITY.md updated if necessary
- [ ] Screenshots added (if UI changes)

**PR Title Format:**
```
<type>(<scope>): <description>
```

Examples:
- `feat(tailscale): add connection status indicator`
- `fix(ssh): resolve pkexec hang on Fedora`
- `docs: improve README installation section`

**PR Description Template:**
```markdown
## Description
What does this PR do?

## Type of Change
- [ ] 🐛 Bug fix (non-breaking)
- [ ] ✨ New feature (non-breaking)
- [ ] 💥 Breaking change
- [ ] 📝 Documentation
- [ ] 🔒 Security fix

## Testing
How did you test this? What OS/versions?

## Screenshots (if applicable)
Add screenshots here.

## Checklist
- [ ] Code formatted
- [ ] `flutter analyze` passes
- [ ] `flutter test` passes
- [ ] Tests added for new features
- [ ] i18n updated (FR + EN)
- [ ] CHANGELOG.md updated
- [ ] No secrets in code
- [ ] SECURITY.md updated (if security change)

## Security Impact
Any security implications?

## Notes for Reviewers
Anything reviewers should know?
```

---

## 🧪 Testing Guidelines

### Unit Tests

**Location:** `test/`

**Test file naming:** `*_test.dart`

**What to test:**
- State models (copyWith, equality)
- Providers (state changes)
- Services (business logic)
- Utilities (helpers, parsers)

**Example:**
```dart
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SshSetupState', () {
    test('initial state is waitingStart', () {
      final state = SshSetupState();
      expect(state.currentStep, SetupStep.waitingStart);
    });

    test('copyWith creates new instance with changes', () {
      final state = SshSetupState();
      final updated = state.copyWith(currentStep: SetupStep.inProgress);
      expect(updated.currentStep, SetupStep.inProgress);
      expect(state.currentStep, SetupStep.waitingStart); // unchanged
    });
  });
}
```

### Widget Tests

**Coming soon** — widget test guidelines will be added.

---

## 📖 Documentation

**What needs documentation:**
- New features (README.md + inline comments)
- Public APIs (dartdoc comments)
- Breaking changes (CHANGELOG.md + migration guide)
- Security changes (SECURITY.md)

**Documentation style:**
- Clear and concise
- Code examples when helpful
- Explain *why*, not just *what*
- Use proper Markdown formatting

---

## 🌍 Internationalization

**Supported languages:** FR (French), EN (English)

**Adding a translation:**

1. Add key to `lib/i18n/app_en.arb`:
```json
"myNewKey": "My new text in English"
```

2. Add same key to `lib/i18n/app_fr.arb`:
```json
"myNewKey": "Mon nouveau texte en français"
```

3. Generate localizations:
```bash
flutter gen-l10n
```

4. Use in code:
```dart
Text(context.l10n.myNewKey)
```

**Translation guidelines:**
- Keep FR and EN in sync (same keys)
- No empty values
- Use placeholders for dynamic text: `"Hello {name}"`
- Test both languages before submitting

---

## 🏗️ Project Structure

```
ChillApp/
├── lib/
│   ├── config/         # App configuration
│   ├── core/           # Core utilities, theme, i18n
│   │   ├── i18n/       # i18n extensions
│   │   └── theme/      # Design system (colors, typography, spacing)
│   ├── features/       # Feature modules
│   │   ├── dashboard/  # Main dashboard screen
│   │   ├── info/       # Connection info screen
│   │   ├── settings/   # Settings screen
│   │   ├── ssh/        # SSH configuration
│   │   ├── tailscale/  # Tailscale integration
│   │   └── wol/        # Wake-on-LAN configuration
│   ├── i18n/           # ARB translation files + generated code
│   ├── infrastructure/ # OS detection, command execution
│   ├── routing/        # go_router configuration
│   ├── shared/         # Shared widgets, utilities
│   └── main.dart       # App entry point
├── test/               # Unit tests
├── tailscale-daemon/   # Go daemon for Tailscale (tsnet)
├── CHANGELOG.md        # Version history
├── CONTRIBUTING.md     # This file
├── LICENSE             # GPL v3 license
├── README.md           # Project overview
├── SECURITY.md         # Security documentation
└── pubspec.yaml        # Dependencies
```

---

## 🤝 Code Review Process

1. **Submit PR** with complete description and checklist
2. **Automated checks** run (CI/CD when available)
3. **Maintainer review** (1-3 days for feedback)
4. **Address feedback** — make requested changes
5. **Approval** — PR is approved
6. **Merge** — Maintainer merges PR
7. **Thank you!** — You're credited in CHANGELOG.md

**Review criteria:**
- Code quality and style
- Tests pass and cover new code
- Security considerations addressed
- Documentation updated
- No breaking changes (or well-justified)
- Aligns with project goals

---

## 📜 License

By contributing, you agree that your contributions will be licensed under **GNU General Public License v3.0 (GPL v3)**.

This means:
- Your code remains free and open source
- Derivative works must also be GPL v3
- No proprietary forks allowed

See [LICENSE](LICENSE) for full text.

---

## 🎓 Learning Resources

**Flutter Desktop:**
- [Official Flutter Desktop Docs](https://docs.flutter.dev/platform-integration/desktop)
- [Desktop Best Practices](https://docs.flutter.dev/development/platform-integration/desktop)

**Riverpod (State Management):**
- [Riverpod Documentation](https://riverpod.dev/)
- [Riverpod Getting Started](https://riverpod.dev/docs/getting_started)

**Security:**
- [OWASP Desktop App Security](https://owasp.org/www-project-desktop-app-security-top-10/)
- [Flutter Security Best Practices](https://flutter.dev/docs/deployment/security)

**Chill-Specific:**
- [SSH Security Guide](https://www.openssh.com/security.html)
- [Tailscale Security Model](https://tailscale.com/security)

---

## ❓ Questions?

- **General questions:** Open a GitHub Discussion (when available) or Issue
- **Security questions:** Chill_app@outlook.fr (private)
- **Feature proposals:** Open an Issue with `enhancement` label

---

**Thank you for contributing to Chill Desktop!** 🚀

Your time and effort help make secure remote access available to everyone.
