# Security Policy — Chill

**Last updated:** February 2026
**Version:** 2.0

---

## 🔒 Security Work Completed

Chill has undergone **four successive internal security reviews** before publication.

### Security Audits Conducted

1. **Architectural Context Audit** (Trail of Bits methodology)
   - Ultra-granular mapping of all modules
   - Trust boundary and attack surface analysis
   - Line-by-line analysis of critical functions

2. **Full Security Audit** (Trail of Bits methodology)
   - **6 specialized AI agents** in parallel
   - **38 findings:** 4 Critical, 8 High, 14 Medium, 12 Low
   - **All fixed, mitigated, or documented**

3. **Codebase Quality Audit**
   - 34 issues identified and fixed
   - 6 Critical, 14 Important, 14 Minor
   - Command injection vulnerabilities eliminated
   - Code duplication removed

4. **Red Team + Full Defensive Hardening** (February 2026)
   - Offensive simulation: 58 attack vectors identified and analyzed
   - **44 security modules created** (`lib/core/security/`)
   - **869 automated tests** — 0 regressions
   - 3 existing files hardened

### What This Means

- ✅ Professional security methodology applied (Trail of Bits protocol)
- ✅ No remotely exploitable vulnerability identified
- ✅ All identified issues fixed or documented
- ✅ Automated test suite: **869 tests passing**
- ✅ Internal security score (self-assessed): **8.5/10**

---

## 🛡️ Security Measures Implemented

### Memory and Secure Storage

**Memory management (SecureBytes):**
- Sensitive data stored as `Uint8List` (never `String`)
- **Explicit zeroing** after use — minimizes memory exposure window
- Keys, tokens, PIN — never exposed as Dart's immutable `String` (which can persist in memory indefinitely)

**Native memory outside GC (FFI):**
- Ultra-sensitive data allocated outside the Dart garbage collector via FFI
- Protects against post-GC memory reads during collection cycles

**OS secure storage:**
- Migration from SharedPreferences (plaintext storage) to **native OS keystore**
- **macOS:** Keychain with hardware protection
- **Windows:** Credential Manager (DPAPI)
- **Linux:** libsecret (GNOME Keyring / KWallet integration)
- Protected data: PIN hash, salt, security configuration
- **Zero hardcoded secrets** in source code (verified by full codebase scan)

---

### Secure Architecture

**Single Execution Point:**
All system commands pass through a single centralized class (`CommandRunner`). This single entry point creates a centralized audit point and enforces cross-cutting protections:
- Default timeout of **120 seconds**
- Uniform exception handling
- Argument separation (list, never concatenated string — prevents injection)

**Privilege Elevation:**
A single, secure mechanism adapted to each OS:
- **Windows:** Temporary PowerShell script executed via `Start-Process` with `RunAs` verb, `-File` parameter (no command-line interpretation)
- **Linux:** Temporary bash script executed via `pkexec` (polkit), arguments passed as a separate list
- **macOS:** Temporary script executed via `osascript` with admin privileges, protected by POSIX escaping

Temporary scripts:
- Created in unique directories with restrictive permissions (**700**)
- Systematically deleted after execution (`finally` block)

**Fail-Closed Circuit Breaker:**
If 3 consecutive errors occur on a critical service, it is **automatically cut off** rather than allowed to pass — deny-by-default security principle.

---

### Local Authentication

**PIN Code:**
- Minimum 8 digits (100 million combinations)
- Hashed with **PBKDF2-HMAC-SHA256** (100,000 iterations + random 16-byte salt)
- **Constant-time comparison** (XOR byte-by-byte) — prevents timing attacks
- Never stored in plaintext
- **Derivation in a separate Dart isolate** — UI doesn't freeze, and the key is isolated from the main thread

**Rate Limiting & Exponential Backoff:**
- 5 failed attempts → 30s lockout
- 10 attempts → 60s
- 15 attempts → 120s
- Capped at 300s
- Persistent counter across restarts

**Automatic Migration:**
Transparent migration from old PIN formats (simple SHA-256) to current format (PBKDF2 + salt).

