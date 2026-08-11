import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/auto_trade/domain/trading_pnl_projection.dart';

void main() {
  test(
    'closed position can verify from complete local evidence despite unrelated source warning',
    () {
      final now = DateTime.utc(2026, 8, 7, 15, 0);
      final projection = TradingPnlProjection.reconcile(
        currency: 'USDT',
        asOf: now,
        unrealizedByPosition: const {},
        fills: [
          ExchangePnlFill(
            tradeId: 'entry',
            orderId: 'entry-order',
            positionId: 'p1',
            symbol: 'SOLUSDT',
            quantity: 0.23,
            price: 74,
            realizedPnl: 0,
            fee: 0.010212,
            reduceOnly: false,
            occurredAt: now.subtract(const Duration(minutes: 25)),
            side: 'BUY',
          ),
          ExchangePnlFill(
            tradeId: 'exit',
            orderId: 'stop-order',
            positionId: 'p1',
            symbol: 'SOLUSDT',
            quantity: 0.23,
            price: 73.62,
            realizedPnl: -0.0874,
            fee: 0.01015956,
            reduceOnly: true,
            occurredAt: now,
            side: 'SELL',
          ),
        ],
        settlements: [
          ExchangePositionSettlement(
            positionId: 'p1',
            symbol: 'SOLUSDT',
            funding: 0,
            realizedPnl: -0.0874,
            fee: 0.02037156,
            openedAt: now.subtract(const Duration(minutes: 25)),
            closedAt: now,
          ),
        ],
        sourceVerified: false,
        warning: 'An unrelated historical trade was ambiguous.',
      );
      final position = projection.forPositionId('p1');
      expect(position, isNotNull);
      expect(position!.isVerified, isTrue);
      expect(position.netRealized.value, closeTo(-0.10777156, 0.00000001));
    },
  );

  test('journal source hardens closure and diagnostic export', () {
    final observer = File(
      'lib/features/trading_journal/application/local_live_journal_observer.dart',
    ).readAsStringSync();
    final service = File(
      'lib/features/auto_trade/application/local_live_trade_service.dart',
    ).readAsStringSync();
    final store = File(
      'lib/features/trading_journal/data/database_trading_journal_store.dart',
    ).readAsStringSync();
    final tools = File(
      'lib/features/owner_alpha/presentation/owner_alpha_local_live_tools.dart',
    ).readAsStringSync();

    expect(observer, contains('_isExitFill'));
    expect(observer, contains("TradeDirection.long => side == 'SELL'"));
    expect(observer, contains('recordExchangeClosureObserved'));
    expect(service, contains('recordExchangeClosureObserved'));
    expect(store, contains('final candidate = merged.appendEvent(event)'));
    expect(tools, contains("'tradingJournal': journalLedger.toJson()"));
  });
}
