import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/auto_trade/domain/trading_pnl_projection.dart';
import 'package:quantara_app/features/trading_journal/application/trading_journal_exchange_history_recovery.dart';
import 'package:quantara_app/features/trading_journal/domain/trading_journal_models.dart';
import 'package:quantara_app/features/trading_journal/domain/trading_journal_projection.dart';

void main() {
  TradingPnlProjection solProjection({String entryClientId = 'q-local-deadbeef'}) {
    return TradingPnlProjection.reconcile(
      currency: 'USDT',
      asOf: DateTime.utc(2026, 8, 7, 15),
      unrealizedByPosition: const {},
      fills: [
        ExchangePnlFill(
          tradeId: 'sol-entry-fill',
          orderId: 'sol-entry-order',
          positionId: 'sol-position-1',
          symbol: 'SOLUSDT',
          quantity: 0.23,
          price: 74.00,
          realizedPnl: 0,
          fee: 0.01000000,
          reduceOnly: false,
          occurredAt: DateTime.utc(2026, 8, 7, 14, 0),
          clientId: entryClientId,
          side: 'BUY',
        ),
        ExchangePnlFill(
          tradeId: 'sol-stop-fill',
          orderId: 'sol-stop-order',
          positionId: 'sol-position-1',
          symbol: 'SOLUSDT',
          quantity: 0.23,
          price: 73.62,
          realizedPnl: -0.0874,
          fee: 0.01037156,
          reduceOnly: false,
          occurredAt: DateTime.utc(2026, 8, 7, 14, 25),
          side: 'SELL',
        ),
      ],
      settlements: [
        ExchangePositionSettlement(
          positionId: 'sol-position-1',
          symbol: 'SOLUSDT',
          funding: 0,
          openedAt: DateTime.utc(2026, 8, 7, 14, 0),
          closedAt: DateTime.utc(2026, 8, 7, 14, 25),
          realizedPnl: -0.0874,
          fee: 0.02037156,
        ),
      ],
    );
  }

  test(
    'clean reinstall recovers verified Quantara SOL history without fabricating decision context',
    () {
      final result = TradingJournalExchangeHistoryRecovery.recoverVerifiedHistory(
        ledger: TradingJournalLedger.empty(),
        pnlProjection: solProjection(),
        recordedAt: DateTime.utc(2026, 8, 8),
      );

      expect(result.changed, isTrue);
      expect(result.recoveredTradeIds, ['exchange-recovered:sol-position-1']);
      expect(result.ledger.integrity, isNot(TradingJournalIntegrity.unverified));
      expect(result.ledger.plans, hasLength(1));
      expect(result.ledger.events, hasLength(2));

      final plan = result.ledger.plans.single;
      expect(plan.source, TradingJournalSource.importedExchange);
      expect(plan.clientId, 'q-local-deadbeef');
      expect(plan.direction, TradingJournalDirection.long);
      expect(plan.strategy, 'not-captured');
      expect(plan.timeframe, 'unknown');
      expect(plan.originalStopLoss, 0);
      expect(plan.targets, isEmpty);
      expect(plan.confidencePercent, 0);
      expect(plan.notes, contains('were not fabricated'));

      final closeEvent = result.ledger.events.singleWhere(
        (event) => event.type == TradingJournalEventType.positionClosed,
      );
      expect(closeEvent.price, closeTo(73.62, 0.0000001));
      expect(closeEvent.details['recoveredAfterInstall'], isTrue);

      final projection = TradingJournalProjector.projectAll(result.ledger).single;
      expect(projection.state, TradingJournalTradeState.closed);
      expect(projection.entryPrice, closeTo(74.00, 0.0000001));
      expect(projection.grossPnl, closeTo(-0.0874, 0.0000001));
      expect(projection.fees, closeTo(0.02037156, 0.00000001));
      expect(projection.funding, closeTo(0, 0.0000001));
      expect(projection.netPnl, closeTo(-0.10777156, 0.00000001));
      expect(projection.closeReason, TradingJournalCloseReason.exchange);
      expect(projection.holdingDuration, const Duration(minutes: 25));
    },
  );

  test('foreign or manual exchange history is never claimed by Quantara', () {
    final result = TradingJournalExchangeHistoryRecovery.recoverVerifiedHistory(
      ledger: TradingJournalLedger.empty(),
      pnlProjection: solProjection(entryClientId: 'manual-mobile-order'),
      recordedAt: DateTime.utc(2026, 8, 8),
    );

    expect(result.changed, isFalse);
    expect(result.ledger.plans, isEmpty);
    expect(result.ledger.events, isEmpty);
  });

  test('reinstall recovery is idempotent', () {
    final first = TradingJournalExchangeHistoryRecovery.recoverVerifiedHistory(
      ledger: TradingJournalLedger.empty(),
      pnlProjection: solProjection(),
      recordedAt: DateTime.utc(2026, 8, 8),
    );
    final second = TradingJournalExchangeHistoryRecovery.recoverVerifiedHistory(
      ledger: first.ledger,
      pnlProjection: solProjection(),
      recordedAt: DateTime.utc(2026, 8, 8, 0, 1),
    );

    expect(first.changed, isTrue);
    expect(second.changed, isFalse);
    expect(second.ledger.plans, hasLength(1));
    expect(second.ledger.events, hasLength(2));
  });

  test('derived q-local close client IDs cannot masquerade as an entry', () {
    final result = TradingJournalExchangeHistoryRecovery.recoverVerifiedHistory(
      ledger: TradingJournalLedger.empty(),
      pnlProjection: solProjection(
        entryClientId: 'q-local-deadbeef-emergency-close',
      ),
      recordedAt: DateTime.utc(2026, 8, 8),
    );

    expect(result.changed, isFalse);
  });
}
