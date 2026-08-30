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
    final parsedStage = ExchangePositionRecoveryStage.values.firstWhere(
      (item) => item.name == stageName,
      orElse: () => throw const FormatException(
        'Unknown exchange recovery checkpoint stage.',
      ),
    );

    // `riskAdopted` used to be persisted before local managed state committed.
    // Replaying it as `journalCommitted` is intentionally conservative: risk
    // adoption is idempotent, while blindly restoring a managed position after
    // the exchange position disappeared could create phantom local exposure.
    final stage = parsedStage == ExchangePositionRecoveryStage.riskAdopted
        ? ExchangePositionRecoveryStage.journalCommitted
        : parsedStage;
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
/// device-local managed state share one ACID transaction. Journal progress is
/// durably checkpointed; risk adoption is deliberately replayable/idempotent so
/// restart cannot resurrect a position that has already disappeared at the
/// exchange before local managed state commits.
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

    // A legacy/in-memory riskAdopted checkpoint is replayed from the last safe
    // durable boundary. adoptRisk must be idempotent by contract.
    if (current.stage == ExchangePositionRecoveryStage.riskAdopted) {
      current = ExchangePositionRecoveryCheckpoint(
        positionId: current.positionId,
        symbol: current.symbol,
        stage: ExchangePositionRecoveryStage.journalCommitted,
        updatedAtUtc: current.updatedAtUtc,
        managedPlan: current.managedPlan,
        reason: 'Risk adoption will be replayed idempotently after restart.',
      );
    }

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

    // Do not persist a separate riskAdopted checkpoint. If the process dies
    // after this idempotent write, restart replays adoption from the durable
    // journalCommitted boundary and re-verifies current exchange truth first.
    await adoptRisk();

    await commitManaged();
    await persistCheckpoint(null);
    return const ExchangePositionRecoveryTransactionResult(
      completed: true,
      checkpoint: null,
      reason: 'managedStateCommitted',
    );
  }
}
