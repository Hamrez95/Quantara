import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/auto_trade/domain/local_live_trade_models.dart';

void main() {
  test(
    'Local Live status preserves recoverable and external ownership states',
    () {
      final now = DateTime.utc(2026, 8, 16, 12);
      final status = LocalLiveTradeStatus(
        state: LocalLiveTradeState.managingOnly,
        updatedAt: now,
        message: 'recovery',
        openPositionCount: 2,
        managedPositionCount: 0,
        unmanagedPositionCount: 2,
        unmanagedSymbols: const ['XRPUSDT', 'ETHUSDT'],
        recoverableOrphanCount: 1,
        recoverableOrphanSymbols: const ['XRPUSDT'],
        externalUnmanagedPositionCount: 1,
        externalUnmanagedSymbols: const ['ETHUSDT'],
        recoveryPendingStages: const {'XRPUSDT': 'journalCommitted'},
        entryBlockReason: 'unmanagedExchangeExposure',
      );

      final restored = LocalLiveTradeStatus.fromJson(status.toJson());
      expect(restored.openPositionCount, 2);
      expect(restored.unmanagedPositionCount, 2);
      expect(restored.recoverableOrphanCount, 1);
      expect(restored.recoverableOrphanSymbols, ['XRPUSDT']);
      expect(restored.externalUnmanagedPositionCount, 1);
      expect(restored.externalUnmanagedSymbols, ['ETHUSDT']);
      expect(restored.recoveryPendingStages['XRPUSDT'], 'journalCommitted');
      expect(restored.requiresExchangeRecovery, isTrue);
      expect(restored.canResumeEntries, isFalse);
    },
  );

  test('old status JSON remains backwards compatible', () {
    final restored = LocalLiveTradeStatus.fromJson({
      'state': 'managingOnly',
      'updatedAt': DateTime.utc(2026, 8, 16).toIso8601String(),
      'message': 'legacy',
      'openPositionCount': 1,
      'managedPositionCount': 0,
      'unmanagedPositionCount': 1,
      'unmanagedSymbols': ['BTCUSDT'],
      'entriesEnabled': false,
    });

    expect(restored.recoverableOrphanCount, 0);
    expect(restored.externalUnmanagedPositionCount, 1);
    expect(restored.recoveryPendingStages, isEmpty);
  });
}
