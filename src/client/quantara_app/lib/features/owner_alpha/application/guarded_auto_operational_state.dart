enum GuardedAutoOperationalMode { disarmed, paused }

enum GuardedAutoPauseCause {
  userEmergencyStop,
  staleAccountSnapshot,
  contradictoryAccountEvidence,
  reconciliationFailure,
  repeatedApiFailure,
  strategyIdentityDrift,
  riskKillCondition,
  restoredUnknownState,
}

/// Durable operational guard for Guarded Auto.
///
/// This state intentionally has no `armed` mode. Arming remains owned by the
/// execution/safety admission path. This guard can only leave that path
/// disarmed or block new entries by pausing it.
final class GuardedAutoOperationalState {
  const GuardedAutoOperationalState._({
    required this.mode,
    required this.updatedAtUtc,
    this.pauseCause,
    this.operatorAction,
    this.lastHealthyAtUtc,
  });

  factory GuardedAutoOperationalState.disarmed({required DateTime atUtc}) =>
      GuardedAutoOperationalState._(
        mode: GuardedAutoOperationalMode.disarmed,
        updatedAtUtc: atUtc.toUtc(),
      );

  factory GuardedAutoOperationalState.paused({
    required GuardedAutoPauseCause cause,
    required DateTime atUtc,
    required String operatorAction,
    DateTime? lastHealthyAtUtc,
  }) {
    if (operatorAction.trim().isEmpty) {
      throw ArgumentError.value(operatorAction, 'operatorAction');
    }
    return GuardedAutoOperationalState._(
      mode: GuardedAutoOperationalMode.paused,
      pauseCause: cause,
      operatorAction: operatorAction.trim(),
      updatedAtUtc: atUtc.toUtc(),
      lastHealthyAtUtc: lastHealthyAtUtc?.toUtc(),
    );
  }

  final GuardedAutoOperationalMode mode;
  final GuardedAutoPauseCause? pauseCause;
  final String? operatorAction;
  final DateTime updatedAtUtc;
  final DateTime? lastHealthyAtUtc;

  bool get blocksNewEntries => true;
  bool get isPaused => mode == GuardedAutoOperationalMode.paused;

  GuardedAutoOperationalState emergencyPause({
    required DateTime atUtc,
    String operatorAction = 'Review safety evidence before re-enabling.',
    DateTime? lastHealthyAtUtc,
  }) => GuardedAutoOperationalState.paused(
    cause: GuardedAutoPauseCause.userEmergencyStop,
    atUtc: atUtc,
    operatorAction: operatorAction,
    lastHealthyAtUtc: lastHealthyAtUtc ?? this.lastHealthyAtUtc,
  );

  GuardedAutoOperationalState autoDisable({
    required GuardedAutoPauseCause cause,
    required DateTime atUtc,
    required String operatorAction,
    DateTime? lastHealthyAtUtc,
  }) {
    if (cause == GuardedAutoPauseCause.userEmergencyStop) {
      throw ArgumentError('Use emergencyPause for user emergency stop.');
    }
    return GuardedAutoOperationalState.paused(
      cause: cause,
      atUtc: atUtc,
      operatorAction: operatorAction,
      lastHealthyAtUtc: lastHealthyAtUtc ?? this.lastHealthyAtUtc,
    );
  }

  /// Recovery deliberately returns to disarmed; it can never auto-rearm.
  GuardedAutoOperationalState recoverToDisarmed({required DateTime atUtc}) =>
      GuardedAutoOperationalState.disarmed(atUtc: atUtc);

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': 1,
    'mode': mode.name,
    'pauseCause': pauseCause?.name,
    'operatorAction': operatorAction,
    'updatedAtUtc': updatedAtUtc.toIso8601String(),
    'lastHealthyAtUtc': lastHealthyAtUtc?.toIso8601String(),
  };

  static GuardedAutoOperationalState? tryFromJson(Map<String, Object?> json) {
    try {
      if (json['schemaVersion'] != 1) return null;
      final mode = GuardedAutoOperationalMode.values.byName(
        json['mode']! as String,
      );
      final updatedAtUtc = DateTime.parse(
        json['updatedAtUtc']! as String,
      ).toUtc();
      if (mode == GuardedAutoOperationalMode.disarmed) {
        return GuardedAutoOperationalState.disarmed(atUtc: updatedAtUtc);
      }
      final cause = GuardedAutoPauseCause.values.byName(
        json['pauseCause']! as String,
      );
      final action = json['operatorAction']! as String;
      final healthyRaw = json['lastHealthyAtUtc'];
      return GuardedAutoOperationalState.paused(
        cause: cause,
        atUtc: updatedAtUtc,
        operatorAction: action,
        lastHealthyAtUtc: healthyRaw is String
            ? DateTime.parse(healthyRaw).toUtc()
            : null,
      );
    } on Object {
      return null;
    }
  }
}
