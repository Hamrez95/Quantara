import 'auto_trade_models.dart';

enum PrivateAccountReconciliationHealth { unavailable, fresh, stale, divergent }

abstract final class ExchangeTruthPhaseOneGate {
  static const bool realEntriesAllowed = true;
  static const bool explicitUserArmRequired = true;
  static const bool automaticArmAllowed = false;
  static const String reason =
      'Guarded Local Live entries require an explicit user start after fresh exchange reconciliation.';
}

enum PrivateAccountRefreshReason {
  initialize,
  connect,
  manual,
  accountPageOpened,
  appResume,
  localLiveEvent,
  activePolling,
  startPreflight,
}

final class PrivateAccountReconciliationState {
  const PrivateAccountReconciliationState({
    required this.health,
    required this.snapshot,
    required this.cycleId,
    required this.completedAt,
    required this.lastAttemptAt,
    required this.refreshing,
    required this.warning,
    required this.localLiveOpenPositionCount,
    required this.localLiveObservedAt,
  });

  factory PrivateAccountReconciliationState.unavailable({DateTime? at}) {
    final timestamp = at?.toUtc();
    return PrivateAccountReconciliationState(
      health: PrivateAccountReconciliationHealth.unavailable,
      snapshot: null,
      cycleId: null,
      completedAt: null,
      lastAttemptAt: timestamp,
      refreshing: false,
      warning: null,
      localLiveOpenPositionCount: null,
      localLiveObservedAt: null,
    );
  }

  factory PrivateAccountReconciliationState.fresh({
    required AutoTradeAccountSnapshot snapshot,
    required String cycleId,
    required DateTime completedAt,
    int? localLiveOpenPositionCount,
    DateTime? localLiveObservedAt,
  }) {
    final normalizedCompletedAt = completedAt.toUtc();
    final normalizedObservedAt = localLiveObservedAt?.toUtc();
    final divergent = _isNewerCountDivergent(
      snapshot: snapshot,
      openPositionCount: localLiveOpenPositionCount,
      observedAt: normalizedObservedAt,
    );
    return PrivateAccountReconciliationState(
      health: divergent
          ? PrivateAccountReconciliationHealth.divergent
          : PrivateAccountReconciliationHealth.fresh,
      snapshot: snapshot,
      cycleId: cycleId,
      completedAt: normalizedCompletedAt,
      lastAttemptAt: normalizedCompletedAt,
      refreshing: false,
      warning: divergent
          ? 'Local Live and the private-account snapshot disagree about open positions.'
          : null,
      localLiveOpenPositionCount: localLiveOpenPositionCount,
      localLiveObservedAt: normalizedObservedAt,
    );
  }

  final PrivateAccountReconciliationHealth health;
  final AutoTradeAccountSnapshot? snapshot;
  final String? cycleId;
  final DateTime? completedAt;
  final DateTime? lastAttemptAt;
  final bool refreshing;
  final String? warning;
  final int? localLiveOpenPositionCount;
  final DateTime? localLiveObservedAt;

  bool get blocksNewEntries =>
      snapshot == null || health != PrivateAccountReconciliationHealth.fresh;

  bool get allowsExistingPositionManagement =>
      snapshot?.positions.isNotEmpty ?? false;

  bool get hasLastKnownSnapshot => snapshot != null;

  PrivateAccountReconciliationState markRefreshing(DateTime attemptedAt) =>
      _copyWith(
        lastAttemptAt: attemptedAt.toUtc(),
        refreshing: true,
        warning: warning,
      );

  PrivateAccountReconciliationState acceptSnapshot({
    required AutoTradeAccountSnapshot value,
    required String nextCycleId,
    required DateTime completedAt,
  }) => PrivateAccountReconciliationState.fresh(
    snapshot: value,
    cycleId: nextCycleId,
    completedAt: completedAt,
    localLiveOpenPositionCount: localLiveOpenPositionCount,
    localLiveObservedAt: localLiveObservedAt,
  );

