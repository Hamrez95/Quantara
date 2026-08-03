import '../domain/owner_alpha_models.dart';

enum SignalTimeframePriorityKind { primary, secondary, conflict }

abstract final class SignalTimeframePriorityResolver {
  static Map<String, SignalTimeframePriorityKind> resolve(
    Iterable<SignalJournalEntry> entries, {
    required DateTime now,
  }) {
    final active = entries.where((entry) {
      if (entry.closed || entry.hasTerminalOutcome) return false;
      if (entry.outcome == SignalOutcome.pendingEntry &&
          !now.toUtc().isBefore(entry.validUntil)) {
        return false;
      }
      return true;
    });
    final grouped = <String, List<SignalJournalEntry>>{};
    for (final entry in active) {
      grouped.putIfAbsent(entry.symbol, () => []).add(entry);
    }

    final result = <String, SignalTimeframePriorityKind>{};
    for (final group in grouped.values) {
      final directions = group.map((entry) => entry.direction).toSet();
      if (directions.length > 1) {
        for (final entry in group) {
          result[entry.setupId] = SignalTimeframePriorityKind.conflict;
        }
        continue;
      }

      final primary = _pickPrimary(group);
      for (final entry in group) {
        result[entry.setupId] = identical(entry, primary)
            ? SignalTimeframePriorityKind.primary
            : SignalTimeframePriorityKind.secondary;
      }
    }
    return Map.unmodifiable(result);
  }

  static SignalJournalEntry _pickPrimary(List<SignalJournalEntry> group) {
    final hasFourHour = group.any((entry) => entry.timeframe == '4h');
    final preferredTimeframe =
        hasFourHour && group.any((entry) => entry.timeframe == '1h')
        ? '1h'
        : group.any((entry) => entry.timeframe == '4h')
        ? '4h'
        : group.any((entry) => entry.timeframe == '1h')
        ? '1h'
        : group.any((entry) => entry.timeframe == '15m')
        ? '15m'
        : group.any((entry) => entry.timeframe == '5m')
        ? '5m'
        : group.any((entry) => entry.timeframe == '1D')
        ? '1D'
        : group.first.timeframe;
    final candidates =
        group
            .where((entry) => entry.timeframe == preferredTimeframe)
            .toList(growable: false)
          ..sort((left, right) => right.createdAt.compareTo(left.createdAt));
    return candidates.first;
  }
}
