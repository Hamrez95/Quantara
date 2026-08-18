import 'dart:collection';

import 'package:flutter/foundation.dart';

enum AutonomyRestartCheckpoint {
  reservation,
  submitUnknownOutcome,
  acknowledgement,
  fill,
  protection,
  management,
  close,
}

@immutable
final class AutonomyRestartObservation {
  AutonomyRestartObservation({
    required this.checkpoint,
    required this.recovered,
    required this.idempotent,
    required this.reservationConsistent,
    required this.protectionConsistent,
    this.duplicateSubmitAttempted = false,
    Iterable<String> evidenceIds = const [],
  }) : evidenceIds = UnmodifiableListView(
         evidenceIds.map((value) => value.trim()).toList(growable: false),
       ) {
    if (this.evidenceIds.any((value) => value.isEmpty)) {
      throw const FormatException('Restart evidence IDs cannot be empty.');
    }
    if (!passed && this.evidenceIds.isEmpty) {
      throw const FormatException(
        'A failed restart checkpoint requires at least one evidence ID.',
      );
    }
  }

  final AutonomyRestartCheckpoint checkpoint;
  final bool recovered;
  final bool idempotent;
  final bool reservationConsistent;
  final bool protectionConsistent;
  final bool duplicateSubmitAttempted;
  final UnmodifiableListView<String> evidenceIds;

  bool get passed =>
      recovered &&
      idempotent &&
      reservationConsistent &&
      protectionConsistent &&
      !duplicateSubmitAttempted;

  Map<String, Object?> toJson() => {
    'checkpoint': checkpoint.name,
    'passed': passed,
    'recovered': recovered,
    'idempotent': idempotent,
    'reservationConsistent': reservationConsistent,
    'protectionConsistent': protectionConsistent,
    'duplicateSubmitAttempted': duplicateSubmitAttempted,
    'evidenceIds': evidenceIds.toList(growable: false),
  };
}

@immutable
final class AutonomyRestartCertificationResult {
  AutonomyRestartCertificationResult._({
    required Iterable<AutonomyRestartObservation> observations,
  }) : observations = UnmodifiableListView(
         observations.toList(growable: false),
       );

  final UnmodifiableListView<AutonomyRestartObservation> observations;

  bool get stopShip => observations.any((observation) => !observation.passed);

  bool get promotionEligible => !stopShip;

  List<AutonomyRestartCheckpoint> get failedCheckpoints => List.unmodifiable(
    observations
        .where((observation) => !observation.passed)
        .map((observation) => observation.checkpoint),
  );

  Map<String, Object?> toJson() => {
    'stopShip': stopShip,
    'promotionEligible': promotionEligible,
    'failedCheckpoints': failedCheckpoints
        .map((checkpoint) => checkpoint.name)
        .toList(growable: false),
    'observations': observations
        .map((observation) => observation.toJson())
        .toList(growable: false),
  };
}

abstract final class AutonomyRestartCertificationGate {
  static AutonomyRestartCertificationResult evaluate({
    required Iterable<AutonomyRestartObservation> observations,
  }) {
    final byCheckpoint =
        <AutonomyRestartCheckpoint, AutonomyRestartObservation>{};
    for (final observation in observations) {
      if (byCheckpoint.containsKey(observation.checkpoint)) {
        throw StateError(
          'Restart certification must report each checkpoint exactly once.',
        );
      }
      byCheckpoint[observation.checkpoint] = observation;
    }

    final missing = AutonomyRestartCheckpoint.values
        .where((checkpoint) => !byCheckpoint.containsKey(checkpoint))
        .toList(growable: false);
    if (missing.isNotEmpty) {
      throw StateError(
        'Restart certification is incomplete; every checkpoint is required.',
      );
    }

    final ordered = AutonomyRestartCheckpoint.values
        .map((checkpoint) => byCheckpoint[checkpoint]!)
        .toList(growable: false);
    return AutonomyRestartCertificationResult._(observations: ordered);
  }
}
