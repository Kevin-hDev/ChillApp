import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/os_detector.dart';
import 'security_commands.dart';
import 'widgets/services_toggle_card.dart';

enum CheckupStatus { ok, warning, error }
enum CheckSeverity { critical, high, medium, minor }

/// Poids de chaque niveau de sévérité pour le calcul du score
const _severityWeights = {
  CheckSeverity.critical: 4.0,
  CheckSeverity.high: 3.0,
  CheckSeverity.medium: 2.0,
  CheckSeverity.minor: 1.0,
};

/// Sévérité de chaque check par ID (tous OS confondus)
const checkSeverities = <String, CheckSeverity>{
  // Critique — si c'est OFF, tu es très vulnérable
  'firewall': CheckSeverity.critical,
  'gatekeeper': CheckSeverity.critical,
  'antivirus': CheckSeverity.critical,
  // Haut — très important
  'rootLogin': CheckSeverity.high,
  'fail2ban': CheckSeverity.high,
  'network': CheckSeverity.high,
  'permissions': CheckSeverity.high,
  'smb1': CheckSeverity.high,
  'stealth': CheckSeverity.high,
  'updates': CheckSeverity.high,
  // Moyen
  'failedLogins': CheckSeverity.medium,
  'secureKeyboard': CheckSeverity.medium,
  'screenLock': CheckSeverity.medium,
  'accounts': CheckSeverity.medium,
  // Mineur
  'disk': CheckSeverity.minor,
  'rkhunter': CheckSeverity.minor,
};

class CheckupItem {
  final String id;
  final CheckupStatus status;
  final String detail;
  final CheckSeverity severity;

  const CheckupItem({
    required this.id,
    required this.status,
    required this.detail,
    required this.severity,
  });
}

class SecurityState {
  final Map<String, bool?> toggleStates;
  final Map<String, bool> toggleLoading;
  final bool isCheckingAll;
  // Pour les outils qui nécessitent installation
  final Map<String, bool> installed; // fail2ban, rkhunter, ufw
  // Services Linux
  final List<ServiceItem> services;
  final Set<String> loadingServices;
  // Checkup
  final bool isCheckupRunning;
  final List<CheckupItem>? checkupResults;
  final double? checkupScore;
  // Scan antivirus/rootkit
  final bool isScanRunning;
  final List<String>? scanWarnings; // null = pas encore lancé, [] = propre
  final String? error;

  const SecurityState({
    this.toggleStates = const {},
    this.toggleLoading = const {},
    this.isCheckingAll = true,
    this.installed = const {},
    this.services = const [],
    this.loadingServices = const {},
    this.isCheckupRunning = false,
    this.checkupResults,
    this.checkupScore,
    this.isScanRunning = false,
    this.scanWarnings,
    this.error,
  });

  SecurityState copyWith({
    Map<String, bool?>? toggleStates,
    Map<String, bool>? toggleLoading,
    bool? isCheckingAll,
    Map<String, bool>? installed,
    List<ServiceItem>? services,
    Set<String>? loadingServices,
    bool? isCheckupRunning,
    List<CheckupItem>? checkupResults,
    double? checkupScore,
    bool? isScanRunning,
    List<String>? scanWarnings,
    String? error,
  }) {
    return SecurityState(
      toggleStates: toggleStates ?? this.toggleStates,
      toggleLoading: toggleLoading ?? this.toggleLoading,
      isCheckingAll: isCheckingAll ?? this.isCheckingAll,
      installed: installed ?? this.installed,
      services: services ?? this.services,
      loadingServices: loadingServices ?? this.loadingServices,
      isCheckupRunning: isCheckupRunning ?? this.isCheckupRunning,
      checkupResults: checkupResults ?? this.checkupResults,
      checkupScore: checkupScore ?? this.checkupScore,
      isScanRunning: isScanRunning ?? this.isScanRunning,
      scanWarnings: scanWarnings ?? this.scanWarnings,
      error: error,
    );
  }
}

final securityProvider =
    NotifierProvider<SecurityNotifier, SecurityState>(SecurityNotifier.new);

class SecurityNotifier extends Notifier<SecurityState> {
  @override
  SecurityState build() {
    // Lancer la vérification initiale de tous les toggles
    Future.microtask(() => checkAllStatuses());
    return const SecurityState();
  }

