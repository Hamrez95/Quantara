import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:quantara_app/features/autonomy/domain/autonomy_soak_certification.dart';

enum ReleaseGateCode {
  flutterQuality,
  backendContract,
  replayDeterminism,
  faultInjectionAndRiskProperties,
  androidPwaBuild,
  performanceSlo,
  diagnosticsExport,
  criticalAlerts,
  rollbackPlan,
  strategyFeatureFlags,
  botFeatureFlags,
  samsungPhysicalQa,
  realtimeShadow14Day,
  permanentSigning,
  tinyRiskCanary,
  upgradeRetention,
}

enum ReleaseGateStatus { pending, passed, failed }

extension ReleaseGateCodeMetadata on ReleaseGateCode {
  bool get physicalOrOwnerGate => switch (this) {
    ReleaseGateCode.samsungPhysicalQa ||
    ReleaseGateCode.realtimeShadow14Day ||
    ReleaseGateCode.permanentSigning ||
    ReleaseGateCode.tinyRiskCanary ||
    ReleaseGateCode.upgradeRetention => true,
    _ => false,
  };
}

@immutable
final class ReleaseGateEvidence {
  ReleaseGateEvidence({
    required this.code,
    required this.status,
    Iterable<String> evidenceIds = const [],
  }) : evidenceIds = UnmodifiableListView(
         evidenceIds.map((value) => value.trim()).toList(growable: false),
       ) {
    if (this.evidenceIds.any((value) => value.isEmpty)) {
      throw const FormatException('Release evidence IDs cannot be empty.');
    }
    if (status != ReleaseGateStatus.pending && this.evidenceIds.isEmpty) {
      throw const FormatException(
        'Passed and failed release gates require explicit evidence IDs.',
      );
    }
  }

  final ReleaseGateCode code;
  final ReleaseGateStatus status;
  final UnmodifiableListView<String> evidenceIds;

  bool get passed => status == ReleaseGateStatus.passed;

  bool get failed => status == ReleaseGateStatus.failed;

  Map<String, Object?> toJson() => {
    'code': code.name,
    'status': status.name,
    'physicalOrOwnerGate': code.physicalOrOwnerGate,
    'evidenceIds': evidenceIds.toList(growable: false),
  };
}

@immutable
final class ReleaseCertificationArtifact {
  ReleaseCertificationArtifact._({
    required this.buildCommit,
    required this.releaseVersion,
    required this.autonomySoak,
    required Iterable<ReleaseGateEvidence> gates,
  }) : gates = UnmodifiableListView(gates.toList(growable: false));

  static const requiredRealtimeShadow = Duration(days: 14);

  final String buildCommit;
  final String releaseVersion;
  final AutonomySoakCertificationResult autonomySoak;
  final UnmodifiableListView<ReleaseGateEvidence> gates;

  ReleaseGateEvidence gate(ReleaseGateCode code) {
    return gates.firstWhere((value) => value.code == code);
  }

  Duration get recordedShadowDuration {
    final seconds = autonomySoak.runs
        .where((run) => run.phase == AutonomySoakPhase.shadow)
        .fold<int>(0, (total, run) => total + run.metrics.elapsedSeconds);
    return Duration(seconds: seconds);
  }

  bool get shadowDurationSatisfied =>
      recordedShadowDuration >= requiredRealtimeShadow;

  bool get stopShip =>
      autonomySoak.stopShip || gates.any((evidence) => evidence.failed);

  bool get allReleaseGatesPassed => gates.every((evidence) => evidence.passed);

  bool get stableEligible =>
      autonomySoak.promotionEligible &&
      shadowDurationSatisfied &&
      allReleaseGatesPassed &&
      !stopShip;

  bool get physicalEvidenceComplete => gates
      .where((evidence) => evidence.code.physicalOrOwnerGate)
      .every((evidence) => evidence.passed);

  List<ReleaseGateCode> get pendingGates => List.unmodifiable(
    gates
        .where((evidence) => evidence.status == ReleaseGateStatus.pending)
        .map((evidence) => evidence.code),
  );

  List<ReleaseGateCode> get failedGates => List.unmodifiable(
    gates.where((evidence) => evidence.failed).map((evidence) => evidence.code),
  );

  Map<String, Object?> toJson() => {
    'buildCommit': buildCommit,
    'releaseVersion': releaseVersion,
    'autonomySoak': autonomySoak.toJson(),
    'requiredRealtimeShadowSeconds': requiredRealtimeShadow.inSeconds,
    'recordedShadowSeconds': recordedShadowDuration.inSeconds,
    'shadowDurationSatisfied': shadowDurationSatisfied,
    'physicalEvidenceComplete': physicalEvidenceComplete,
    'stopShip': stopShip,
    'stableEligible': stableEligible,
    'pendingGates': pendingGates.map((gate) => gate.name).toList(growable: false),
    'failedGates': failedGates.map((gate) => gate.name).toList(growable: false),
    'gates': gates.map((gate) => gate.toJson()).toList(growable: false),
  };
}

abstract final class ReleaseCertificationGate {
  static ReleaseCertificationArtifact evaluate({
    required String buildCommit,
    required String releaseVersion,
    required AutonomySoakCertificationResult autonomySoak,
    required Iterable<ReleaseGateEvidence> gates,
  }) {
    if (buildCommit.trim().isEmpty || releaseVersion.trim().isEmpty) {
      throw const FormatException(
        'Release certification requires build and release versions.',
      );
    }

    final byCode = <ReleaseGateCode, ReleaseGateEvidence>{};
    for (final evidence in gates) {
      if (byCode.containsKey(evidence.code)) {
        throw StateError('Release certification must report each gate once.');
      }
      byCode[evidence.code] = evidence;
    }

    final missing = ReleaseGateCode.values
        .where((code) => !byCode.containsKey(code))
        .toList(growable: false);
    if (missing.isNotEmpty) {
      throw StateError(
        'Release certification is incomplete; every gate is required.',
      );
    }

    final ordered = ReleaseGateCode.values
        .map((code) => byCode[code]!)
        .toList(growable: false);
    final artifact = ReleaseCertificationArtifact._(
      buildCommit: buildCommit.trim(),
      releaseVersion: releaseVersion.trim(),
      autonomySoak: autonomySoak,
      gates: ordered,
    );

    _validateCanaryOrdering(artifact);
    return artifact;
  }

  static void _validateCanaryOrdering(ReleaseCertificationArtifact artifact) {
    final canary = artifact.gate(ReleaseGateCode.tinyRiskCanary);
    if (!canary.passed) {
      return;
    }

    final signing = artifact.gate(ReleaseGateCode.permanentSigning);
    final shadow = artifact.gate(ReleaseGateCode.realtimeShadow14Day);
    if (!signing.passed || !shadow.passed || !artifact.shadowDurationSatisfied) {
      throw StateError(
        'Tiny-risk canary evidence is invalid before signing and 14-day shadow.',
      );
    }
  }
}
