import 'supervisor_system_evidence.dart';

/// Small bounded in-memory ledger for Supervisor evidence.
///
/// Persistence adapters can sit behind this contract later; the domain layer
/// already enforces bounded retention and deterministic snapshots so review
/// bundles cannot grow without limit.
final class SupervisorEvidenceLedger {
  SupervisorEvidenceLedger({
    this.maxEntries = 500,
    this.maxAge = const Duration(days: 7),
  }) : assert(maxEntries > 0);

  final int maxEntries;
  final Duration maxAge;
  final List<SupervisorSystemEvidence> _entries = <SupervisorSystemEvidence>[];

  int get length => _entries.length;

  void record(SupervisorSystemEvidence evidence, {DateTime? nowUtc}) {
    _entries.add(evidence);
    _prune((nowUtc ?? DateTime.now().toUtc()).toUtc());
  }

  void recordAll(
    Iterable<SupervisorSystemEvidence> evidence, {
    DateTime? nowUtc,
  }) {
    _entries.addAll(evidence);
    _prune((nowUtc ?? DateTime.now().toUtc()).toUtc());
  }

  List<SupervisorSystemEvidence> snapshot() {
    final copy = List<SupervisorSystemEvidence>.of(_entries);
    copy.sort((left, right) {
      final time = left.observedAtUtc.compareTo(right.observedAtUtc);
      if (time != 0) return time;
      return left.evidenceId.compareTo(right.evidenceId);
    });
    return List.unmodifiable(copy);
  }

  List<SupervisorSystemEvidence> byCorrelationId(String correlationId) =>
      List.unmodifiable(
        snapshot().where((entry) => entry.correlationId == correlationId),
      );

  void _prune(DateTime nowUtc) {
    final cutoff = nowUtc.subtract(maxAge);
    _entries.removeWhere(
      (entry) => entry.observedAtUtc.toUtc().isBefore(cutoff),
    );

    if (_entries.length <= maxEntries) return;

    _entries.sort((left, right) {
      final time = left.observedAtUtc.compareTo(right.observedAtUtc);
      if (time != 0) return time;
      return left.evidenceId.compareTo(right.evidenceId);
    });
    _entries.removeRange(0, _entries.length - maxEntries);
  }
}
