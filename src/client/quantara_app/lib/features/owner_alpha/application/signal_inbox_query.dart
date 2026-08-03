import '../domain/owner_alpha_models.dart';

enum SignalInboxFilter { all, opportunities, active, results, expired, taken }

enum SignalInboxSort { recommended, score, expiringSoon, newest, latestResult }

abstract final class SignalInboxQuery {
  static List<SignalJournalEntry> apply({
    required Iterable<SignalJournalEntry> entries,
    required SignalInboxFilter filter,
    required SignalInboxSort sort,
    required DateTime now,
    required bool Function(String setupId) isTaken,
  }) {
    final utcNow = now.toUtc();
    final result = entries
        .where((entry) {
          final taken = isTaken(entry.setupId);
          return switch (filter) {
            SignalInboxFilter.all => true,
            SignalInboxFilter.opportunities => isOpenOpportunity(
              entry,
              now: utcNow,
              taken: taken,
            ),
            SignalInboxFilter.active => isActive(entry),
            SignalInboxFilter.results => hasVisibleResult(entry),
            SignalInboxFilter.expired => isExpired(entry, now: utcNow),
            SignalInboxFilter.taken => taken,
          };
        })
        .toList(growable: false);
    result.sort(
      (left, right) =>
          _compare(left, right, sort: sort, now: utcNow, isTaken: isTaken),
    );
    return result;
  }

  static int count({
    required Iterable<SignalJournalEntry> entries,
    required SignalInboxFilter filter,
    required DateTime now,
    required bool Function(String setupId) isTaken,
  }) => apply(
    entries: entries,
    filter: filter,
    sort: SignalInboxSort.recommended,
    now: now,
    isTaken: isTaken,
  ).length;

  static bool isOpenOpportunity(
    SignalJournalEntry entry, {
    required DateTime now,
    required bool taken,
  }) =>
      !taken &&
      !entry.closed &&
      entry.outcome == SignalOutcome.pendingEntry &&
      now.toUtc().isBefore(entry.validUntil);

  static bool isActive(SignalJournalEntry entry) =>
      !entry.closed &&
      (entry.outcome == SignalOutcome.active ||
          entry.outcome == SignalOutcome.tp1 ||
          entry.outcome == SignalOutcome.tp2);

  static bool hasVisibleResult(SignalJournalEntry entry) =>
      entry.outcome == SignalOutcome.stopped ||
      entry.outcome == SignalOutcome.tp1 ||
      entry.outcome == SignalOutcome.tp2 ||
      entry.outcome == SignalOutcome.tp3;

  static bool isExpired(SignalJournalEntry entry, {required DateTime now}) =>
      entry.outcome == SignalOutcome.expiredUntriggered ||
      entry.outcome == SignalOutcome.pendingEntry &&
          !now.toUtc().isBefore(entry.validUntil);

  static int _compare(
    SignalJournalEntry left,
    SignalJournalEntry right, {
    required SignalInboxSort sort,
    required DateTime now,
    required bool Function(String setupId) isTaken,
  }) {
    final result = switch (sort) {
      SignalInboxSort.recommended => _recommended(
        left,
        right,
        now: now,
        isTaken: isTaken,
      ),
      SignalInboxSort.score => _score(left, right),
      SignalInboxSort.expiringSoon => _expiringSoon(left, right, now: now),
      SignalInboxSort.newest => right.createdAt.compareTo(left.createdAt),
      SignalInboxSort.latestResult => _latestResult(left, right),
    };
    return result != 0 ? result : left.setupId.compareTo(right.setupId);
  }

  static int _recommended(
    SignalJournalEntry left,
    SignalJournalEntry right, {
    required DateTime now,
    required bool Function(String setupId) isTaken,
  }) {
    final leftBucket = _recommendedBucket(
      left,
      now: now,
      taken: isTaken(left.setupId),
    );
    final rightBucket = _recommendedBucket(
      right,
      now: now,
      taken: isTaken(right.setupId),
    );
    final bucket = leftBucket.compareTo(rightBucket);
    if (bucket != 0) return bucket;
    final score = _score(left, right);
    if (score != 0) return score;
    if (leftBucket == 0) return left.validUntil.compareTo(right.validUntil);
    return right.createdAt.compareTo(left.createdAt);
  }

  static int _recommendedBucket(
    SignalJournalEntry entry, {
    required DateTime now,
    required bool taken,
  }) {
    if (isOpenOpportunity(entry, now: now, taken: taken)) return 0;
    if (isActive(entry)) return 1;
    if (taken) return 2;
    if (hasVisibleResult(entry)) return 3;
    if (isExpired(entry, now: now)) return 4;
    return 5;
  }

  static int _score(SignalJournalEntry left, SignalJournalEntry right) {
    final confidence = right.confidencePercent.compareTo(
      left.confidencePercent,
    );
    if (confidence != 0) return confidence;
    final rewardRisk = (right.riskReward ?? 0).compareTo(left.riskReward ?? 0);
    if (rewardRisk != 0) return rewardRisk;
    return right.createdAt.compareTo(left.createdAt);
  }

  static int _expiringSoon(
    SignalJournalEntry left,
    SignalJournalEntry right, {
    required DateTime now,
  }) {
    final leftLive =
        left.outcome == SignalOutcome.pendingEntry &&
        now.isBefore(left.validUntil);
    final rightLive =
        right.outcome == SignalOutcome.pendingEntry &&
        now.isBefore(right.validUntil);
    if (leftLive != rightLive) return leftLive ? -1 : 1;
    if (leftLive) {
      final expiry = left.validUntil.compareTo(right.validUntil);
      if (expiry != 0) return expiry;
    }
    return _score(left, right);
  }

  static int _latestResult(SignalJournalEntry left, SignalJournalEntry right) {
    final leftResult = hasVisibleResult(left);
    final rightResult = hasVisibleResult(right);
    if (leftResult != rightResult) return leftResult ? -1 : 1;
    final leftAt = left.resolvedAt ?? left.createdAt;
    final rightAt = right.resolvedAt ?? right.createdAt;
    return rightAt.compareTo(leftAt);
  }
}
