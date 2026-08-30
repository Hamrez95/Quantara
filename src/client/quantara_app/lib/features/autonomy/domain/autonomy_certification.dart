import 'dart:collection';

import 'package:flutter/foundation.dart';

enum AutonomyFaultCategory {
  marketPublic,
  privateExecution,
  processStoragePlatform,
  strategyAutonomy,
}

enum AutonomyStopShipInvariant {
  duplicateLiveOrder,
  riskDoubleSpend,
  marginDoubleSpend,
  staleOrAmbiguousEntry,
  unprotectedOwnedExposure,
  wrongSideStopAccepted,
  stopWidening,
  forbiddenFinancialAuthority,
  confirmedEconomicTruthLossOrDoubleCount,
  ambiguousMutationReleasedRisk,
}

@immutable
final class AutonomyFaultScenario {
  const AutonomyFaultScenario({
    required this.version,
    required this.seed,
    required this.category,
    required this.faultCode,
  });

  final String version;
  final int seed;
  final AutonomyFaultCategory category;
  final String faultCode;

  void validate() {
    if (version.trim().isEmpty || faultCode.trim().isEmpty || seed < 0) {
      throw const FormatException(
        'Fault scenario requires a version, non-negative seed, and fault code.',
      );
    }
  }

  Map<String, Object?> toJson() => {
    'version': version,
    'seed': seed,
    'category': category.name,
    'faultCode': faultCode,
  };
}

@immutable
final class AutonomyInvariantObservation {
  AutonomyInvariantObservation({
    required this.invariant,
    required this.passed,
    Iterable<String> evidenceIds = const [],
  }) : evidenceIds = UnmodifiableListView(
         evidenceIds.map((value) => value.trim()).toList(growable: false),
       ) {
    if (this.evidenceIds.any((value) => value.isEmpty)) {
      throw const FormatException(
        'Certification evidence IDs cannot be empty.',
      );
    }
    if (!passed && this.evidenceIds.isEmpty) {
      throw const FormatException(
        'A failed stop-ship invariant requires at least one evidence ID.',
      );
    }
  }

  final AutonomyStopShipInvariant invariant;
  final bool passed;
  final UnmodifiableListView<String> evidenceIds;

  Map<String, Object?> toJson() => {
    'invariant': invariant.name,
    'passed': passed,
    'evidenceIds': evidenceIds.toList(growable: false),
  };
}

@immutable
final class AutonomyCertificationResult {
  AutonomyCertificationResult._({
    required this.scenario,
    required Iterable<AutonomyInvariantObservation> observations,
  }) : observations = UnmodifiableListView(
         observations.toList(growable: false),
       );

  final AutonomyFaultScenario scenario;
  final UnmodifiableListView<AutonomyInvariantObservation> observations;

  bool get stopShip => observations.any((observation) => !observation.passed);

  bool get promotionEligible => !stopShip;

  List<AutonomyStopShipInvariant> get failedInvariants => List.unmodifiable(
    observations
        .where((observation) => !observation.passed)
        .map((observation) => observation.invariant),
  );

  Map<String, Object?> toJson() => {
    'scenario': scenario.toJson(),
    'stopShip': stopShip,
    'promotionEligible': promotionEligible,
    'failedInvariants': failedInvariants.map((value) => value.name).toList(),
    'observations': observations
        .map((observation) => observation.toJson())
        .toList(growable: false),
  };
}

abstract final class AutonomyCertificationGate {
  static AutonomyCertificationResult evaluate({
    required AutonomyFaultScenario scenario,
    required Iterable<AutonomyInvariantObservation> observations,
  }) {
    scenario.validate();
    final byInvariant =
        <AutonomyStopShipInvariant, AutonomyInvariantObservation>{};
    for (final observation in observations) {
      if (byInvariant.containsKey(observation.invariant)) {
        throw StateError(
          'Certification must report each stop-ship invariant exactly once.',
        );
      }
      byInvariant[observation.invariant] = observation;
    }

    final missing = AutonomyStopShipInvariant.values
        .where((invariant) => !byInvariant.containsKey(invariant))
        .toList(growable: false);
    if (missing.isNotEmpty) {
      throw StateError(
        'Certification is incomplete; every stop-ship invariant is required.',
      );
    }

    final ordered = AutonomyStopShipInvariant.values
        .map((invariant) => byInvariant[invariant]!)
        .toList(growable: false);
    return AutonomyCertificationResult._(
      scenario: scenario,
      observations: ordered,
    );
  }
}