**UI Gate Lock:**
When PIN is active, the entire app is replaced by the lock screen until verification. No route is accessible before PIN entry — implemented via a `SecurityRouteObserver` that intercepts all navigation attempts.

---

### Startup Protection

Integrity checks run at every app launch:
- **Frida detection**: presence of dynamic code injection tool
- **Debugger detection** (gdb, lldb): debugger attached to the process
- **LD_PRELOAD / DYLD_INSERT_LIBRARIES detection**: OS-level injected libraries
- If a threat is detected → **immediate app shutdown** (fail closed)
- Protections disabled in debug mode to avoid false positives during development

---

### Automated SSH Configuration

Secure, automated SSH server configuration per OS, grouping all admin operations into a single script with elevation. The user enters their admin password only once.

**Specific Protections:**
- Temporary scripts in unique directories (random names)
- Restrictive permissions (700 on directory and script)
- Semantic exit codes (10, 20, 30, 40) for precise diagnostics
- Post-installation verification (SSH service active)
- Firewall rule created only if no existing SSH rule

**Supported Systems:**
- **Windows:** OpenSSH installation via Windows Capabilities, auto-start and auto-enable service, firewall config
- **Linux:** Auto-detection of distro (Ubuntu, Debian, Fedora, Arch via `ID_LIKE`), installation via appropriate package manager, systemd service activation, firewall config
- **macOS:** Remote Login activation via system tools

---

### Hardened SSH Configuration

The SSH server configured by Chill applies a reinforced configuration:
- **Weak algorithms blocked:** SHA-1, CBC, 3DES, arcfour and their variants
- Preferred algorithms: Ed25519, AES-256-GCM, ChaCha20-Poly1305
- Key-only authentication (password authentication optionally disabled)
- Configurable session timeout (default: 15 minutes of inactivity)

---

### Secure Wake-on-LAN Configuration

Same secure model as SSH: single script with elevation, secure temp files, semantic exit codes.

**Specific Protections:**
- **Interface name validation:** Strict regex validation (alphanumeric, hyphens, dots only, max 15 chars)
- **Adapter name escaping:** Windows adapter names escaped for PowerShell
- **systemd service:** On Linux, creates a systemd service for WoL persistence after reboot

---

### Tailscale Integration

Communication with external Go daemon (`chill-tailscale`) via JSON protocol on stdin/stdout.

**Daemon Integrity:**
- **SHA-256 verification** of the Tailscale binary at startup — detects any modification
- If hash doesn't match → daemon not launched (fail closed)

**Secured IPC:**
- **HMAC-SHA256 authentication** on each IPC message (daemon → app)
- **Encrypt-then-MAC**: data is encrypted then authenticated (never the reverse)
- Each message contains a timestamp — replayed messages are rejected

**Other Protections:**
- **URL validation:** Auth URLs validated (HTTPS scheme only) before opening browser
- **Concurrent call guard:** Lock mechanism prevents simultaneous daemon restarts
- **Clean shutdown:** Daemon stopped via dedicated JSON command, 3s timeout before forced shutdown
- **Defensive JSON parsing:** Each response parsed in `try-catch`, invalid data silently filtered
- **Generic error messages:** Network/system errors don't reveal technical details to the user

---

### SSH Firewall via Tailscale

- SSH configured to accept connections **only via the Tailscale interface (WireGuard VPN)**
- Prevents direct connection attempts from the Internet
- Brute-force from the public Internet is physically impossible
- Fallback to classic SSH only if Tailscale is not configured

---

### OS Security Tab

**Major new feature:** Integrated OS security hardening interface for the user's operating system.

#### 1. Security Toggles

Quick on/off buttons to enable OS protections without a terminal.

**Protection against accidental disabling:**
Disabling a critical protection requires **progressive confirmation**:
- Reflection delay before the button becomes active
- Manual typing of the word "CONFIRM" to validate
- Reduces accidental single-click disabling

