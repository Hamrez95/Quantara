import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/auto_trade/application/exchange_position_recovery_transaction.dart';

void main() {
  final first = DateTime.utc(2026, 8, 16, 10);

  ExchangePositionRecoveryCheckpoint checkpoint({
    ExchangePositionRecoveryStage stage =
        ExchangePositionRecoveryStage.verified,
  }) => ExchangePositionRecoveryCheckpoint(
    positionId: 'p-1',
    symbol: 'XRPUSDT',
    stage: stage,
    updatedAtUtc: first,
    managedPlan: const {'positionId': 'p-1', 'symbol': 'XRPUSDT'},
  );

  test('checkpoint serialization is stable and cannot regress', () {
    final value = checkpoint().advance(
      ExchangePositionRecoveryStage.journalCommitted,
      atUtc: first.add(const Duration(seconds: 1)),
    );
    final restored = ExchangePositionRecoveryCheckpoint.fromJson(
      value.toJson(),
    );

    expect(restored.positionId, 'p-1');
    expect(restored.symbol, 'XRPUSDT');
    expect(restored.stage, ExchangePositionRecoveryStage.journalCommitted);
    expect(
      () => restored.advance(
        ExchangePositionRecoveryStage.verified,
        atUtc: first,
      ),
      throwsStateError,
    );
  });

  test(
    'journal failure leaves verified checkpoint and skips later stores',
    () async {
      var riskCalls = 0;
      var managedCalls = 0;
      final persisted = <ExchangePositionRecoveryCheckpoint?>[];

      final result = await ExchangePositionRecoveryTransaction.resume(
        checkpoint: checkpoint(),
        clock: () => first,
        commitJournal: () async => false,
        adoptRisk: () async => riskCalls++,
        commitManaged: () async => managedCalls++,
        persistCheckpoint: (value) async => persisted.add(value),
      );

      expect(result.completed, isFalse);
      expect(result.reason, 'journalCommitPending');
      expect(result.checkpoint?.stage, ExchangePositionRecoveryStage.verified);
      expect(riskCalls, 0);
      expect(managedCalls, 0);
      expect(persisted, isEmpty);
    },
  );

  test('risk failure persists journal stage and retry skips journal', () async {
    var journalCalls = 0;
    var riskCalls = 0;
    var managedCalls = 0;
    final persisted = <ExchangePositionRecoveryCheckpoint?>[];
    ExchangePositionRecoveryCheckpoint? durable = checkpoint();

    Future<void> persist(ExchangePositionRecoveryCheckpoint? value) async {
      durable = value;
      persisted.add(value);
    }

    await expectLater(
      ExchangePositionRecoveryTransaction.resume(
        checkpoint: durable!,
        clock: () => first.add(const Duration(seconds: 1)),
        commitJournal: () async {
          journalCalls++;
          return true;
        },
        adoptRisk: () async {
          riskCalls++;
          throw StateError('risk store unavailable');
        },
        commitManaged: () async => managedCalls++,
        persistCheckpoint: persist,
      ),
      throwsStateError,
    );

    expect(journalCalls, 1);
    expect(riskCalls, 1);
    expect(managedCalls, 0);
    expect(durable?.stage, ExchangePositionRecoveryStage.journalCommitted);

    final result = await ExchangePositionRecoveryTransaction.resume(
      checkpoint: durable!,
      clock: () => first.add(const Duration(seconds: 2)),
      commitJournal: () async {
        journalCalls++;
        return true;
      },
      adoptRisk: () async => riskCalls++,
      commitManaged: () async => managedCalls++,
      persistCheckpoint: persist,
    );

    expect(result.completed, isTrue);
    expect(journalCalls, 1, reason: 'durable journal stage must not replay');
    expect(riskCalls, 2);
    expect(managedCalls, 1);
    expect(durable, isNull);
    expect(persisted.last, isNull);
  });

  test(
    'risk-adopted retry commits only managed state then clears checkpoint',
    () async {
      var journalCalls = 0;
      var riskCalls = 0;
      var managedCalls = 0;
      ExchangePositionRecoveryCheckpoint? durable = checkpoint(
        stage: ExchangePositionRecoveryStage.riskAdopted,
      );

      final result = await ExchangePositionRecoveryTransaction.resume(
        checkpoint: durable,
        clock: () => first,
        commitJournal: () async {
          journalCalls++;
          return true;
        },
        adoptRisk: () async => riskCalls++,
        commitManaged: () async => managedCalls++,
        persistCheckpoint: (value) async => durable = value,
      );

      expect(result.completed, isTrue);
      expect(journalCalls, 0);
      expect(riskCalls, 0);
      expect(managedCalls, 1);
      expect(durable, isNull);
    },
  );
}
