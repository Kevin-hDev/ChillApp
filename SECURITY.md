# Security Policy

## 🔒 Security Work Performed

Chill has undergone **extensive internal security validation** before public release.

### Security Audits Conducted

**Two successive internal audits + quality audit:**

1. **Architectural Context Audit** (Trail of Bits methodology - audit-context-building)
   - Ultra-granular mapping of all modules
   - Trust boundaries and attack surface analysis
   - Line-by-line analysis of critical functions

2. **Complete Security Audit** (Trail of Bits methodology - sharp-edges + audit-context-building)
   - **6 specialized agents** in parallel
   - **38 findings:** 4 Critical, 8 High, 14 Medium, 12 Low
   - **All corrected, mitigated, or documented**
   - **61 unit tests passing** after corrections

3. **Codebase Quality Audit**
   - 34 issues identified and fixed
   - 6 Critical, 14 Important, 14 Minor
   - Command injection vulnerabilities fixed
   - Code duplication removed
   - **42 tests passing** after corrections

### What This Means

- ✅ Professional security methodology applied (Trail of Bits protocol)
- ✅ All identified issues corrected or documented
- ✅ Command injection vulnerabilities eliminated
- ✅ 61 unit tests passing (security + functionality)

---

## 🛡️ Security Measures Implemented

### Secure Architecture

**Single Execution Point:**
All system commands go through a single centralized class (CommandRunner). This creates a central audit point and facilitates transversal protections:
- Default 120-second timeout
- Exception handling
- Argument separation (list, not concatenated string)

**Privilege Elevation:**
Secure and unique mechanism adapted to each OS:
- **Windows:** Temporary PowerShell script executed via Start-Process with RunAs verb, using -File parameter (no command interpretation)
- **Linux:** Temporary bash script executed via pkexec (polkit), arguments passed as separated list
- **macOS:** Temporary script executed via osascript with admin privileges, POSIX escaping protection

Temporary scripts:
- Created in unique directories with restrictive permissions (700)
- Systematically deleted after execution (finally block)

### Local Authentication

**PIN Code:**
- Minimum 8 digits (100 million combinations)
- Hashed with **PBKDF2-HMAC-SHA256** (100,000 iterations + 16-byte random salt)
- **Constant-time comparison** (XOR bit-by-bit) prevents timing attacks
- Never stored in plaintext

**Rate Limiting & Exponential Backoff:**
- 5 failed attempts → 30s lockout
- 10 attempts → 60s
- 15 attempts → 120s
- Capped at 300s
- Counter persists across restarts

**Automatic Migration:**
Transparent migration from old PIN formats (simple SHA-256) to current format (PBKDF2 + salt).

**UI Gate Lock:**
When PIN is active, entire app is replaced by lock screen until verification. No route accessible before PIN entry.

---

### Automated SSH Configuration

Secure automated SSH server setup per OS, grouping all admin operations in single elevated script. User enters admin password only once.

**Specific Protections:**
- Temporary scripts in unique directories (random names)
- Restrictive permissions (700 on directory and script)
- Semantic exit codes (10, 20, 30, 40) for precise failure diagnosis
- Post-installation verification (SSH service active check)
- Firewall rule creation only if no existing SSH rule

**Supported Systems:**
- **Windows:** OpenSSH installation via Windows Capabilities, service start and auto-start, firewall config
- **Linux:** Auto-detection of distro (Ubuntu, Debian, Fedora, Arch via ID_LIKE), installation via appropriate package manager, systemd service activation, firewall config
- **macOS:** Remote Login activation via system tools

---

### Automated Wake-on-LAN Configuration

Same secure model as SSH: single script with elevation, secure temp files, semantic exit codes.

**Specific Protections:**
- **Interface name validation:** Strict regex validation (alphanumeric, dashes, dots only, max 15 chars)
- **Adapter name escaping:** Windows adapter names escaped for PowerShell
- **systemd service:** On Linux, creates systemd service for WoL persistence after reboot

---

### Tailscale Integration

Communication with external Go daemon (chill-tailscale) via JSON protocol on stdin/stdout.

