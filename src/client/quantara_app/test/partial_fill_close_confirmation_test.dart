import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/auto_trade/application/partial_fill_close_confirmation.dart';
import 'package:quantara_app/features/auto_trade/data/bitunix_local_live_api_client.dart';

void main() {
  const openPosition = BitunixLivePosition(
    positionId: 'position-1',
    symbol: 'BTCUSDT',
    quantity: 0.01,
    side: 'LONG',
    marginMode: 'ISOLATION',
    positionMode: 'ONE_WAY',
    leverage: 3,
    averageOpenPrice: 100000,
    realizedPnl: 0,
    unrealizedPnl: 0,
    fee: 0,
    funding: 0,
  );

  test('canceled entry plus no position proves flat', () {
    expect(
      PartialFillCloseConfirmationPolicy.provesFlat(
        orderStatus: 'CANCELED',
        position: null,
      ),
      isTrue,
    );
  });

  test('canceled entry with remaining exposure is not flat', () {
    expect(
      PartialFillCloseConfirmationPolicy.provesFlat(
        orderStatus: 'CANCELED',
        position: openPosition,
      ),
      isFalse,
    );
  });

  test('non-canceled order without position is not sufficient proof', () {
    expect(
      PartialFillCloseConfirmationPolicy.provesFlat(
        orderStatus: 'PARTIALLY_FILLED',
        position: null,
      ),
      isFalse,
    );
  });
}
