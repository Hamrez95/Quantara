import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/auto_trade/domain/trading_pnl_projection.dart';

void main() {
  final tp1At = DateTime.utc(2026, 8, 3, 12, 2);
  final stoppedAt = DateTime.utc(2026, 8, 3, 12, 18);

  test(
    'keeps TP1 realized separate from remaining unrealized without fake funding zero',
    () {
      final projection = TradingPnlProjection.reconcile(
        currency: 'USDT',
        asOf: tp1At,
        unrealizedByPosition: const {
          'xrp-position-1': ExchangeUnrealizedPnl(
            positionId: 'xrp-position-1',
            symbol: 'XRPUSDT',
            value: -0.012,
          ),
        },
        fills: [
          ExchangePnlFill(
            tradeId: 'entry-fill-1',
            orderId: 'entry-order-1',
            positionId: 'xrp-position-1',
            symbol: 'XRPUSDT',
            quantity: 21.4,
            price: 1.0665,
            realizedPnl: 0,
            fee: 0.010,
            reduceOnly: false,
            occurredAt: DateTime.utc(2026, 8, 3, 11, 57),
          ),
          ExchangePnlFill(
            tradeId: 'tp1-fill-1',
            orderId: 'tp1-order-1',
            positionId: 'xrp-position-1',
            symbol: 'XRPUSDT',
            quantity: 13.91,
            price: 1.0603,
            realizedPnl: 0.100,
            fee: 0.004,
            reduceOnly: true,
            occurredAt: tp1At,
          ),
        ],
        settlements: const [],
      );

      final position = projection.positions.single;
      expect(position.realizedGross.value, closeTo(0.100, 0.0000001));
      expect(position.fees.value, closeTo(0.014, 0.0000001));
      expect(position.funding.isAvailable, isFalse);
      expect(position.netRealized.isAvailable, isFalse);
      expect(position.unrealized.value, closeTo(-0.012, 0.0000001));
      expect(position.exitFills, hasLength(1));
      expect(position.exitFills.single.tradeId, 'tp1-fill-1');
    },
  );

  test(
    'TP1 then remaining stop reconciles once and preserves captured TP1 profit',
    () {
      final tp1 = ExchangePnlFill(
        tradeId: 'tp1-fill-1',
        orderId: 'tp1-order-1',
        positionId: 'xrp-position-1',
        symbol: 'XRPUSDT',
        quantity: 13.91,
        price: 1.0603,
        realizedPnl: 0.100,
        fee: 0.004,
        reduceOnly: true,
        occurredAt: tp1At,
      );
      final projection = TradingPnlProjection.reconcile(
        currency: 'USDT',
        asOf: stoppedAt,
        unrealizedByPosition: const {},
        fills: [
          ExchangePnlFill(
            tradeId: 'stop-fill-1',
            orderId: 'stop-order-1',
            positionId: 'xrp-position-1',
            symbol: 'XRPUSDT',
            quantity: 7.49,
            price: 1.0691,
            realizedPnl: -0.050,
            fee: 0.003,
            reduceOnly: true,
            occurredAt: stoppedAt,
          ),
          tp1,
          ExchangePnlFill(
            tradeId: 'entry-fill-1',
            orderId: 'entry-order-1',
            positionId: 'xrp-position-1',
            symbol: 'XRPUSDT',
            quantity: 21.4,
            price: 1.0665,
            realizedPnl: 0,
            fee: 0.010,
            reduceOnly: false,
            occurredAt: DateTime.utc(2026, 8, 3, 11, 57),
          ),
          tp1,
        ],
        settlements: [
          ExchangePositionSettlement(
            positionId: 'xrp-position-1',
            symbol: 'XRPUSDT',
            funding: -0.002,
            closedAt: stoppedAt,
          ),
        ],
      );

      final position = projection.positions.single;
      expect(position.exchangeFillIds, hasLength(3));
      expect(position.exitFills, hasLength(2));
      expect(position.realizedGross.value, closeTo(0.050, 0.0000001));
      expect(position.fees.value, closeTo(0.017, 0.0000001));
      expect(position.funding.value, closeTo(-0.002, 0.0000001));
      expect(position.netRealized.value, closeTo(0.031, 0.0000001));
      expect(position.unrealized.isAvailable, isFalse);
      expect(projection.accountNetRealized.value, closeTo(0.031, 0.0000001));
    },
  );

  test('conflicting duplicate trade IDs make the projection unverified', () {
    final projection = TradingPnlProjection.reconcile(
      currency: 'USDT',
      asOf: stoppedAt,
      unrealizedByPosition: const {},
      fills: [
        ExchangePnlFill(
          tradeId: 'duplicate-id',
          orderId: 'tp1-order-1',
          positionId: 'xrp-position-1',
          symbol: 'XRPUSDT',
          quantity: 13.91,
          price: 1.0603,
          realizedPnl: 0.100,
          fee: 0.004,
          reduceOnly: true,
          occurredAt: tp1At,
        ),
        ExchangePnlFill(
          tradeId: 'duplicate-id',
          orderId: 'tp1-order-1',
          positionId: 'xrp-position-1',
          symbol: 'XRPUSDT',
          quantity: 13.91,
          price: 1.0603,
          realizedPnl: 0.120,
          fee: 0.004,
          reduceOnly: true,
          occurredAt: tp1At,
        ),
      ],
      settlements: const [],
    );

    expect(projection.isVerified, isFalse);
    expect(projection.warning, contains('duplicate-id'));
    expect(projection.accountNetRealized.isAvailable, isFalse);
  });
}
