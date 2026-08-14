enum SupervisorFindingKind {
  observedFact,
  hypothesis,
  riskObservation,
  recommendation,
}

final class SupervisorEvidenceRef {
  const SupervisorEvidenceRef({
    required this.id,
    required this.source,
  });

  final String id;
  final String source;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'source': source,
  };
}

final class SupervisorFinding {
  SupervisorFinding({
    required this.kind,
    required this.summary,
    required this.confidence,
    List<SupervisorEvidenceRef> evidence = const [],
    List<String> validationTests = const [],
    List<String> rollbackCriteria = const [],
  }) : assert(confidence >= 0 && confidence <= 1),
       evidence = List.unmodifiable(evidence),
       validationTests = List.unmodifiable(validationTests),
       rollbackCriteria = List.unmodifiable(rollbackCriteria);

  final SupervisorFindingKind kind;
  final String summary;
  final double confidence;
  final List<SupervisorEvidenceRef> evidence;
  final List<String> validationTests;
  final List<String> rollbackCriteria;

  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind.name,
    'summary': summary,
    'confidence': confidence,
    'evidence': evidence.map((item) => item.toJson()).toList(growable: false),
    'validationTests': validationTests,
    'rollbackCriteria': rollbackCriteria,
  };
}

final class SupervisorReview {
  SupervisorReview({
    required DateTime generatedAtUtc,
    required this.reviewId,
    required this.snapshotSchemaVersion,
    List<SupervisorFinding> findings = const [],
    this.insufficientEvidenceReason,
  }) : generatedAtUtc = generatedAtUtc.toUtc(),
       findings = List.unmodifiable(findings);

  static const String schemaVersion = '1';

  final DateTime generatedAtUtc;
  final String reviewId;
  final String snapshotSchemaVersion;
  final List<SupervisorFinding> findings;
  final String? insufficientEvidenceReason;

  bool get hasSufficientEvidence => insufficientEvidenceReason == null;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'generatedAtUtc': generatedAtUtc.toIso8601String(),
    'reviewId': reviewId,
    'snapshotSchemaVersion': snapshotSchemaVersion,
    'findings': findings.map((item) => item.toJson()).toList(growable: false),
    if (insufficientEvidenceReason != null)
      'insufficientEvidenceReason': insufficientEvidenceReason,
  };
}
