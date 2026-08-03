import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/auto_trade/data/bitunix_pnl_mapper.dart';
import 'package:quantara_app/features/auto_trade/domain/trading_pnl_projection.dart';

void main() {
  test(
    'historical fill maps to its closed interval before a same-symbol open position',
    () {
      final occurredAt = DateTime.utc(2026, 8, 3, 12);
      final result = BitunixPnlMapper.fills(
        {
          'tradeList': [
            {
              'tradeId': 'old-tp1-fill',
              'orderId': 'old-tp1-order',
              'symbol': 'XRPUSDT',
              'qty': '13.91',
              'price': '1.0603',
              'realizedPNL': '0.100',
              'fee': '0.004',
              'reduceOnly': true,
              'ctime': occurredAt.millisecondsSinceEpoch,
            },
          ],
        },
        openPositions: const [
          ExchangeUnrealizedPnl(
            positionId: 'current-open-xrp',
            symbol: 'XRPUSDT',
            value: -0.01,
          ),
        ],
        settlements: [
          ExchangePositionSettlement(
            positionId: 'closed-xrp-position',
            symbol: 'XRPUSDT',
            funding: -0.002,
            openedAt: DateTime.utc(2026, 8, 3, 11),
            closedAt: DateTime.utc(2026, 8, 3, 12, 30),
          ),
        ],
      );

      expect(result.verified, isTrue);
      expect(result.values.single.positionId, 'closed-xrp-position');
    },
  );

  test('overlapping closed intervals remain unverified instead of guessing', () {
    final occurredAt = DateTime.utc(2026, 8, 3, 12);
    final result = BitunixPnlMapper.fills(
      {
        'tradeList': [
          {
            'tradeId': 'ambiguous-fill',
            'orderId': 'ambiguous-order',
            'symbol': 'XRPUSDT',
            'qty': '1',
            'price': '1.0603',
            'realizedPNL': '0.010',
            'fee': '0.001',
            'reduceOnly': true,
            'ctime': occurredAt.millisecondsSinceEpoch,
          },
        ],
      },
      openPositions: const [
        ExchangeUnrealizedPnl(
          positionId: 'current-open-xrp',
          symbol: 'XRPUSDT',
          value: 0,
        ),
      ],
      settlements: [
        ExchangePositionSettlement(
          positionId: 'closed-xrp-a',
          symbol: 'XRPUSDT',
          funding: 0,
          openedAt: DateTime.utc(2026, 8, 3, 11),
          closedAt: DateTime.utc(2026, 8, 3, 12, 30),
        ),
        ExchangePositionSettlement(
          positionId: 'closed-xrp-b',
          symbol: 'XRPUSDT',
          funding: 0,
          openedAt: DateTime.utc(2026, 8, 3, 11, 30),
          closedAt: DateTime.utc(2026, 8, 3, 12, 15),
        ),
      ],
    );

    expect(result.verified, isFalse);
    expect(result.values.single.positionId, isEmpty);
    expect(result.warning, contains('ambiguous-fill'));
  });
}