**Specific Protections:**
- **URL validation:** Auth URLs validated (HTTPS scheme only) before browser opening
- **Guard against concurrent calls:** Lock mechanism prevents simultaneous daemon relaunches
- **Clean shutdown:** Daemon stopped via dedicated JSON command, 3-second timeout before forced shutdown
- **Defensive JSON parsing:** Each daemon response parsed in try-catch, invalid peer data filtered silently
- **Binary verification:** Daemon binary permissions checked at startup
- **Generic error messages:** Network/system errors don't disclose technical details to user (details in debug logs, inactive in production)

---

### 🛡️ OS Security Tab

**New major security feature:** Integrated security hardening interface for the user's OS.

#### 1. Security Toggles (Enable/Disable Protections)

Quick on/off switches to activate OS protections without terminal.

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
- Secure network parameters (IP spoofing protection, redirects...)
- Disable unnecessary services (printing, network discovery...)
- Sensitive file permissions (/etc/shadow, /etc/ssh...)
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
- Gatekeeper (block unsigned apps)
- Automatic screen lock after sleep

#### 2. System Checkup (Single Button)

Complete read-only scan analyzing PC security state with score out of 12.

**What's checked (12 points):**
1. Active firewall
2. Pending updates
3. Disk encryption (BitLocker/LUKS/FileVault)
4. Antivirus/signatures (Defender/rkhunter/XProtect)
5. Quick malware scan
6. Startup programs
7. Suspicious scheduled tasks
8. Active network connections
9. Failed connection attempts
10. User accounts
11. Disk space
12. OS-specific parameters (SMBv1/network params/Gatekeeper)

**Result:** Score out of 12 + personalized recommendations (✅ OK, ⚠️ Check, ❌ Issue detected)

**Privacy:** Everything is local, nothing sent over network. 🔒

---

### Command Injection Protection

Audit identified and fixed several injection vectors:

- **Windows elevation:** Replaced PowerShell nesting with temporary scripts executed via -File
- **macOS elevation:** Replaced osascript interpolation with temporary scripts + POSIX escaping
- **Network interface names:** Centralized strict regex validation in all functions
- **Windows adapter names:** Apostrophe escaping for PowerShell
- **WoL PowerShell commands:** PowerShell single quotes for interpolated values

---

### Information Leak Protection

- **Error messages:** User-facing messages are generic. Technical details (stderr, stack traces) redirected to debug logs (inactive in production)
- **Clipboard:** Copied content (IP addresses, network info) automatically cleared after 30 seconds
- **Production logs:** All debug calls conditional on debug mode. No sensitive info (paths, IPs, identifiers) in production logs
- **Silent catches:** All empty catch blocks replaced with informative debug logs (6 blocks fixed)

---

### Process Management

**Command Timeouts:**
All system commands subject to 120-second default timeout (configurable per command).

**Tailscale Daemon Management:**
Single daemon process allowed at a time. Relaunch mechanism kills old process and waits for termination before launching new one.

**Race Conditions:**
Several race conditions identified and fixed:
- Tailscale daemon relaunch protected by guard against concurrent calls
- Daemon stop and restart sequenced correctly
- stdout/stderr stream subscriptions stored and cancelled properly

---

## ⚠️ Known Limitations (Documented and Accepted)

| Limitation | Explanation | Impact |
|------------|-------------|--------|
| **Admin password in temp scripts** | Temporary scripts may contain sensitive commands, though deleted immediately after execution. | **Low.** Scripts created with 700 permissions in unique directories, deleted in finally block. |
| **PIN in SharedPreferences** | PIN hash and salt in SharedPreferences (accessible without admin but protected by PBKDF2). | **Mitigated.** Offline brute force impractical with 100,000 PBKDF2 iterations. |
| **OS security toggles require admin** | Activating OS protections requires admin/sudo password. | **Acceptable.** System-level changes inherently require elevation. |

---

## 🚨 Reporting a Vulnerability

**We take security seriously, but please understand our limits as a volunteer project.**

### Responsible Disclosure Procedure

**If you discover a security vulnerability:**

