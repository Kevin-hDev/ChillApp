import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../ssh_setup/ssh_setup_provider.dart';

class WolSetupState {
  final Map<String, StepStatus> steps;
  final String? macAddress;
  final String? errorMessage;

  const WolSetupState({
    this.steps = const {},
    this.macAddress,
    this.errorMessage,
  });

  WolSetupState copyWith({
    Map<String, StepStatus>? steps,
    String? macAddress,
    String? errorMessage,
  }) {
    return WolSetupState(
      steps: steps ?? this.steps,
      macAddress: macAddress ?? this.macAddress,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

final wolSetupProvider = NotifierProvider<WolSetupNotifier, WolSetupState>(WolSetupNotifier.new);

class WolSetupNotifier extends Notifier<WolSetupState> {
  @override
  WolSetupState build() => const WolSetupState();

  // TODO: Implémenter les commandes WoL pour chaque OS
}
