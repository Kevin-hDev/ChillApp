# ⚠️ READ THIS FIRST

**Before installing or using Chill Desktop Application**

---

## 🔴 Critical Security Information

### This Application Requires Administrator Privileges

Chill needs elevated permissions (admin/sudo/root) to configure system-level security settings:
- Firewall configuration
- SSH server installation and management
- Wake-on-LAN network interface configuration
- System security hardening (OS Security Tab)
- Disk encryption management (BitLocker/LUKS/FileVault)

**⚠️ Never grant administrator access to software you don't trust.**

---

## 🛡️ What We've Done to Earn Your Trust

### Professional Security Audits

**Two successive internal audits + quality audit:**
- Complete architectural mapping (Trail of Bits methodology)
- **38 security findings** (4 Critical, 8 High, 14 Medium, 12 Low)
- **All issues corrected or documented**
- **61 unit tests passing** after corrections
- Command injection vulnerabilities eliminated
- Information leak protections implemented

**Details:** See [SECURITY.md](SECURITY.md) for complete audit report.

### Open Source & Auditable

- **License:** GNU General Public License v3.0 (GPL v3)
- **Source code:** Publicly available on GitHub (after release)
- **No telemetry:** Everything stays on your machine 🔒
- **No hidden features:** What you see is what you get
- **Community auditable:** Anyone can review the code

---

## 📋 System Requirements

### Supported Operating Systems

| OS | Version | Notes |
|----|---------|-------|
| **Windows** | 10/11 | PowerShell 5.1+ required |
| **Linux** | Ubuntu 20.04+, Debian 11+, Fedora 35+, Arch | systemd required |
| **macOS** | 11+ (Big Sur and later) | Rosetta 2 for Apple Silicon |

### Required Permissions

- **Administrator/sudo access** for system configuration
- **Network access** for SSH connections
- **Disk access** for SSH key storage

---

## ⚙️ What This Application Does

### Core Features

1. **SSH Configuration Assistant**
   - Automated SSH server installation per OS
   - Key generation and management (Ed25519 preferred)
   - Secure key storage with encryption
   - Host key verification (TOFU - Trust On First Use)

2. **Wake-on-LAN Configuration**
   - Network interface detection
   - MAC address configuration
   - WoL packet testing
   - Linked to SSH connections for seamless wake-up

3. **Tailscale Integration**
   - VPN mesh network setup
   - Secure peer-to-peer connections
   - External Go daemon (chill-tailscale) communication
   - URL validation and auth flow

4. **OS Security Tab** 🆕
   - **Security Toggles:** One-click enable/disable OS protections
     - Windows: Firewall, Anti-ransomware, BitLocker, Disable Remote Desktop, etc.
     - Linux: UFW, Fail2Ban, Secure network params, File permissions, etc.
     - macOS: Firewall, FileVault, Gatekeeper, Stealth mode, etc.
   - **System Checkup:** 12-point security scan with score and recommendations
     - Firewall status, pending updates, disk encryption, antivirus, malware scan, etc.
   - **100% Local:** No data sent over network

### Companion Application

**Chill works together with ChillShell (mobile app):**
- ChillShell (Android/iOS): Remote SSH terminal client
- Chill (Desktop): PC configuration assistant
- Together: Complete secure remote access system

---

## 🚨 Known Limitations (Accepted Trade-offs)

| Limitation | Impact | Mitigation |
|------------|--------|------------|
| **Admin password in temp scripts** | Elevated scripts may contain sensitive commands | 🟢 Low. Scripts have 700 permissions, deleted immediately in finally block |
| **PIN in SharedPreferences** | PIN hash accessible without admin (protected by PBKDF2) | 🟡 Mitigated. 100,000 PBKDF2 iterations make offline brute force impractical |
| **OS security toggles require admin** | System-level changes need elevation | ✅ Acceptable. Inherent to system modifications |

**Full details:** [SECURITY.md - Known Limitations](SECURITY.md#️-known-limitations-documented-and-accepted)

---

## 📜 License: GPL v3 (Copyleft)

**What this means for you:**

✅ **You CAN:**
- Use Chill for free (personal or commercial)
- Study and modify the source code
- Redistribute modified versions

⚠️ **You MUST:**
- Keep it free and open source (GPL v3)
- Provide source code if you distribute modifications
- Credit original authors

❌ **You CANNOT:**
- Close the source code
- Use a proprietary license
- Remove copyright notices

**Why GPL v3?** We want Chill to remain free and open forever. Anyone can use it, but nobody can turn it into closed-source commercial software.

**Full license:** [LICENSE](LICENSE)

---

## 🔐 Security Contact

**Found a vulnerability?**

🚫 **DO NOT open a public GitHub issue** (endangers all users)

📧 **Email privately:** Chill_app@outlook.fr
Subject: `[SECURITY] Vulnerability in Chill`

**Coordinated disclosure:** 90-day timeline, credit in Hall of Fame (optional)

**Details:** [SECURITY.md - Reporting a Vulnerability](SECURITY.md#-reporting-a-vulnerability)

---

## 📚 Documentation

Before using Chill:
1. **Start here:** ⚠️_READ_THIS_FIRST.md (you are here)
2. **Security details:** [SECURITY.md](SECURITY.md)
3. **Contributing:** [CONTRIBUTING.md](CONTRIBUTING.md)
4. **Version history:** [CHANGELOG.md](CHANGELOG.md)
5. **Roadmap:** [ROADMAP.md](ROADMAP.md)

---

## ✅ Ready to Install?

If you understand and accept:
- The need for administrator privileges
- The known limitations and trade-offs
- The GPL v3 license terms
- The security considerations

**Then proceed with installation.**

Detailed setup instructions: [README.md](README.md)

---

## 🤝 Community

- **Issues:** GitHub Issues (for bugs and feature requests)
- **Security:** Chill_app@outlook.fr (private security reports only)
- **Contributions:** See [CONTRIBUTING.md](CONTRIBUTING.md)

---

**Last updated:** February 2026
**Chill version:** Check [CHANGELOG.md](CHANGELOG.md) for current version