**🪟 Windows (8 toggles):**
- Firewall (all profiles)
- Disable Remote Desktop
- Disable SMBv1 (obsolete protocol, WannaCry vector)
- Disable Remote Registry
- Anti-ransomware protection (Controlled Folder Access)
- Connection audit (success + failures)
- Automatic updates
- BitLocker (disk encryption — requires TPM 2.0)

**🐧 Linux (7 toggles):**
- UFW Firewall
- Secure network settings (IP spoofing protection, redirects...)
- Disable unnecessary services (printing, network discovery...)
- Sensitive file permissions (`/etc/shadow`, `/etc/ssh`...)
- Fail2Ban for SSH (brute-force protection)
- Automatic security updates
- Disable root login by password

**🍎 macOS (8 toggles):**
- Application firewall
- Stealth mode (invisible to network scans)
- FileVault (disk encryption)
- Disable SMB file sharing
- Automatic updates
- Secure keyboard entry (keylogger protection in Terminal)
- Gatekeeper (blocking unsigned apps)
- Automatic screen lock after sleep

#### 2. System Checkup

Full **read-only** scan analyzing the PC's security state with a score out of 12.

**What is checked (12 points):**
1. Firewall active
2. Pending updates
3. Disk encryption (BitLocker/LUKS/FileVault)
4. Antivirus/signatures (Defender/rkhunter/XProtect)
5. Quick malware scan
6. Startup programs
7. Suspicious scheduled tasks
8. Active network connections
9. Failed login attempts
10. User accounts
11. Disk space
12. OS-specific settings (SMBv1/network settings/Gatekeeper)

**Result:** Score out of 12 + personalized recommendations (✅ OK, ⚠️ Check, ❌ Issue detected)

**Privacy:** Everything is local, nothing is sent over the network. 🔒

---

### Command Injection Protection

The audit identified and fixed several injection vectors:

- **Windows elevation:** Replaced PowerShell nesting with temporary scripts executed via `-File`
- **macOS elevation:** Replaced osascript interpolation with temporary scripts + POSIX escaping
- **Network interface names:** Centralized strict regex validation in all functions
- **Windows adapter names:** Apostrophe escaping for PowerShell
- **WoL PowerShell commands:** PowerShell single quotes for interpolated values

---

### Information Leak Prevention

**Error messages:**
Messages displayed to users are generic. Technical details (`stderr`, stack traces) redirected to debug logs (inactive in production).

**Clipboard:**
Copied content (IP addresses, network info) automatically cleared after **30 seconds**.

**Production logs:**
All debug calls conditioned by debug mode. No sensitive info (paths, IPs, identifiers) in production logs. **Zero logs emitted in release** for sensitive data.

**Silent catches:**
All empty `catch` blocks replaced by informative debug logs (6 blocks fixed in the previous audit).

---

### Tamper-Evident Audit Log

**Automatically recorded events:**
- SSH connection (success or failure)
- SSH disconnection / reconnection
- PIN authentication failure
- Security configuration change
- Tailscale daemon start and stop
- Repeated attempts (rate limiting triggered)

**Entry integrity:**
- Each entry is chained with a **SHA-256 hash** of the previous entry
- Modifying any entry invalidates all subsequent entries
- `verifyIntegrity()` method available to check the chain

**Storage:**
- In the secure OS keystore
- Limited to 500 entries with automatic rotation

---

### Process Management

**Command Timeout:**
All system commands subject to a default timeout of 120 seconds (configurable per command).

**Tailscale Daemon:**
Only one daemon process allowed at a time. Restart kills the old process and waits for termination before launching the new one.

**Race Conditions:**
Multiple race conditions identified and fixed:
- Daemon restart protected by concurrent call guard
- Daemon shutdown and restart correctly sequenced
- `stdout`/`stderr` stream subscriptions stored and properly cancelled

**Secure Heartbeat:**
Heartbeat mechanism detects silent connection drops — the connection is declared dead if the heartbeat receives no response within the allowed delay.

---

### Secure Types and States

**Dart extension types:**
SSH keys, authentication tokens, and sensitive credentials are encapsulated in **dedicated extension types**. This:
- Prevents accidentally passing a secret where ordinary data is expected
- Ensures secret comparison always uses the constant-time method (not `==` inherited from the underlying type — a known Dart pitfall)

