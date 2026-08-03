import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/auto_trade/domain/auto_trade_models.dart';
import 'package:quantara_app/features/auto_trade/presentation/position_protection_summary.dart';

void main() {
  const position = AutoTradePosition(
    positionId: 'xrp-position-1',
    symbol: 'XRPUSDT',
    quantity: 21.4,
    side: 'SHORT',
    marginMode: 'ISOLATION',
    positionMode: 'HEDGE',
    leverage: 10,
    margin: 2.30,
    unrealizedPnl: 0.0021,
    liquidationPrice: 1.12,
    averageOpenPrice: 1.0665,
  );
  final asOf = DateTime.utc(2026, 8, 3, 11, 27);
  final protection = AutoTradePositionProtection.reconcile(
    position: position,
    orders: const [
      AutoTradeProtectionOrder.stopLoss(
        exchangeId: 'sl-1',
        positionId: 'xrp-position-1',
        symbol: 'XRPUSDT',
        price: 1.0691,
        quantity: 21.4,
      ),
      AutoTradeProtectionOrder.takeProfit(
        exchangeId: 'tp-1',
        positionId: 'xrp-position-1',
        symbol: 'XRPUSDT',
        price: 1.0603,
        quantity: 8.56,
      ),
      AutoTradeProtectionOrder.takeProfit(
        exchangeId: 'tp-2',
        positionId: 'xrp-position-1',
        symbol: 'XRPUSDT',
        price: 1.0567,
        quantity: 6.42,
      ),
      AutoTradeProtectionOrder.takeProfit(
        exchangeId: 'tp-3',
        positionId: 'xrp-position-1',
        symbol: 'XRPUSDT',
        price: 1.0531,
        quantity: 6.42,
      ),
    ],
    asOf: asOf,
  );

  testWidgets('shows verified SL, all partial TPs, total, and residual', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PositionProtectionSummary(
            protection: protection,
            stale: false,
            persian: false,
          ),
        ),
      ),
    );

    expect(find.text('Fully protected'), findsOneWidget);
    expect(find.textContaining('SL 1.0691'), findsOneWidget);
    expect(find.textContaining('TP1 1.0603'), findsOneWidget);
    expect(find.textContaining('TP2 1.0567'), findsOneWidget);
    expect(find.textContaining('TP3 1.0531'), findsOneWidget);
    expect(find.textContaining('TP total 21.4'), findsOneWidget);
    expect(find.textContaining('Residual 0'), findsOneWidget);
  });

  testWidgets('stale reconciliation overrides a previously verified badge', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PositionProtectionSummary(
            protection: protection,
            stale: true,
            persian: false,
          ),
        ),
      ),
    );

    expect(find.text('Stale'), findsOneWidget);
    expect(find.text('Fully protected'), findsNothing);
  });
}
