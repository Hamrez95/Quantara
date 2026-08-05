import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/auto_trade/domain/local_live_trade_models.dart';

void main() {
  test(
    'an exchange orphan consumes a slot and cannot expose Resume entries',
    () {
      final status = LocalLiveTradeStatus(
        state: LocalLiveTradeState.managingOnly,
        updatedAt: DateTime.utc(2026, 8, 5),
        message: 'recovery pending',
        openPositionCount: 1,
        managedPositionCount: 0,
        unmanagedPositionCount: 1,
        unmanagedSymbols: const ['XRPUSDT'],
        entryBlockReason: 'unmanagedExchangeExposure',
        entriesEnabled: false,
      );

      expect(status.requiresExchangeRecovery, isTrue);
      expect(status.canResumeEntries, isFalse);
      final restored = LocalLiveTradeStatus.fromJson(status.toJson());
      expect(restored.openPositionCount, 1);
      expect(restored.managedPositionCount, 0);
      expect(restored.unmanagedPositionCount, 1);
      expect(restored.unmanagedSymbols, ['XRPUSDT']);
      expect(restored.canResumeEntries, isFalse);
    },
  );

  test('a fully managed portfolio can be explicitly re-armed', () {
    final status = LocalLiveTradeStatus(
      state: LocalLiveTradeState.managingOnly,
      updatedAt: DateTime.utc(2026, 8, 5),
      message: 'user stopped entries',
      openPositionCount: 1,
      managedPositionCount: 1,
      unmanagedPositionCount: 0,
      entriesEnabled: false,
    );

    expect(status.requiresExchangeRecovery, isFalse);
    expect(status.canResumeEntries, isTrue);
  });
}
