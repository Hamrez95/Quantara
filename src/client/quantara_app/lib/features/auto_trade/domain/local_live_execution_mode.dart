enum LocalLiveExecutionMode {
  readOnly,
  approvalRequired,
  guardedAuto,
}

extension LocalLiveExecutionModeJson on LocalLiveExecutionMode {
  String get wireName => switch (this) {
    LocalLiveExecutionMode.readOnly => 'read_only',
    LocalLiveExecutionMode.approvalRequired => 'approval_required',
    LocalLiveExecutionMode.guardedAuto => 'guarded_auto',
  };

  bool get canSubmitEntries => this != LocalLiveExecutionMode.readOnly;

  bool get requiresPerTradeApproval =>
      this == LocalLiveExecutionMode.approvalRequired;

  static LocalLiveExecutionMode parse(Object? value) => switch (value) {
    'guarded_auto' => LocalLiveExecutionMode.guardedAuto,
    'approval_required' => LocalLiveExecutionMode.approvalRequired,
    _ => LocalLiveExecutionMode.readOnly,
  };
}
