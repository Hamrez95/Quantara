enum SupervisorRuntimeState {
  armed,
  blocked,
  managing,
  degraded,
  circuitBreaker,
  stopped,
}

final class SupervisorRuntimeObservation {
  const SupervisorRuntimeObservation({
    required this.state,
    required this.scannerRunning,
    required this.userRequestedEntries,
    required this.effectiveEntryPermission,
    required this.openPositionCount,
    required this.maxConcurrentPositions,
    required this.candidatesSeen,
    required this.candidatesRejected,
    required this.candidatesAdmitted,
    this.lastScanAtUtc,
    this.lastSuccessfulExchangeSyncAtUtc,
    this.topBlockReason,
  });

  final SupervisorRuntimeState state;
  final bool scannerRunning;
  final bool userRequestedEntries;
  final bool effectiveEntryPermission;
  final int openPositionCount;
  final int maxConcurrentPositions;
  final int candidatesSeen;
  final int candidatesRejected;
  final int candidatesAdmitted;
  final DateTime? lastScanAtUtc;
  final DateTime? lastSuccessfulExchangeSyncAtUtc;
  final String? topBlockReason;

  Map<String, Object?> toJson() => <String, Object?>{
    'state': state.name,
    'scannerRunning': scannerRunning,
    'userRequestedEntries': userRequestedEntries,
    'effectiveEntryPermission': effectiveEntryPermission,
    'openPositionCount': openPositionCount,
    'maxConcurrentPositions': maxConcurrentPositions,
    'slotsAvailable': (maxConcurrentPositions - openPositionCount).clamp(
      0,
      maxConcurrentPositions,
    ),
    'candidatesSeen': candidatesSeen,
    'candidatesRejected': candidatesRejected,
    'candidatesAdmitted': candidatesAdmitted,
    if (lastScanAtUtc != null)
      'lastScanAtUtc': lastScanAtUtc!.toUtc().toIso8601String(),
    if (lastSuccessfulExchangeSyncAtUtc != null)
      'lastSuccessfulExchangeSyncAtUtc':
          lastSuccessfulExchangeSyncAtUtc!.toUtc().toIso8601String(),
    if (topBlockReason != null) 'topBlockReason': topBlockReason,
  };
}

final class SupervisorRiskObservation {
  const SupervisorRiskObservation({
    required this.portfolioRiskConsumed,
    required this.portfolioRiskAvailable,
    required this.marginReserved,
    required this.marginSpendable,
    required this.managedPositionCount,
    required this.exchangePositionCount,
    required this.unmanagedExchangePositionCount,
  });

  final double portfolioRiskConsumed;
  final double portfolioRiskAvailable;
  final double marginReserved;
  final double marginSpendable;
  final int managedPositionCount;
  final int exchangePositionCount;
  final int unmanagedExchangePositionCount;

  Map<String, Object?> toJson() => <String, Object?>{
    'portfolioRiskConsumed': portfolioRiskConsumed,
    'portfolioRiskAvailable': portfolioRiskAvailable,
    'marginReserved': marginReserved,
    'marginSpendable': marginSpendable,
    'managedPositionCount': managedPositionCount,
    'exchangePositionCount': exchangePositionCount,
    'unmanagedExchangePositionCount': unmanagedExchangePositionCount,
  };
}

final class SupervisorStrategyObservation {
  const SupervisorStrategyObservation({
    required this.strategyId,
    required this.strategyVersion,
    required this.selectedSymbols,
    required this.selectedTimeframes,
  });

  final String strategyId;
  final String strategyVersion;
  final List<String> selectedSymbols;
  final List<String> selectedTimeframes;

  Map<String, Object?> toJson() => <String, Object?>{
    'strategyId': strategyId,
    'strategyVersion': strategyVersion,
    'selectedSymbols': List<String>.unmodifiable(selectedSymbols),
    'selectedTimeframes': List<String>.unmodifiable(selectedTimeframes),
  };
}

final class SupervisorLifecycleEvidence {
  const SupervisorLifecycleEvidence({
    required this.evidenceId,
    required this.kind,
    required this.summary,
    required this.occurredAtUtc,
  });

  final String evidenceId;
  final String kind;
  final String summary;
  final DateTime occurredAtUtc;

  Map<String, Object?> toJson() => <String, Object?>{
    'evidenceId': evidenceId,
    'kind': kind,
    'summary': summary,
    'occurredAtUtc': occurredAtUtc.toUtc().toIso8601String(),
  };
}

/// Immutable, explicitly allow-listed observation captured for read-only review.
///
/// Credential-bearing request data has no field in this contract. Unknown
/// runtime fields therefore cannot cross the Supervisor boundary implicitly.
final class SupervisorSnapshot {
  SupervisorSnapshot({
    required DateTime capturedAtUtc,
    required this.runtime,
    required this.risk,
    required this.strategy,
    List<SupervisorLifecycleEvidence> recentEvidence = const [],
  }) : capturedAtUtc = capturedAtUtc.toUtc(),
       recentEvidence = List.unmodifiable(recentEvidence);

  static const String schemaVersion = '1';

  final DateTime capturedAtUtc;
  final SupervisorRuntimeObservation runtime;
  final SupervisorRiskObservation risk;
  final SupervisorStrategyObservation strategy;
  final List<SupervisorLifecycleEvidence> recentEvidence;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'capturedAtUtc': capturedAtUtc.toIso8601String(),
    'runtime': runtime.toJson(),
    'risk': risk.toJson(),
    'strategy': strategy.toJson(),
    'recentEvidence': recentEvidence
        .map((item) => item.toJson())
        .toList(growable: false),
  };
}
