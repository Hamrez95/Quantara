import 'supervisor_evidence_ledger.dart';
import 'supervisor_observability_coverage.dart';
import 'supervisor_safe_text.dart';

/// Deterministic, sanitized payload boundary for system-wide AI review.
final class SupervisorSystemBundle {
  SupervisorSystemBundle({
    required this.bundleId,
    required DateTime capturedAtUtc,
    required SupervisorEvidenceLedger ledger,
  }) : capturedAtUtc = capturedAtUtc.toUtc(),
       evidence = List.unmodifiable(ledger.snapshot());

  static const String schemaVersion = '1';

  final String bundleId;
  final DateTime capturedAtUtc;
  final List<dynamic> evidence;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'bundleId': SupervisorSafeText.sanitize(bundleId),
    'capturedAtUtc': capturedAtUtc.toIso8601String(),
    'coverage': SupervisorObservabilityCoverage.toJson(),
    'evidence': evidence
        .map((entry) => (entry as dynamic).toJson())
        .toList(growable: false),
  };
}
