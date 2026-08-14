import 'supervisor_evidence_ledger.dart';
import 'supervisor_observability_coverage.dart';
import 'supervisor_safe_text.dart';
import 'supervisor_system_evidence.dart';

/// Deterministic, sanitized payload boundary for system-wide AI review.
/// Only evidence already admitted to the bounded Supervisor ledger is emitted.
final class SupervisorSystemBundle {
  SupervisorSystemBundle({
    required this.bundleId,
    required DateTime capturedAtUtc,
    required SupervisorEvidenceLedger ledger,
  }) : capturedAtUtc = capturedAtUtc.toUtc(),
       evidence = List<SupervisorSystemEvidence>.unmodifiable(
         ledger.snapshot(),
       );

  static const String schemaVersion = '1';

  final String bundleId;
  final DateTime capturedAtUtc;
  final List<SupervisorSystemEvidence> evidence;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'bundleId': SupervisorSafeText.sanitize(bundleId),
    'capturedAtUtc': capturedAtUtc.toIso8601String(),
    'coverage': SupervisorObservabilityCoverage.toJson(),
    'evidence': evidence.map((entry) => entry.toJson()).toList(growable: false),
  };
}
