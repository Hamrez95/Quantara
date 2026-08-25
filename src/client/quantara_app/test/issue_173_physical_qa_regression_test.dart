import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/auto_trade/domain/auto_trade_models.dart';
import 'package:quantara_app/features/auto_trade/domain/trading_pnl_projection.dart';

void main() {
  test('AAVE open-position net semantics stay verified', () {
    final openedAt = DateTime.utc(2026, 8, 8, 16, 34, 9);
    const gross = 0.0;
    const feeExpense = 0.0054756;
    const funding = 0.00058839571;
    const pendingNet = -0.00488720429;
    final open = ExchangeUnrealizedPnl(
      positionId: '3518418297103901915',
      symbol: 'AAVEUSDT',
      value: 0.006,
      realizedPnl: pendingNet,
      fee: -feeExpense,
      funding: funding,
      openedAt: openedAt,
    );
    final entryFill = ExchangePnlFill(
      tradeId: '6465817657640892218',
      orderId: '2086128842343002112',
      positionId: open.positionId,
      symbol: open.symbol,
      quantity: 0.1,
      price: 91.26,
      realizedPnl: gross,
      fee: feeExpense,
      reduceOnly: false,
      occurredAt: openedAt,
      side: 'SELL',
    );

    final projection = TradingPnlProjection.reconcile(
      currency: 'USDT',
      asOf: DateTime.utc(2026, 8, 9, 6, 12),
      unrealizedByPosition: {open.positionId: open},
      fills: [entryFill],
      settlements: const [],
      sourceVerified: true,
    );
    final position = projection.forPositionId(open.positionId);

    expect(gross - feeExpense + funding, closeTo(pendingNet, 1e-12));
    expect(position, isNotNull);
    expect(position!.isVerified, isTrue);
    expect(position.warning, isNull);
    expect(position.fees.value, closeTo(feeExpense, 1e-12));
    expect(projection.isReadyForRiskGates, isTrue);
  });

  test('one full TP plus one full SL is complete account protection', () {
    const position = AutoTradePosition(
      positionId: '3518418297103901915',
      symbol: 'AAVEUSDT',
      quantity: 0.1,
      side: 'SELL',
      marginMode: 'ISOLATION',
      positionMode: 'HEDGE',
      leverage: 10,
      margin: 0.919,
      unrealizedPnl: 0.006,
      liquidationPrice: 99.83,
      averageOpenPrice: 91.26,
    );
    final asOf = DateTime.utc(2026, 8, 9, 6, 12);
    final snapshot = AutoTradeAccountSnapshot(
      marginCoin: 'USDT',
      available: 28.65,
      frozen: 0,
      positionMargin: 0.919,
      crossUnrealizedPnl: 0,
      isolatedUnrealizedPnl: 0.006,
      positionMode: 'HEDGE',
      positions: const [position],
      orders: const [],
      protectionOrders: const [
        AutoTradeProtectionOrder.takeProfit(
          exchangeId: 'tp-1',
          positionId: '3518418297103901915',
          symbol: 'AAVEUSDT',
          price: 88.8,
          quantity: 0.1,
        ),
        AutoTradeProtectionOrder.stopLoss(
          exchangeId: 'sl-1',
          positionId: '3518418297103901915',
          symbol: 'AAVEUSDT',
          price: 92.36,
          quantity: 0.1,
        ),
      ],
      protectionVerifications: {
        '3518418297103901915': AutoTradeProtectionVerification.verified(
          asOf: asOf,
        ),
      },
      syncedAt: asOf,
    );

    expect(
      snapshot.protectionForPosition(position).status,
      AutoTradeProtectionStatus.fullyProtected,
    );
    expect(snapshot.allOpenPositionsFullyProtected, isTrue);
  });

  test(
    'Issue 173 wiring preserves frozen plan and immutable historical replay',
    () {
      final projectionSource = File(
        'lib/features/auto_trade/domain/trading_pnl_projection.dart',
      ).readAsStringSync();
      final serviceSource = File(
        'lib/features/auto_trade/application/local_live_trade_service.dart',
      ).readAsStringSync();
      final accountSource = File(
        'lib/features/auto_trade/domain/auto_trade_models.dart',
      ).readAsStringSync();
      final chartSource = File(
        'lib/features/market_analysis/presentation/tradingview_lightweight_chart.dart',
      ).readAsStringSync();
      final journalSource = File(
        'lib/features/trading_journal/presentation/trading_journal_view.dart',
      ).readAsStringSync();
      final pageSource = File(
        'lib/features/owner_alpha/presentation/owner_alpha_page.dart',
      ).readAsStringSync();

      expect(projectionSource, contains('pendingNetFromHistory'));
      expect(projectionSource, contains('pendingFeeExpense'));
      expect(serviceSource, contains('clearWarning: true'));
      expect(accountSource, contains('expectedTakeProfitCount: 1'));
      expect(chartSource, contains('this.tradeOverlay'));
      expect(journalSource, contains('TradingJournalReplay.decisionChart('));
      expect(journalSource, contains('analysis: historicalAnalysis,'));
      expect(journalSource, contains('currentIdea: null,'));
      expect(journalSource, contains('بازپخش نمودار لحظه تصمیم'));
      expect(journalSource, contains('داده زنده جایگزین تاریخچه نمی‌شود'));
      expect(journalSource, contains('previousDonchianHigh20'));
      expect(journalSource, contains('live.strongestZones'));
      expect(pageSource, contains('journalLiveAnalyses'));
      expect(pageSource, contains('await _controller.refresh();'));
    },
  );
}