  /// Vérifie l'état de chaque toggle selon l'OS
  Future<void> checkAllStatuses() async {
    state = state.copyWith(isCheckingAll: true);

    try {
      final os = OsDetector.currentOS;
      switch (os) {
        case SupportedOS.windows:
          await _checkWindowsStatuses();
          break;
        case SupportedOS.linux:
          await _checkLinuxStatuses();
          break;
        case SupportedOS.macos:
          await _checkMacStatuses();
          break;
      }
    } catch (e) {
      debugPrint('[Security] checkAllStatuses error: $e');
      state = state.copyWith(error: e.toString());
    }

    state = state.copyWith(isCheckingAll: false);
  }

  Future<void> _checkWindowsStatuses() async {
    final states = <String, bool?>{};

    states['win.firewall'] = await SecurityCommands.checkWindowsFirewall();
    states['win.rdp'] = await SecurityCommands.checkWindowsRdp();
    states['win.smb1'] = await SecurityCommands.checkWindowsSmb1();
    states['win.remoteRegistry'] = await SecurityCommands.checkWindowsRemoteRegistry();
    states['win.ransomware'] = await SecurityCommands.checkWindowsRansomware();
    states['win.audit'] = await SecurityCommands.checkWindowsAudit();
    states['win.updates'] = await SecurityCommands.checkWindowsUpdates();

    state = state.copyWith(toggleStates: states);
  }

  Future<void> _checkLinuxStatuses() async {
    final states = <String, bool?>{};
    final installedMap = <String, bool>{};

    // Vérifier les installations
    installedMap['ufw'] = await SecurityCommands.checkLinuxUfwInstalled();
    installedMap['fail2ban'] = await SecurityCommands.checkLinuxFail2banInstalled();
    installedMap['rkhunter'] = await SecurityCommands.checkLinuxRkhunterInstalled();

    states['linux.firewall'] = installedMap['ufw']! ? await SecurityCommands.checkLinuxFirewall() : null;
    states['linux.sysctl'] = await SecurityCommands.checkLinuxSysctl();
    states['linux.permissions'] = await SecurityCommands.checkLinuxPermissions();
    states['linux.fail2ban'] = installedMap['fail2ban']! ? await SecurityCommands.checkLinuxFail2ban() : null;
    states['linux.updates'] = await SecurityCommands.checkLinuxUpdates();
    states['linux.rootLogin'] = await SecurityCommands.checkLinuxRootLogin();

    // Détecter les services
    final servicesList = await SecurityCommands.detectLinuxServices();
    final services = servicesList
        .map((s) => ServiceItem(
              name: s['name'] as String,
              displayName: s['display'] as String,
              isActive: s['active'] as bool,
            ))
        .toList();

    state = state.copyWith(
      toggleStates: states,
      installed: installedMap,
      services: services,
    );
  }

  Future<void> _checkMacStatuses() async {
    final states = <String, bool?>{};

    states['mac.firewall'] = await SecurityCommands.checkMacFirewall();
    states['mac.stealth'] = await SecurityCommands.checkMacStealth();
    states['mac.smb'] = await SecurityCommands.checkMacSmb();
    states['mac.updates'] = await SecurityCommands.checkMacUpdates();
    states['mac.secureKeyboard'] = await SecurityCommands.checkMacSecureKeyboard();
    states['mac.gatekeeper'] = await SecurityCommands.checkMacGatekeeper();
    states['mac.screenLock'] = await SecurityCommands.checkMacScreenLock();

    state = state.copyWith(toggleStates: states);
  }

  /// Active ou désactive un toggle, puis vérifie l'état réel
  Future<void> toggle(String id, bool enable) async {
    // Marquer comme loading
    final loading = Map<String, bool>.from(state.toggleLoading);
    loading[id] = true;
    state = state.copyWith(toggleLoading: loading);

    try {
      await _executeToggle(id, enable);
      // Vérifier l'état réel après le toggle (ne pas faire confiance au code de sortie)
      final actualState = await _checkSingleToggle(id);
      final states = Map<String, bool?>.from(state.toggleStates);
      states[id] = actualState ?? enable;
      state = state.copyWith(toggleStates: states);
    } catch (e) {
      debugPrint('[Security] toggle error: $e');
      state = state.copyWith(error: e.toString());
    }

    // Enlever le loading
    final loadingAfter = Map<String, bool>.from(state.toggleLoading);
    loadingAfter.remove(id);
    state = state.copyWith(toggleLoading: loadingAfter);
  }

