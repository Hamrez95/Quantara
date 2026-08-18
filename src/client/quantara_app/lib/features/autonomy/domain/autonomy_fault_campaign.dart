import 'dart:collection';

import 'package:flutter/foundation.dart';

import 'autonomy_certification.dart';

enum AutonomyFaultCode {
  marketDisconnectReconnectStorm,
  staleTickerOrKline,
  klineGapBackfillFailure,
  duplicateOrOutOfOrderMarketEvent,
  marketShardUnavailable,
  boundedQueueSaturation,
  localClockJump,
  privateDisconnectBeforeSubmit,
  privateDisconnectAfterSubmit,
  submitTimeoutUnknownOutcome,
  acknowledgementLostFillExists,
  duplicateAcknowledgementOrFill,
  partialFillBeforeReconciliation,
  protectionPlacementRejected,
  protectionPlacementTimeout,
  protectionPlacementAmbiguous,
  takeProfitStopLossOrderingRace,
  externalPositionAppears,
  exchangeAccountCountDivergence,
  historyTemporarilyUnavailable,
  exchangeRateLimitOrTransientServerError,
  androidBackgroundForegroundTransition,
  foregroundServiceRestart,
  processDeathAfterReservation,
  processDeathAfterSubmit,
  processDeathAfterFill,
  processDeathAfterProtection,
  processDeathAfterClose,
  databaseWriteInterruption,
  restartDuringStopPromotion,
  appUpdateWithOpenDurableState,
  constrainedMemoryOrCpu,
  networkTransportFlap,
  strategyQuarantinedWithOpenPosition,
  driftBreakerTriggered,
  latencyOrSlippageBreakerTriggered,
  drawdownBreakerWithCandidateArrival,
  candidateStaleBetweenRankingAndSubmit,
  policyVersionChangesWithFrozenDecision,
}

extension AutonomyFaultCodeMetadata on AutonomyFaultCode {
  AutonomyFaultCategory get category => switch (this) {
    AutonomyFaultCode.marketDisconnectReconnectStorm ||
    AutonomyFaultCode.staleTickerOrKline ||
    AutonomyFaultCode.klineGapBackfillFailure ||
    AutonomyFaultCode.duplicateOrOutOfOrderMarketEvent ||
    AutonomyFaultCode.marketShardUnavailable ||
    AutonomyFaultCode.boundedQueueSaturation ||
    AutonomyFaultCode.localClockJump => AutonomyFaultCategory.marketPublic,
    AutonomyFaultCode.privateDisconnectBeforeSubmit ||
    AutonomyFaultCode.privateDisconnectAfterSubmit ||
    AutonomyFaultCode.submitTimeoutUnknownOutcome ||
    AutonomyFaultCode.acknowledgementLostFillExists ||
    AutonomyFaultCode.duplicateAcknowledgementOrFill ||
    AutonomyFaultCode.partialFillBeforeReconciliation ||
    AutonomyFaultCode.protectionPlacementRejected ||
    AutonomyFaultCode.protectionPlacementTimeout ||
    AutonomyFaultCode.protectionPlacementAmbiguous ||
    AutonomyFaultCode.takeProfitStopLossOrderingRace ||
    AutonomyFaultCode.externalPositionAppears ||
    AutonomyFaultCode.exchangeAccountCountDivergence ||
    AutonomyFaultCode.historyTemporarilyUnavailable ||
    AutonomyFaultCode.exchangeRateLimitOrTransientServerError =>
      AutonomyFaultCategory.privateExecution,
    AutonomyFaultCode.androidBackgroundForegroundTransition ||
    AutonomyFaultCode.foregroundServiceRestart ||
    AutonomyFaultCode.processDeathAfterReservation ||
    AutonomyFaultCode.processDeathAfterSubmit ||
    AutonomyFaultCode.processDeathAfterFill ||
    AutonomyFaultCode.processDeathAfterProtection ||
    AutonomyFaultCode.processDeathAfterClose ||
    AutonomyFaultCode.databaseWriteInterruption ||
    AutonomyFaultCode.restartDuringStopPromotion ||
    AutonomyFaultCode.appUpdateWithOpenDurableState ||
    AutonomyFaultCode.constrainedMemoryOrCpu ||
    AutonomyFaultCode.networkTransportFlap =>
      AutonomyFaultCategory.processStoragePlatform,
    AutonomyFaultCode.strategyQuarantinedWithOpenPosition ||
    AutonomyFaultCode.driftBreakerTriggered ||
    AutonomyFaultCode.latencyOrSlippageBreakerTriggered ||
    AutonomyFaultCode.drawdownBreakerWithCandidateArrival ||
    AutonomyFaultCode.candidateStaleBetweenRankingAndSubmit ||
    AutonomyFaultCode.policyVersionChangesWithFrozenDecision =>
      AutonomyFaultCategory.strategyAutonomy,
  };
}

@immutable
final class AutonomyFaultCampaignScenario {
  const AutonomyFaultCampaignScenario({
    required this.version,
    required this.seed,
    required this.fault,
    required this.category,
  });

  final String version;
  final int seed;
  final AutonomyFaultCode fault;
  final AutonomyFaultCategory category;

  void validate() {
    if (version.trim().isEmpty || seed < 0) {
      throw const FormatException(
        'Fault campaign scenario requires a version and non-negative seed.',
      );
    }
    if (category != fault.category) {
      throw StateError(
        'Fault campaign scenario category does not match fault.',
      );
    }
  }

  AutonomyFaultScenario toFaultScenario() {
    validate();
    return AutonomyFaultScenario(
      version: version,
      seed: seed,
      category: category,
      faultCode: fault.name,
    );
  }

  Map<String, Object?> toJson() => {
    'version': version,
    'seed': seed,
    'fault': fault.name,
    'category': category.name,
  };
}

@immutable
final class AutonomyFaultCampaignResult {
  AutonomyFaultCampaignResult._({
    required Iterable<AutonomyFaultCampaignScenario> scenarios,
  }) : scenarios = UnmodifiableListView(scenarios.toList(growable: false));

  final UnmodifiableListView<AutonomyFaultCampaignScenario> scenarios;

  int countFor(AutonomyFaultCategory category) {
    return scenarios.where((scenario) => scenario.category == category).length;
  }

  bool get complete => scenarios.length == AutonomyFaultCode.values.length;

  Map<String, Object?> toJson() => {
    'complete': complete,
    'scenarioCount': scenarios.length,
    'categoryCounts': {
      for (final category in AutonomyFaultCategory.values)
        category.name: countFor(category),
    },
    'scenarios': scenarios
        .map((scenario) => scenario.toJson())
        .toList(growable: false),
  };
}

abstract final class AutonomyFaultCampaignGate {
  static AutonomyFaultCampaignResult evaluate({
    required Iterable<AutonomyFaultCampaignScenario> scenarios,
  }) {
    final byFault = <AutonomyFaultCode, AutonomyFaultCampaignScenario>{};
    for (final scenario in scenarios) {
      scenario.validate();
      if (byFault.containsKey(scenario.fault)) {
        throw StateError('Fault campaign must report each fault exactly once.');
      }
      byFault[scenario.fault] = scenario;
    }

    final missing = AutonomyFaultCode.values
        .where((fault) => !byFault.containsKey(fault))
        .toList(growable: false);
    if (missing.isNotEmpty) {
      throw StateError(
        'Fault campaign is incomplete; every required fault must be covered.',
      );
    }

    final ordered = AutonomyFaultCode.values
        .map((fault) => byFault[fault]!)
        .toList(growable: false);
    return AutonomyFaultCampaignResult._(scenarios: ordered);
  }
}
