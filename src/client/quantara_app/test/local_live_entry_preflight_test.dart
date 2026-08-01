import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/auto_trade/domain/local_live_entry_preflight.dart';

void main() {
  test('existing position bypasses only the new-entry affordability gate', () {
    expect(
      LocalLiveEntryPreflightPolicy.shouldCheckNewEntryAffordability(
        openPositionCount: 0,
      ),
      isTrue,
    );
    expect(
      LocalLiveEntryPreflightPolicy.shouldCheckNewEntryAffordability(
        openPositionCount: 1,
      ),
      isFalse,
    );
  });

  test('requires three exchange-minimum quantities for three TP tranches', () {
    final result = LocalLiveEntryAffordability.calculate(
      availableMargin: 0.25,
      markPrice: 60000,
      minimumExchangeQuantity: 0.0001,
      leverage: 4,
    );

    expect(result.requiredQuantity, closeTo(0.0003, 1e-12));
    expect(result.minimumNotional, closeTo(18, 1e-9));
    expect(result.minimumBufferedMargin, closeTo(5.175, 1e-9));
    expect(result.affordable, isFalse);
    expect(result.shortfall, closeTo(4.925, 1e-9));
  });

  test(
    'higher leverage lowers margin floor but never changes quantity floor',
    () {
      final lowLeverage = LocalLiveEntryAffordability.calculate(
        availableMargin: 10,
        markPrice: 60000,
        minimumExchangeQuantity: 0.0001,
        leverage: 4,
      );
      final highLeverage = LocalLiveEntryAffordability.calculate(
        availableMargin: 10,
        markPrice: 60000,
        minimumExchangeQuantity: 0.0001,
        leverage: 20,
      );

      expect(highLeverage.requiredQuantity, lowLeverage.requiredQuantity);
      expect(
        highLeverage.minimumBufferedMargin,
        lessThan(lowLeverage.minimumBufferedMargin),
      );
      expect(highLeverage.affordable, isTrue);
    },
  );

  test('rejects malformed exchange values', () {
    expect(
      () => LocalLiveEntryAffordability.calculate(
        availableMargin: 1,
        markPrice: double.nan,
        minimumExchangeQuantity: 0.0001,
        leverage: 4,
      ),
      throwsFormatException,
    );
  });
}
