import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/auto_trade/data/bitunix_pnl_mapper.dart';

void main() {
  test('attributes a stop fill just after rounded settlement close time', () {
    final openedAt = DateTime.utc(2026, 8, 5, 2);
    final closedAt = DateTime.utc(2026, 8, 5, 3, 19);
    final fillAt = DateTime.utc(2026, 8, 5, 3, 19, 14);
    final settlements = BitunixPnlMapper.settlements({
      'positionList': [
        {
          'positionId': 'gram-position',
          'symbol': 'GRAMUSDT',
          'ctime': openedAt.millisecondsSinceEpoch,
          'mtime': closedAt.millisecondsSinceEpoch,
          'realizedPNL': '-0.2574',
          'fee': '0.03575286',
          'funding': '0',
        },
      ],
    });
    final fills = BitunixPnlMapper.fills(
      {
        'tradeList': [
          {
            'tradeId': '2795413522294203930',
            'orderId': '7352379888826528074',
            'symbol': 'GRAMUSDT',
            'qty': '42.9',
            'price': '1.389',
            'realizedPNL': '-0.2574',
            'fee': '0.03575286',
            'ctime': fillAt.millisecondsSinceEpoch,
            'reduceOnly': true,
            'side': 'SELL',
          },
        ],
      },
      openPositions: const [],
      settlements: settlements.values,
    );

    expect(settlements.verified, isTrue);
    expect(fills.verified, isTrue);
    expect(fills.warning, isNull);
    expect(fills.values.single.positionId, 'gram-position');
    expect(fills.values.single.quantity, 42.9);
    expect(fills.values.single.realizedPnl, -0.2574);
    expect(fills.values.single.fee, 0.03575286);
  });

  test('keeps equal-distance same-symbol closed histories ambiguous', () {
    final fillAt = DateTime.utc(2026, 8, 5, 3, 19, 14);
    final settlements = BitunixPnlMapper.settlements({
      'positionList': [
        {
          'positionId': 'left',
          'symbol': 'GRAMUSDT',
          'ctime': DateTime.utc(2026, 8, 5, 1).millisecondsSinceEpoch,
          'mtime': DateTime.utc(2026, 8, 5, 3, 19).millisecondsSinceEpoch,
        },
        {
          'positionId': 'right',
          'symbol': 'GRAMUSDT',
          'ctime': DateTime.utc(2026, 8, 5, 1).millisecondsSinceEpoch,
          'mtime': DateTime.utc(2026, 8, 5, 3, 19).millisecondsSinceEpoch,
        },
      ],
    });
    final fills = BitunixPnlMapper.fills(
      {
        'tradeList': [
          {
            'tradeId': 'ambiguous',
            'orderId': 'close-order',
            'symbol': 'GRAMUSDT',
            'qty': '1',
            'price': '1.389',
            'realizedPNL': '-0.1',
            'fee': '0.01',
            'ctime': fillAt.millisecondsSinceEpoch,
            'reduceOnly': true,
          },
        ],
      },
      openPositions: const [],
      settlements: settlements.values,
    );

    expect(fills.verified, isTrue);
    expect(
      fills.values.single.positionId,
      '${BitunixPnlMapper.unassignedPositionPrefix}ambiguous',
    );
    expect(fills.warning, contains('could not be assigned'));
  });
}
