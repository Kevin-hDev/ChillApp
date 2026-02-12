enum StepStatus { pending, running, success, error }

/// Represente une etape de configuration
class SetupStep {
  final String id;
  final StepStatus status;
  final String? errorDetail;

  const SetupStep({
    required this.id,
    this.status = StepStatus.pending,
    this.errorDetail,
  });

  SetupStep copyWith({StepStatus? status, String? errorDetail}) {
    return SetupStep(
      id: id,
      status: status ?? this.status,
      errorDetail: errorDetail ?? this.errorDetail,
    );
  }
}