1. **🚫 DO NOT open a public GitHub issue**
   - This would immediately endanger all users
   - Attackers could exploit the flaw before a fix

2. **📧 Send a private email to:**
   - **Chill_app@outlook.fr**
   - Subject: `[SECURITY] Vulnerability in Chill`

3. **📋 Include in your email:**
   - **Description:** Nature of the vulnerability
   - **Reproduction:** Detailed steps to reproduce (PoC)
   - **Impact:** Severity and potential consequences (CVSS score if possible)
   - **Proof of concept:** Code or demonstration (if applicable)
   - **Environment:** Affected versions (Chill version, OS version)
   - **Suggestions:** Proposed fix (optional but appreciated)
   - **Credit:** How you wish to be credited (see below)

### Timelines and Expectations

**What you can expect:**
- ⏱️ **Acknowledgment:** 48-72 hours (best effort)
- 🔍 **Initial analysis:** 2-6 days
- 🛠️ **Fix:** Depending on severity and complexity
  - **Critical:** 1-2 days
  - **High:** 3-4 days
  - **Medium/Low:** 1 week
- 📢 **Public disclosure:** Coordinated with you after fix

**What you CANNOT expect:**
- 💰 **Bug bounty:** No budget (free open source project)
- ⚡ **Guaranteed SLAs:** Volunteer project, no contractual deadlines
- 👔 **Professional support:** Limited security team (1 person)

### Credit and Public Recognition

**What is "credit"?**

If you find a vulnerability and report it responsibly, we will thank you publicly (if you wish).

**Options:**

**Option 1: Public Recognition** (default)
- ✅ Your name/pseudonym mentioned in:
  - SECURITY.md (Hall of Fame)
  - CHANGELOG.md
  - Release notes of the fix
  - Potentially on social media
- ✅ Good for your professional reputation
- ✅ Can be added to your CV/LinkedIn

**Option 2: Anonymous**
- ✅ Vulnerability fixed without public mention of who found it
- ✅ Your identity remains private

**Choose your preferred option in your email.**

### Coordinated Disclosure

We follow **coordinated disclosure**:

1. You report the vulnerability to us privately
2. We work on a fix
3. We keep you updated on progress
4. Once fix is deployed and users notified
5. We publish vulnerability details (CVE if applicable)
6. You are publicly credited (if desired)

**Standard timeline:** 90 days maximum between discovery and public disclosure (following Google Project Zero practices).

---

## 🏆 Hall of Fame - Security Researchers

These people helped secure Chill by responsibly reporting vulnerabilities:

*(No contributions yet - be the first!)*

**Format:**
- **Name/Pseudonym** - Vulnerability description - Severity (Critical/High/Medium/Low) - Date - CVE (if applicable)

**Example:**
- **John Doe** - Command injection in SSH setup - High - 2026-03-15 - CVE-2026-12345

---

## 📚 Security Resources

### SSH Security:
- [Official OpenSSH Guide](https://www.openssh.com/security.html)
- [SSH Hardening Guide](https://www.ssh.com/academy/ssh/security)
- [NIST Guide to SSH](https://nvlpubs.nist.gov/nistpubs/ir/2015/NIST.IR.7966.pdf)

### Tailscale Security:
- [Tailscale Security Model](https://tailscale.com/security)
- [Tailscale ACL Guide](https://tailscale.com/kb/1018/acls/)
- [Tailscale Encryption](https://tailscale.com/blog/how-tailscale-works/)

### Desktop Security:
- [OWASP Desktop App Security](https://owasp.org/www-project-desktop-app-security-top-10/)
- [Windows Security Baselines](https://docs.microsoft.com/en-us/windows/security/threat-protection/windows-security-baselines)
- [Linux Hardening Guide](https://www.cisecurity.org/benchmark/distribution_independent_linux)
- [macOS Security Guide](https://support.apple.com/guide/security/welcome/web)

### Flutter/Dart Security:
- [Flutter Security Best Practices](https://flutter.dev/docs/deployment/security)
- [Dart Security](https://dart.dev/guides/security)

---

**Last updated:** February 2026  
**Policy version:** 1.0