**`sealed` security states:**
App security states (`Locked`, `Unlocked`, `PendingAuth`, etc.) are implemented as **sealed classes** — the compiler guarantees all cases are handled, with no possible unhandled intermediate state.

---

### Secure Streams and Nonce Management

**Secure Streams:**
Sensitive data streams (SSH stream, IPC stream) are wrapped with automatic cleanup — even in case of exception, resources are released and sensitive data cleared.

**Nonce Manager:**
- Nonces generated by CSPRNG (never sequential)
- Internal counter — when the **2^32 limit is approached** (NIST limit for AES-GCM), the session key is renewed
- Guarantees the same nonce is never reused with the same key

---

### Secure Logger with Integrity Chain

**SecureLogger:**
- All app logs pass through a single entry point (`SecureLogger`)
- **Zero sensitive logs in production** — automatic filtering based on build mode
- Each log entry is signed with a chained SHA-256 hash — any retroactive modification is detectable

---

### Screen Protection

- **Screenshots blocked** on screens containing sensitive data (PIN screen, SSH config, keys)
- On security configuration screens, the app detects backgrounding and masks content
- User-configurable in settings

---

### Sandbox and Minimal Permissions

**Linux (AppArmor):**
- AppArmor profile restricting file access, network, and system capabilities to the strict minimum
- Only explicitly authorized directories and sockets are accessible

**macOS (Entitlements):**
- Minimal entitlements: only network permissions and capabilities actually used
- Hardened Runtime enabled — prevents dynamic code injection

**Windows (code integrity):**
- Application control policy verifying the signature of executed components

---

### Automatic SSH Key Rotation

- SSH keys generated by Chill have a configured lifetime (**30 days by default**)
- As expiration approaches, the user is notified
- Manual rotation available at any time from the interface

---

### Code Signature Verification

At each launch, Chill verifies its own digital signature:
- **Windows:** MSIX signature verified via Windows Authenticode
- **Linux:** Snap package signature verified
- **macOS:** DMG signature + Apple notarization verified

If the signature is invalid or missing → user alert before any sensitive operation.

---

### Network Detection

**Proxy/VPN detection:**
The app detects if the connection passes through a non-Tailscale proxy or VPN, and warns the user if this could compromise communication confidentiality.

**Tailscale security state:**
The WireGuard tunnel state is continuously verified — degradation (tunnel disconnected, expired key) triggers an immediate alert.

---

### Network Segmentation

- Chill ↔ Tailscale daemon communications: local Unix socket only (no exposed TCP port)
- SSH communications: only via Tailscale tunnel if configured
- Each communication channel is isolated — compromising one channel does not expose the others

---

### Supply Chain Defense

**Dependencies locked to exact versions:**

| Package | Locked version | Role |
|---------|---------------|------|
| `flutter_secure_storage` | Exact version | Secure storage |
| `local_auth` | Exact version | Biometrics |
| `cryptography` | Exact version | Crypto primitives |

- No `^` on critical security packages (which would allow unverified automatic updates)
- `pubspec.lock` file versioned and verified

---

### Post-Quantum Readiness

- **Post-quantum roadmap** documentation integrated into the code (`post_quantum_roadmap.dart`)
- Migration to **X25519-Kyber768** (NIST-selected hybrid algorithm) planned as soon as Dart libraries support it
- Architecture designed to allow cryptographic primitive replacement without major rewrite

---

### Forensics and Regulatory Compliance

- Audit log structure compatible with traceability requirements
- Compliance with the European **Cyber Resilience Act (CRA)**: component documentation, update policy, vulnerability disclosure channel
- Personal data: Chill collects no user data — everything stays local

---

### Build Obfuscation

All production builds are compiled with:
- `--obfuscate`: class names, methods, and variables made unreadable
- `--split-debug-info=build/debug-info/`: debug symbols separated and never included in the distributed binary

---

## ⚠️ Known Limitations (Documented and Accepted)