  /// Re-vérifie l'état d'un seul toggle après une action
  Future<bool?> _checkSingleToggle(String id) async {
    switch (id) {
      // Linux
      case 'linux.firewall': return SecurityCommands.checkLinuxFirewall();
      case 'linux.sysctl': return SecurityCommands.checkLinuxSysctl();
      case 'linux.permissions': return SecurityCommands.checkLinuxPermissions();
      case 'linux.fail2ban': return SecurityCommands.checkLinuxFail2ban();
      case 'linux.updates': return SecurityCommands.checkLinuxUpdates();
      case 'linux.rootLogin': return SecurityCommands.checkLinuxRootLogin();
      // Windows
      case 'win.firewall': return SecurityCommands.checkWindowsFirewall();
      case 'win.rdp': return SecurityCommands.checkWindowsRdp();
      case 'win.smb1': return SecurityCommands.checkWindowsSmb1();
      case 'win.remoteRegistry': return SecurityCommands.checkWindowsRemoteRegistry();
      case 'win.ransomware': return SecurityCommands.checkWindowsRansomware();
      case 'win.audit': return SecurityCommands.checkWindowsAudit();
      case 'win.updates': return SecurityCommands.checkWindowsUpdates();
      // macOS
      case 'mac.firewall': return SecurityCommands.checkMacFirewall();
      case 'mac.stealth': return SecurityCommands.checkMacStealth();
      case 'mac.smb': return SecurityCommands.checkMacSmb();
      case 'mac.updates': return SecurityCommands.checkMacUpdates();
      case 'mac.secureKeyboard': return SecurityCommands.checkMacSecureKeyboard();
      case 'mac.gatekeeper': return SecurityCommands.checkMacGatekeeper();
      case 'mac.screenLock': return SecurityCommands.checkMacScreenLock();
      default: return null;
    }
  }

  Future<bool> _executeToggle(String id, bool enable) async {
    switch (id) {
      // Windows
      case 'win.firewall':
        return enable ? SecurityCommands.enableWindowsFirewall() : SecurityCommands.disableWindowsFirewall();
      case 'win.rdp':
        return enable ? SecurityCommands.enableWindowsRdpProtection() : SecurityCommands.disableWindowsRdpProtection();
      case 'win.smb1':
        return enable ? SecurityCommands.enableWindowsSmb1Protection() : SecurityCommands.disableWindowsSmb1Protection();
      case 'win.remoteRegistry':
        return enable
            ? SecurityCommands.enableWindowsRemoteRegistryProtection()
            : SecurityCommands.disableWindowsRemoteRegistryProtection();
      case 'win.ransomware':
        return enable ? SecurityCommands.enableWindowsRansomware() : SecurityCommands.disableWindowsRansomware();
      case 'win.audit':
        return enable ? SecurityCommands.enableWindowsAudit() : SecurityCommands.disableWindowsAudit();
      case 'win.updates':
        return enable ? SecurityCommands.enableWindowsUpdates() : SecurityCommands.disableWindowsUpdates();

      // Linux
      case 'linux.firewall':
        return enable ? SecurityCommands.enableLinuxFirewall() : SecurityCommands.disableLinuxFirewall();
      case 'linux.sysctl':
        return enable ? SecurityCommands.enableLinuxSysctl() : SecurityCommands.disableLinuxSysctl();
      case 'linux.permissions':
        return SecurityCommands.enableLinuxPermissions(); // Pas de "disable"
      case 'linux.fail2ban':
        return enable ? SecurityCommands.enableLinuxFail2ban() : SecurityCommands.disableLinuxFail2ban();
      case 'linux.updates':
        return enable ? SecurityCommands.enableLinuxUpdates() : SecurityCommands.disableLinuxUpdates();
      case 'linux.rootLogin':
        return enable
            ? SecurityCommands.enableLinuxRootLoginProtection()
            : SecurityCommands.disableLinuxRootLoginProtection();

      // macOS
      case 'mac.firewall':
        return enable ? SecurityCommands.enableMacFirewall() : SecurityCommands.disableMacFirewall();
      case 'mac.stealth':
        return enable ? SecurityCommands.enableMacStealth() : SecurityCommands.disableMacStealth();
      case 'mac.smb':
        return enable ? SecurityCommands.enableMacSmbProtection() : SecurityCommands.disableMacSmbProtection();
      case 'mac.updates':
        return enable ? SecurityCommands.enableMacUpdates() : SecurityCommands.disableMacUpdates();
      case 'mac.secureKeyboard':
        return enable ? SecurityCommands.enableMacSecureKeyboard() : SecurityCommands.disableMacSecureKeyboard();
      case 'mac.gatekeeper':
        return enable ? SecurityCommands.enableMacGatekeeper() : SecurityCommands.disableMacGatekeeper();
      case 'mac.screenLock':
        return enable ? SecurityCommands.enableMacScreenLock() : SecurityCommands.disableMacScreenLock();

      default:
        return false;
    }
  }

