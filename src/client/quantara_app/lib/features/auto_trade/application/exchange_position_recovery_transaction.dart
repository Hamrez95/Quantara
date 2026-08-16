enum ExchangePositionRecoveryStage { verified, journalCommitted, riskAdopted }

final class ExchangePositionRecoveryCheckpoint {
  const ExchangePositionRecoveryCheckpoint({
    required this.positionId,
    required this.symbol,
    required this.stage,
    required this.updatedAtUtc,
    required this.managedPlan,
    this.reason = '',
  });

  final String positionId;
  final String symbol;
  final ExchangePositionRecoveryStage stage;
  final DateTime updatedAtUtc;
  final Map<String, Object?> managedPlan;
  final String reason;

  ExchangePositionRecoveryCheckpoint advance(
    ExchangePositionRecoveryStage next, {
    required DateTime atUtc,
    String reason = '',
  }) {
    if (next.index < stage.index) {
      throw StateError('Exchange position recovery cannot move backwards.');
    }
    return ExchangePositionRecoveryCheckpoint(
      positionId: positionId,
      symbol: symbol,
      stage: next,
      updatedAtUtc: atUtc.toUtc(),
      managedPlan: managedPlan,
      reason: reason,
    );
  }

  Map<String, Object?> toJson() => {
    'positionId': positionId,
    'symbol': symbol,
    'stage': stage.name,
    'updatedAtUtc': updatedAtUtc.toUtc().toIso8601String(),
    'managedPlan': managedPlan,
    'reason': reason,
  };

  factory ExchangePositionRecoveryCheckpoint.fromJson(
    Map<String, Object?> json,
  ) {
    final positionId = json['positionId']?.toString().trim() ?? '';
    final symbol = json['symbol']?.toString().trim().toUpperCase() ?? '';
    final stageName = json['stage']?.toString() ?? '';
    final updatedAt = DateTime.tryParse(
      json['updatedAtUtc']?.toString() ?? '',
    )?.toUtc();
    final managedPlanRaw = json['managedPlan'];
    final managedPlan = managedPlanRaw is Map<String, Object?>
        ? Map<String, Object?>.of(managedPlanRaw)
        : managedPlanRaw is Map<Object?, Object?>
        ? managedPlanRaw.map((key, value) => MapEntry(key.toString(), value))
        : const <String, Object?>{};
    if (positionId.isEmpty ||
        symbol.isEmpty ||
        updatedAt == null ||
        managedPlan.isEmpty) {
      throw const FormatException('Invalid exchange recovery checkpoint.');
    }
    final stage = ExchangePositionRecoveryStage.values.firstWhere(
      (item) => item.name == stageName,
      orElse: () => throw const FormatException(
        'Unknown exchange recovery checkpoint stage.',
      ),
    );
    return ExchangePositionRecoveryCheckpoint(
      positionId: positionId,
      symbol: symbol,
      stage: stage,
      updatedAtUtc: updatedAt,
      managedPlan: Map.unmodifiable(managedPlan),
      reason: json['reason']?.toString() ?? '',
    );
  }
}

typedef ExchangeRecoveryJournalCommit = Future<bool> Function();
typedef ExchangeRecoveryRiskAdoption = Future<void> Function();
typedef ExchangeRecoveryManagedCommit = Future<void> Function();
typedef ExchangeRecoveryCheckpointPersist =
    Future<void> Function(ExchangePositionRecoveryCheckpoint? checkpoint);

final class ExchangePositionRecoveryTransactionResult {
  const ExchangePositionRecoveryTransactionResult({
    required this.completed,
    required this.checkpoint,
    required this.reason,
  });

  final bool completed;
  final ExchangePositionRecoveryCheckpoint? checkpoint;
  final String reason;
}

/// Resumes a cross-store recovery without pretending Journal, risk ledger and
/// device-local managed state share one ACID transaction. Each completed stage
/// is persisted before the next side effect. All operations are required to be
/// idempotent, so a process death can safely retry from the last checkpoint.
abstract final class ExchangePositionRecoveryTransaction {
  static Future<ExchangePositionRecoveryTransactionResult> resume({
    required ExchangePositionRecoveryCheckpoint checkpoint,
    required DateTime Function() clock,
    required ExchangeRecoveryJournalCommit commitJournal,
    required ExchangeRecoveryRiskAdoption adoptRisk,
    required ExchangeRecoveryManagedCommit commitManaged,
    required ExchangeRecoveryCheckpointPersist persistCheckpoint,
  }) async {
    var current = checkpoint;

    if (current.stage.index <
        ExchangePositionRecoveryStage.journalCommitted.index) {
      final journalCommitted = await commitJournal();
      if (!journalCommitted) {
        return ExchangePositionRecoveryTransactionResult(
          completed: false,
          checkpoint: current,
          reason: 'journalCommitPending',
        );
      }
      current = current.advance(
        ExchangePositionRecoveryStage.journalCommitted,
        atUtc: clock(),
        reason: 'Recovered journal plan is durable.',
      );
      await persistCheckpoint(current);
    }

    if (current.stage.index < ExchangePositionRecoveryStage.riskAdopted.index) {
      await adoptRisk();
      current = current.advance(
        ExchangePositionRecoveryStage.riskAdopted,
        atUtc: clock(),
        reason: 'Exchange-confirmed open risk is durable.',
      );
      await persistCheckpoint(current);
    }

    await commitManaged();
    await persistCheckpoint(null);
    return const ExchangePositionRecoveryTransactionResult(
      completed: true,
      checkpoint: null,
      reason: 'managedStateCommitted',
    );
  }
}