  PrivateAccountReconciliationState markRefreshFailure({
    required DateTime attemptedAt,
    required String warning,
  }) => PrivateAccountReconciliationState(
    health: snapshot == null
        ? PrivateAccountReconciliationHealth.unavailable
        : PrivateAccountReconciliationHealth.stale,
    snapshot: snapshot,
    cycleId: cycleId,
    completedAt: completedAt,
    lastAttemptAt: attemptedAt.toUtc(),
    refreshing: false,
    warning: warning,
    localLiveOpenPositionCount: localLiveOpenPositionCount,
    localLiveObservedAt: localLiveObservedAt,
  );

  PrivateAccountReconciliationState evaluateFreshness({
    required DateTime now,
    required Duration staleAfter,
  }) {
    if (snapshot == null || completedAt == null) return this;
    if (health == PrivateAccountReconciliationHealth.divergent) return this;
    final age = now.toUtc().difference(completedAt!);
    if (age <= staleAfter) return this;
    if (health == PrivateAccountReconciliationHealth.stale && !refreshing) {
      return this;
    }
    return _copyWith(
      health: PrivateAccountReconciliationHealth.stale,
      refreshing: false,
      warning: 'The private-account snapshot is stale.',
    );
  }

  PrivateAccountReconciliationState observeLocalLiveOpenPositions({
    required int openPositionCount,
    required DateTime observedAt,
  }) {
    if (openPositionCount < 0) {
      throw const FormatException('Open position count cannot be negative.');
    }
    final normalizedObservedAt = observedAt.toUtc();
    final currentObservedAt = localLiveObservedAt;
    if (currentObservedAt != null &&
        normalizedObservedAt.isBefore(currentObservedAt)) {
      return this;
    }
    if (snapshot == null) {
      return PrivateAccountReconciliationState(
        health: PrivateAccountReconciliationHealth.unavailable,
        snapshot: null,
        cycleId: cycleId,
        completedAt: completedAt,
        lastAttemptAt: lastAttemptAt,
        refreshing: refreshing,
        warning:
            'Local Live reported exchange state before a private-account snapshot was available.',
        localLiveOpenPositionCount: openPositionCount,
        localLiveObservedAt: normalizedObservedAt,
      );
    }
    if (normalizedObservedAt.isBefore(snapshot!.syncedAt.toUtc())) {
      return _copyWith(
        localLiveOpenPositionCount: openPositionCount,
        localLiveObservedAt: normalizedObservedAt,
      );
    }
    final divergent = openPositionCount != snapshot!.positions.length;
    return _copyWith(
      health: divergent
          ? PrivateAccountReconciliationHealth.divergent
          : PrivateAccountReconciliationHealth.fresh,
      refreshing: refreshing,
      warning: divergent
          ? 'Local Live and the private-account snapshot disagree about open positions.'
          : null,
      localLiveOpenPositionCount: openPositionCount,
      localLiveObservedAt: normalizedObservedAt,
    );
  }

  PrivateAccountReconciliationState clear({DateTime? at}) =>
      PrivateAccountReconciliationState.unavailable(at: at);

  PrivateAccountReconciliationState _copyWith({
    PrivateAccountReconciliationHealth? health,
    AutoTradeAccountSnapshot? snapshot,
    String? cycleId,
    DateTime? completedAt,
    DateTime? lastAttemptAt,
    bool? refreshing,
    Object? warning = _notProvided,
    int? localLiveOpenPositionCount,
    DateTime? localLiveObservedAt,
  }) => PrivateAccountReconciliationState(
    health: health ?? this.health,
    snapshot: snapshot ?? this.snapshot,
    cycleId: cycleId ?? this.cycleId,
    completedAt: completedAt ?? this.completedAt,
    lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
    refreshing: refreshing ?? this.refreshing,
    warning: identical(warning, _notProvided)
        ? this.warning
        : warning as String?,
    localLiveOpenPositionCount:
        localLiveOpenPositionCount ?? this.localLiveOpenPositionCount,
    localLiveObservedAt: localLiveObservedAt ?? this.localLiveObservedAt,
  );

  static bool _isNewerCountDivergent({
    required AutoTradeAccountSnapshot snapshot,
    required int? openPositionCount,
    required DateTime? observedAt,
  }) =>
      openPositionCount != null &&
      observedAt != null &&
      !observedAt.isBefore(snapshot.syncedAt.toUtc()) &&
      openPositionCount != snapshot.positions.length;

  static const Object _notProvided = Object();
}