  /// Installer un outil (UFW, fail2ban, rkhunter)
  Future<void> install(String toolId) async {
    final loading = Map<String, bool>.from(state.toggleLoading);
    loading[toolId] = true;
    state = state.copyWith(toggleLoading: loading);

    try {
      bool success = false;
      switch (toolId) {
        case 'ufw':
          success = await SecurityCommands.installLinuxUfw();
          break;
        case 'fail2ban':
          success = await SecurityCommands.installLinuxFail2ban();
          break;
        case 'rkhunter':
          success = await SecurityCommands.installLinuxRkhunter();
          break;
      }

      if (success) {
        final installed = Map<String, bool>.from(state.installed);
        installed[toolId] = true;
        state = state.copyWith(installed: installed);
        // Revérifier le statut du toggle associé
        await checkAllStatuses();
      }
    } catch (e) {
      debugPrint('[Security] install error: $e');
      state = state.copyWith(error: e.toString());
    }

    final loadingAfter = Map<String, bool>.from(state.toggleLoading);
    loadingAfter.remove(toolId);
    state = state.copyWith(toggleLoading: loadingAfter);
  }

  /// Activer/désactiver un service Linux
  Future<void> toggleService(String serviceName) async {
    final loadingServices = Set<String>.from(state.loadingServices);
    loadingServices.add(serviceName);
    state = state.copyWith(loadingServices: loadingServices);

    try {
      final currentService = state.services.firstWhere((s) => s.name == serviceName);
      final success = await SecurityCommands.toggleLinuxService(
        serviceName,
        !currentService.isActive,
      );

      if (success) {
        final services = state.services.map((s) {
          if (s.name == serviceName) {
            return ServiceItem(
              name: s.name,
              displayName: s.displayName,
              isActive: !s.isActive,
            );
          }
          return s;
        }).toList();
        state = state.copyWith(services: services);
      }
    } catch (e) {
      debugPrint('[Security] toggleService error: $e');
    }

    final loadingAfter = Set<String>.from(state.loadingServices);
    loadingAfter.remove(serviceName);
    state = state.copyWith(loadingServices: loadingAfter);
  }

  /// Lancer un scan antivirus/rootkit (rkhunter sur Linux, Defender sur Windows)
  Future<void> runScan() async {
    state = state.copyWith(isScanRunning: true, scanWarnings: null);

    try {
      final os = OsDetector.currentOS;
      List<String> warnings;

      if (os == SupportedOS.linux) {
        warnings = await SecurityCommands.runRkhunterScan();
      } else if (os == SupportedOS.windows) {
        warnings = await SecurityCommands.runDefenderScan();
      } else {
        warnings = [];
      }

      state = state.copyWith(isScanRunning: false, scanWarnings: warnings);
    } catch (e) {
      debugPrint('[Security] scan error: $e');
      state = state.copyWith(
        isScanRunning: false,
        scanWarnings: ['Erreur: $e'],
      );
    }
  }

  /// Lancer le checkup complet
  Future<void> runCheckup() async {
    state = state.copyWith(
      isCheckupRunning: true,
      checkupResults: null,
      checkupScore: null,
    );

    try {
      final rawResults = await SecurityCommands.runCheckup();

      final results = rawResults.map((r) {
        final statusStr = r['status'] ?? 'warning';
        final id = r['id'] ?? '';
        CheckupStatus status;
        switch (statusStr) {
          case 'ok':
            status = CheckupStatus.ok;
            break;
          case 'error':
            status = CheckupStatus.error;
            break;
          default:
            status = CheckupStatus.warning;
        }
        return CheckupItem(
          id: id,
          status: status,
          detail: r['detail'] ?? '',
          severity: checkSeverities[id] ?? CheckSeverity.medium,
        );
      }).toList();

      // Calculer le score pondéré par sévérité
      double weightedScore = 0;
      double maxWeight = 0;
      for (final item in results) {
        final weight = _severityWeights[item.severity] ?? 2.0;
        maxWeight += weight;
        switch (item.status) {
          case CheckupStatus.ok:
            weightedScore += weight;
            break;
          case CheckupStatus.warning:
            weightedScore += weight * 0.5;
            break;
          case CheckupStatus.error:
            break;
        }
      }
      final totalScore = maxWeight > 0 ? weightedScore / maxWeight : 0.0;

      state = state.copyWith(
        isCheckupRunning: false,
        checkupResults: results,
        checkupScore: totalScore,
      );
    } catch (e) {
      debugPrint('[Security] checkup error: $e');
      state = state.copyWith(
        isCheckupRunning: false,
        error: 'Erreur lors du checkup: $e',
      );
    }
  }
}