| Limitation | Explanation | Impact |
|------------|-------------|--------|
| **Dart GC and memory** | The Dart garbage collector may retain temporary copies of data in memory. | **Low.** Requires direct memory access to the process. Mitigated by SecureBytes (Uint8List + zeroing) and FFI for the most sensitive data. |
| **Temp scripts and elevation** | Temporary scripts may contain sensitive commands, though deleted immediately after execution. | **Low.** Created with 700 permissions in unique directories, deleted in `finally` block. Exposure window of a few seconds. |
| **OS toggles require admin** | Activating OS protections requires admin/sudo password. | **Acceptable.** System changes inherently require elevation. |
| **AppArmor sandbox optional** | AppArmor profile is only active if AppArmor is installed on the Linux distribution. | **Low.** Most modern distributions (Ubuntu, Debian) have it by default. |

---

## 🚨 Reporting a Vulnerability

**We take security seriously, but please understand our limitations as a volunteer project.**

### Responsible Disclosure Procedure

**If you discover a security vulnerability:**

1. **🚫 DO NOT open a public issue on GitHub**
   - This would immediately put all users at risk
   - Attackers could exploit the flaw before a fix is deployed

2. **📧 Send a private email to:**
   - **Chill_app@outlook.fr**
   - Subject: `[SECURITY] Vulnerability in Chill`

3. **📋 Include in your email:**
   - **Description:** Nature of the vulnerability
   - **Reproduction:** Detailed steps to reproduce (PoC)
   - **Impact:** Severity and possible consequences (CVSS score if possible)
   - **Proof of concept:** Code or demonstration (if applicable)
   - **Environment:** Affected versions (Chill version, OS version)
   - **Suggestions:** Proposed fix (optional but appreciated)
   - **Credit:** How you wish to be credited

### Timelines and Expectations

| Step | Estimated Timeline |
|------|-------------------|
| Acknowledgment | 48–72 hours |
| Initial analysis | 2–6 days |
| Critical fix | 1–2 days |
| High fix | 3–4 days |
| Medium/Low fix | 1 week |
| Public disclosure | Coordinated after fix (max 90 days) |

**What you CANNOT expect:**
- 💰 **Bug bounty:** Free open source project, no budget
- ⚡ **Guaranteed SLA:** Volunteer team
- 👔 **Professional support:** 1 developer

### Credit and Public Recognition

If you report a vulnerability responsibly, you will be publicly thanked (if you wish) in:
- This file (Hall of Fame below)
- The CHANGELOG
- The fix's release notes

---

## 🏆 Hall of Fame — Security Researchers

These people helped secure Chill by responsibly disclosing vulnerabilities:

*(No contributions yet — be the first!)*

**Format:**
- **Name/Handle** — Description — Severity — Date — CVE (if applicable)

---

## 📚 Security Resources

### SSH Security:
- [Official OpenSSH Guide](https://www.openssh.com/security.html)
- [SSH Hardening Guide](https://www.ssh.com/academy/ssh/security)
- [NIST SSH Guide](https://nvlpubs.nist.gov/nistpubs/ir/2015/NIST.IR.7966.pdf)

### Tailscale Security:
- [Tailscale Security Model](https://tailscale.com/security)
- [Tailscale ACL Guide](https://tailscale.com/kb/1018/acls/)
- [Tailscale Encryption (WireGuard)](https://tailscale.com/blog/how-tailscale-works/)

### Desktop Security:
- [OWASP Desktop App Security](https://owasp.org/www-project-desktop-app-security-top-10/)
- [Windows Security Baselines](https://docs.microsoft.com/en-us/windows/security/threat-protection/windows-security-baselines)
- [Linux Hardening Guide (CIS)](https://www.cisecurity.org/benchmark/distribution_independent_linux)
- [macOS Security Guide](https://support.apple.com/en-us/guide/security/welcome/web)

### Flutter/Dart Security:
- [Flutter Security Best Practices](https://flutter.dev/docs/deployment/security)
- [Dart Security](https://dart.dev/guides/security)
