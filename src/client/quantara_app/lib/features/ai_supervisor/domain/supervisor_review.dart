import 'supervisor_safe_text.dart';

enum SupervisorFindingKind {
  observedFact,
  hypothesis,
  riskObservation,
  recommendation,
}

final class SupervisorEvidenceRef {
  const SupervisorEvidenceRef({required this.id, required this.source});

  final String id;
  final String source;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': SupervisorSafeText.sanitize(id),
    'source': SupervisorSafeText.sanitize(source),
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
    'summary': SupervisorSafeText.sanitize(summary),
    'confidence': confidence,
    'evidence': evidence.map((item) => item.toJson()).toList(growable: false),
    'validationTests': validationTests
        .map(SupervisorSafeText.sanitize)
        .toList(growable: false),
    'rollbackCriteria': rollbackCriteria
        .map(SupervisorSafeText.sanitize)
        .toList(growable: false),
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
    'reviewId': SupervisorSafeText.sanitize(reviewId),
    'snapshotSchemaVersion': SupervisorSafeText.sanitize(
      snapshotSchemaVersion,
    ),
    'findings': findings.map((item) => item.toJson()).toList(growable: false),
    if (insufficientEvidenceReason != null)
      'insufficientEvidenceReason': SupervisorSafeText.sanitize(
        insufficientEvidenceReason!,
      ),
  };
}
