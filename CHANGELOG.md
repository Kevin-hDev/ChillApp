# Changelog - Chill Desktop

All notable changes to Chill Desktop will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [1.0.0] - 2026-02-12

### 🎉 Initial Release

**Chill Desktop** — Your PC configuration assistant for SSH, Wake-on-LAN, and Tailscale.

### ✨ Added

#### Core Features
- **SSH Configuration Assistant**
  - Automated SSH server installation (Windows/Linux/macOS)
  - Per-OS command sequences (7 steps Windows, 5 Linux, 3 macOS)
  - Single admin password prompt for all operations
  - Real-time step progress indicators
  - Connection info display (Ethernet IP, WiFi IP, username, connection string)
  - One-click copy buttons for all connection details
  - Retry mechanism on failure

- **Wake-on-LAN Configuration**
  - Automated WoL setup (Windows/Linux, macOS not supported)
  - Network interface detection
  - MAC address retrieval
  - Magic Packet activation
  - systemd service creation on Linux
  - BIOS configuration reminder warnings
  - Real-time step progress indicators
  - Single admin password prompt for all operations

- **Tailscale Native Integration**
  - Custom Go daemon (`chill-tailscale`) using tsnet.Server
  - JSON stdin/stdout communication protocol
  - Connection persistence (auto-reconnect)
  - Zero external installation required
  - Multi-platform build script
  - Account creation and login flows

- **Connection Info Screen**
  - Auto-detection: Ethernet IP, WiFi IP, MAC address, username, network adapter
  - OS-specific commands (Windows/Linux/macOS)
  - One-click copy for each info
  - Refresh button for real-time updates
  - Tailscale security recommendation card

- **Dashboard**
  - 6-card grid layout (SSH, WoL, Tailscale, Info, Settings, Mascot)
  - Status badges (configured/not configured) on SSH and WoL cards
  - Automatic status verification on launch
  - Responsive grid (2-3 columns based on width)

#### Security
- **PIN Lock**
  - 8-digit PIN code protection
  - SHA-256 hashing before storage
  - Visual numeric keypad + keyboard support
  - Shake animation on error
  - 5 attempt limit
  - Enable/disable/change PIN in settings
  - PIN confirmation (double entry verification)

- **Privilege Management**
  - OS-specific elevation (RunAs/pkexec/osascript)
  - Single script execution with batch commands
  - Temporary script cleanup after execution

#### Design & UX
- **Design System**
  - Dark + Light theme support
  - Design tokens (colors, spacing, radii)
  - JetBrains Mono (headings) + Plus Jakarta Sans (body)
  - Custom ChillCard, ChillButton, StepIndicator, StatusBadge widgets

- **Internationalization**
  - Complete FR/EN translations (80+ keys)
  - Language selector in settings
  - Persistent language preference

- **Responsive Design**
  - Minimum window size 800x600 (GTK Linux)
  - Adaptive padding based on width
  - Scrollable screens (no overflow)
  - Mascot illustration (dashboard)
  - Animated loader character (SSH/WoL screens)

#### Technical Infrastructure
- **OS Detection**
  - Platform detection (Windows/Linux/macOS)
  - Linux distribution detection (Debian/Fedora/Arch via ID_LIKE)
  - Auto-selection of appropriate package manager

- **Command Execution**
  - CommandRunner (Process.run wrapper)
  - Timeout handling (120s default)
  - Stdout/stderr capture
  - Exit code validation

- **Navigation**
  - go_router with 5 routes (/, /ssh, /wol, /info, /settings)
  - Deep linking support

#### Testing
- Unit tests for:
  - State models (SetupStep, SshSetupState, WolSetupState, ConnectionInfoState, DashboardState, TailscaleState, LockState)
  - CommandRunner (simple command, nonexistent command, stdout trim)
  - Translations (FR/EN parity, no empty values, critical keys)

### 🛠️ Technical Details

**Architecture:**
- Flutter 3.27+ (Windows/Linux/macOS)
- Riverpod 3.2.1 (state management)
- go_router 16.2.2 (navigation)
- shared_preferences 2.5.4 (persistence)
- google_fonts 8.0.1 (typography)
- Custom Go daemon (Tailscale tsnet integration)

**Build Requirements:**
- Flutter via git (not snap) for Linux builds
- lld-18 linker on Ubuntu
- Go 1.21+ for Tailscale daemon compilation

**Known Limitations:**
- WoL on Linux unreliable depending on network card/kernel (works better from Windows in dual-boot)
- macOS WoL not supported (hardware limitations)
- Dashboard WoL verification uses `systemctl is-enabled wol-enable.service` (no sudo needed)

### 📦 Platforms

- **Windows:** 10, 11 (PowerShell 5.1+)
- **Linux:** Ubuntu 20.04+, Debian 11+, Fedora 35+, Arch (systemd required)
- **macOS:** 11+ (Big Sur and later, Rosetta 2 for Apple Silicon)

---

## [Unreleased]

### 🔮 Planned Features

- **OS Security Tab** (in development)
  - Security toggles for OS hardening
  - System security checkup (12-point scan)
  - Windows: Firewall, Anti-ransomware, BitLocker, Remote Desktop, SMBv1, etc.
  - Linux: UFW, Fail2Ban, secure network params, file permissions, etc.
  - macOS: Firewall, FileVault, Gatekeeper, Stealth mode, etc.

- UI tests for all screens
- Automated installer/packaging
- Additional Linux distributions support
- Enhanced error diagnostics
- Localization (ES, DE, ZH)

---

## Version History

- **1.0.0** (2026-02-12) — Initial release with SSH, WoL, Tailscale configuration

---

**Legend:**
- ✨ Added: New features
- 🔧 Changed: Changes to existing features
- 🐛 Fixed: Bug fixes
- 🗑️ Removed: Removed features
- 🔒 Security: Security improvements
