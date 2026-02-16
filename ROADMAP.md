# Roadmap - Chill Desktop

**Vision:** Make secure remote access configuration effortless for everyone.

This roadmap outlines completed milestones and planned features for **Chill Desktop**, the PC configuration assistant for SSH, Wake-on-LAN, and Tailscale.

**Companion app:** Chill works together with [ChillShell](https://github.com/YOUR_ORG/ChillShell) (mobile SSH terminal).

---

## 📍 VERSION ACTUELLE

### **V1.0** — Initial Release ✅ (February 2026)

First stable release with core configuration features.

---

## 🎯 Released Versions

### **V1.0** — Foundation ✅ (February 2026)

**Status:** Released

**Highlights:**
- ✅ Automated SSH server configuration (Windows/Linux/macOS)
- ✅ Wake-on-LAN setup assistant (Windows/Linux)
- ✅ Native Tailscale integration (tsnet Go daemon)
- ✅ Connection info screen (IP, MAC, username auto-detection)
- ✅ PIN lock protection (8-digit, SHA-256 hashed)
- ✅ Dark/Light theme support
- ✅ FR/EN internationalization
- ✅ Responsive desktop UI (800x600 minimum)

**Technical:**
- Flutter 3.27+ (Windows/Linux/macOS)
- Riverpod 3.2.1 state management
- go_router navigation
- Custom Go daemon for Tailscale
- 97 unit tests

**Documentation:**
- Complete security audit documentation
- GPL v3 license
- Contributing guidelines
- Security disclosure procedure

---

## 🚀 Planned Versions

### **V1.1** — OS Security Tab (In Development) 🔧

**Status:** In Development

**Goal:** Empower users to harden their OS security with one-click toggles and comprehensive security checkups.

**Features:**

#### Security Toggles
Quick on/off switches for OS-level protections:

**Windows (8 toggles):**
- [ ] Firewall (all profiles)
- [ ] Disable Remote Desktop
- [ ] Disable SMBv1 (WannaCry vector)
- [ ] Disable Remote Registry
- [ ] Anti-ransomware (Controlled Folder Access)
- [ ] Connection audit logging
- [ ] Automatic updates
- [ ] BitLocker disk encryption (requires TPM 2.0)

**Linux (7 toggles):**
- [ ] UFW Firewall
- [ ] Secure network parameters (IP spoofing protection, ICMP redirects)
- [ ] Disable unnecessary services (printing, network discovery)
- [ ] Sensitive file permissions (/etc/shadow, /etc/ssh)
- [ ] Fail2Ban for SSH brute-force protection
- [ ] Automatic security updates
- [ ] Disable root login by password

**macOS (8 toggles):**
- [ ] Application firewall
- [ ] Stealth mode (invisible to network scans)
- [ ] FileVault disk encryption
- [ ] Disable SMB file sharing
- [ ] Automatic updates
- [ ] Secure keyboard entry (anti-keylogger)
- [ ] Gatekeeper (block unsigned apps)
- [ ] Automatic screen lock after sleep

#### System Checkup
Complete security scan with score out of 12:

- [ ] **Firewall status** — Is firewall active?
- [ ] **Pending updates** — OS updates available?
- [ ] **Disk encryption** — BitLocker/LUKS/FileVault enabled?
- [ ] **Antivirus/signatures** — Defender/rkhunter/XProtect up to date?
- [ ] **Malware scan** — Quick scan results
- [ ] **Startup programs** — Suspicious auto-start entries?
- [ ] **Scheduled tasks** — Unusual scheduled tasks?
- [ ] **Network connections** — Active connections analysis
- [ ] **Failed logins** — Recent failed connection attempts
- [ ] **User accounts** — Unauthorized accounts?
- [ ] **Disk space** — Sufficient free space?
- [ ] **OS-specific params** — SMBv1/network security/Gatekeeper status

**Result:** Score X/12 + personalized recommendations (✅ OK, ⚠️ Check, ❌ Issue detected)

**Privacy:** 100% local processing, no data sent over network 🔒

**ETA:** V1.1 — Q2 2026

---

### **V1.2** — Enhanced Error Diagnostics 🔮

**Status:** Planned

**Goal:** Better error messages and troubleshooting guidance.

**Features:**
- [ ] Detailed error explanations (not just "command failed")
- [ ] Context-aware troubleshooting suggestions
- [ ] Log export for debugging
- [ ] Connection test utility (SSH/WoL/Tailscale)
- [ ] System requirements checker (pre-installation)

**ETA:** V1.2 — Q3 2026

---

### **V1.3** — Extended Linux Support 🔮

**Status:** Planned

**Goal:** Support more Linux distributions and configurations.

**Features:**
- [ ] openSUSE support
- [ ] Gentoo support
- [ ] Alpine Linux support
- [ ] Non-systemd init systems (OpenRC, runit)
- [ ] Custom package manager detection
- [ ] Manual configuration fallback (if auto-detection fails)

**ETA:** V1.3 — Q3 2026

---

### **V1.4** — Advanced SSH Features 🔮

**Status:** Planned

**Goal:** More control over SSH configuration.

**Features:**
- [ ] Custom SSH port configuration
- [ ] SSH key algorithm selection (Ed25519, RSA, ECDSA)
- [ ] Key generation directly in Chill
- [ ] Public key export for manual setup
- [ ] sshd_config validation and hardening suggestions
- [ ] Two-factor authentication (2FA) setup assistance

**ETA:** V1.4 — Q4 2026

---

### **V1.5** — Localization Expansion 🔮

**Status:** Planned

**Goal:** Support more languages.

**Features:**
- [ ] Spanish (ES) translation
- [ ] German (DE) translation
- [ ] Chinese (ZH) translation
- [ ] Portuguese (PT) translation
- [ ] Italian (IT) translation
- [ ] Community-contributed translations

**ETA:** V1.5 — Q4 2026

---

### **V2.0** — Advanced Configuration 🔮

**Status:** Planned

**Goal:** Power user features and automation.

**Features:**
- [ ] Configuration profiles (save/load settings)
- [ ] Batch configuration (multiple PCs at once)
- [ ] Backup/restore settings
- [ ] CLI mode for scripting
- [ ] Network discovery (scan local network for devices)
- [ ] Remote configuration assistance (help friend over video call)
- [ ] Integration with ChillShell (push config from desktop to mobile)

**ETA:** V2.0 — 2027

---

## 🔮 Future Ideas (No ETA)

**Community-requested features** (not committed, subject to feasibility):

- **VPN Alternatives:**
  - WireGuard setup assistant
  - ZeroTier integration
  - OpenVPN configuration

- **Monitoring:**
  - Real-time SSH connection monitoring
  - Network traffic visualization
  - System resource monitoring

- **Automation:**
  - Scheduled Wake-on-LAN (wake PC at specific time)
  - Automatic SSH key rotation
  - Configuration drift detection

- **Security:**
  - Intrusion detection system (IDS) integration
  - Port scan detection
  - Firewall rule management UI

- **UI/UX:**
  - Onboarding tutorial/wizard
  - Video tutorials embedded in app
  - Dark/Light theme auto-switch (time-based)
  - Custom theme builder

**Have an idea?** Open a GitHub Issue with the `enhancement` label!

---

## 📊 Progress Tracking

| Version | Status | Features | Completion |
|---------|--------|----------|------------|
| **V1.0** | ✅ Released | SSH, WoL, Tailscale, PIN lock, i18n | 100% |
| **V1.1** | 🔧 In Development | OS Security Tab | ~60% |
| **V1.2** | 🔮 Planned | Enhanced error diagnostics | 0% |
| **V1.3** | 🔮 Planned | Extended Linux support | 0% |
| **V1.4** | 🔮 Planned | Advanced SSH features | 0% |
| **V1.5** | 🔮 Planned | Localization expansion | 0% |
| **V2.0** | 🔮 Planned | Advanced configuration | 0% |

---

## 🤝 Contributing to the Roadmap

**Want to help shape Chill's future?**

1. **Vote on features:** Comment on GitHub Issues to show interest
2. **Propose features:** Open new Issues with `enhancement` label
3. **Contribute code:** See [CONTRIBUTING.md](CONTRIBUTING.md)
4. **Sponsor development:** (Details coming soon)

**Prioritization criteria:**
- User impact (how many users benefit?)
- Security benefits
- Complexity vs. value
- Platform compatibility (cross-platform preferred)
- Community demand

---

## 📜 License

All features, past and future, are released under **GNU General Public License v3.0 (GPL v3)** — free and open forever.

---

## 📅 Version Timeline

```
2026 Feb ━━━━━━━━━━━●━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
              V1.0 Released

2026 Q2  ━━━━━━━━━━━━━━━━━━━━━━━●━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                        V1.1 (OS Security Tab)

2026 Q3  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━●━━━━━━━━●━━━━━━━━━━━━━━━━━━━━
                              V1.2        V1.3

2026 Q4  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━●━━━━━━━●━━━━━━━━━━━━
                                          V1.4    V1.5

2027     ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━●━━━━━━━━━━━━
                                                  V2.0
```

---

**Last updated:** February 2026

*This roadmap is subject to change based on user feedback, security requirements, and development capacity. Dates are estimates, not commitments.*
