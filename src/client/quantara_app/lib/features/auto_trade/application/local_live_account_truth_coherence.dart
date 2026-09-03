import '../domain/auto_trade_models.dart';

final class LocalLiveAccountTruthRecord {
  const LocalLiveAccountTruthRecord({
    required this.account,
    required this.reconciliationGeneration,
    required this.reconciliationCompletedAtUtc,
    required this.publishedAtUtc,
  });

  final AutoTradeAccountSnapshot account;
  final int reconciliationGeneration;
  final DateTime reconciliationCompletedAtUtc;
  final DateTime publishedAtUtc;
}

final class LocalLiveAccountTruthResolution {
  const LocalLiveAccountTruthResolution({
    required this.account,
    required this.reconciliationGeneration,
    required this.reconciliationCompletedAtUtc,
    required this.refreshAttempted,
    required this.refreshResult,
    required this.recoveredFromStaleFallback,
  });

  final AutoTradeAccountSnapshot account;
  final int? reconciliationGeneration;
  final DateTime? reconciliationCompletedAtUtc;
  final bool refreshAttempted;
  final String refreshResult;
  final bool recoveredFromStaleFallback;
}

/// Process-local handoff between authenticated private-account truth and the
/// atomic portfolio admission layer.
///
/// Only a successfully reconciled, entry-admissible private-truth projection is
/// published. Reconnect/stale/ambiguous states invalidate the record. The
/// portfolio layer may therefore refresh a stale scan-time account snapshot
/// without issuing a second REST read or bypassing the freshness gate.
abstract final class LocalLiveAccountTruthCoherence {
  static LocalLiveAccountTruthRecord? _latest;

  static LocalLiveAccountTruthRecord? get latest => _latest;

  static void publish(LocalLiveAccountTruthRecord record) {
    final current = _latest;
    if (current != null) {
      if (record.reconciliationGeneration < current.reconciliationGeneration) {
        return;
      }
      if (record.reconciliationGeneration == current.reconciliationGeneration &&
          record.account.syncedAt.toUtc().isBefore(
            current.account.syncedAt.toUtc(),
          )) {
        return;
      }
    }
    _latest = record;
  }

  static void invalidate() {
    _latest = null;
  }

  static LocalLiveAccountTruthResolution resolve({
    required AutoTradeAccountSnapshot fallback,
    required DateTime observedAtUtc,
    required Duration freshnessWindow,
  }) {
    final observedAt = observedAtUtc.toUtc();
    bool isFresh(DateTime asOf) {
      final utc = asOf.toUtc();
      if (utc.isAfter(observedAt)) return false;
      return observedAt.difference(utc) <= freshnessWindow;
    }

    final fallbackFresh = isFresh(fallback.syncedAt);
    final latest = _latest;
    if (latest == null) {
      return LocalLiveAccountTruthResolution(
        account: fallback,
        reconciliationGeneration: null,
        reconciliationCompletedAtUtc: null,
        refreshAttempted: !fallbackFresh,
        refreshResult: fallbackFresh
            ? 'fallback_current'
            : 'no_reconciled_truth',
        recoveredFromStaleFallback: false,
      );
    }

    final candidate = latest.account;
    final candidateAsOf = candidate.syncedAt.toUtc();
    final fallbackAsOf = fallback.syncedAt.toUtc();
    final candidateFresh = isFresh(candidateAsOf);
    final candidateNotOlder = !candidateAsOf.isBefore(fallbackAsOf);
    if (candidateFresh && candidateNotOlder) {
      return LocalLiveAccountTruthResolution(
        account: candidate,
        reconciliationGeneration: latest.reconciliationGeneration,
        reconciliationCompletedAtUtc: latest.reconciliationCompletedAtUtc,
        refreshAttempted: !fallbackFresh,
        refreshResult: candidateAsOf.isAfter(fallbackAsOf)
            ? 'coherent_reconciled_truth_used'
            : 'coherent_generation_confirmed',
        recoveredFromStaleFallback: !fallbackFresh,
      );
    }

    return LocalLiveAccountTruthResolution(
      account: fallback,
      reconciliationGeneration: latest.reconciliationGeneration,
      reconciliationCompletedAtUtc: latest.reconciliationCompletedAtUtc,
      refreshAttempted: !fallbackFresh,
      refreshResult: candidateFresh
          ? 'reconciled_truth_older_than_fallback'
          : 'reconciled_truth_stale',
      recoveredFromStaleFallback: false,
    );
  }

  static void resetForTest() => invalidate();
}
