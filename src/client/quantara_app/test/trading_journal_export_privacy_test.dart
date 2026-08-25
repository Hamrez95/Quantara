import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/trading_journal/data/trading_journal_export.dart';
import 'package:quantara_app/features/trading_journal/domain/trading_journal_models.dart';

void main() {
  const rawJournalId = 'local-live:position-raw-123';
  const rawPositionId = 'position-raw-123';
  const rawOrderId = 'order-raw-456';
  const rawTradeId = 'trade-raw-789';
  const rawClientId = 'q-live-client-secret-shape';

  TradingJournalLedger ledger() {
    var result = TradingJournalLedger.empty();
    result = result.appendPlan(
      TradingJournalPlan(
        journalTradeId: rawJournalId,
        setupId: 'setup-raw-42',
        analysisVersion: 'test',
        symbol: 'BTCUSDT',
        market: 'USDT_PERPETUAL',
        timeframe: '15m',
        direction: TradingJournalDirection.long,
        strategy: 'structureZones',
        cadence: 'balanced',
        source: TradingJournalSource.localLive,
        decidedAt: DateTime.utc(2026, 8, 24, 12),
        decisionPrice: 100,
        entryLower: 99,
        entryUpper: 101,
        plannedEntry: 100,
        originalStopLoss: 95,
        targets: const [105, 110, 115],
        expectedRMultiples: const [1, 2, 3],
        confidencePercent: 80,
        confluence: const ['fixture'],
        regime: 'trend',
        rationale: 'fixture',
        invalidation: 'fixture',
        accountEquity: 1000,
        riskPercent: 1,
        riskBudget: 10,
        leverage: 2,
        expectedMargin: 50,
        passedGates: const ['fixture'],
        blockedGates: const [],
        appVersion: 'test',
        strategyRulesVersion: 'test',
        positionId: rawPositionId,
        entryOrderId: rawOrderId,
        clientId: rawClientId,
      ),
    );
    result = result.appendEvent(
      TradingJournalEvent(
        eventId: 'event-$rawTradeId',
        journalTradeId: rawJournalId,
        type: TradingJournalEventType.positionClosed,
        occurredAt: DateTime.utc(2026, 8, 24, 13),
        recordedAt: DateTime.utc(2026, 8, 24, 13),
        source: TradingJournalFactSource.exchange,
        quality: TradingJournalFactQuality.confirmed,
        scope: TradingJournalScope.position,
        currency: 'USDT',
        asOf: DateTime.utc(2026, 8, 24, 13),
        exchangeEventId: rawTradeId,
        positionId: rawPositionId,
        orderId: rawOrderId,
        clientId: rawClientId,
        tradeId: rawTradeId,
        quantity: 1,
        price: 110,
        grossPnl: 10,
        remainingQuantity: 0,
        details: const {'note': 'closed $rawPositionId via $rawOrderId'},
      ),
    );
    return result;
  }

  test(
    'JSON and CSV remove raw exchange identifiers but preserve correlation',
    () {
      final source = ledger();
      final json = TradingJournalExport.toPrivacySafeJson(source);
      final csv = TradingJournalExport.toPrivacySafeCsv(source);

      for (final raw in [
        rawJournalId,
        rawPositionId,
        rawOrderId,
        rawTradeId,
        rawClientId,
      ]) {
        expect(json, isNot(contains(raw)));
        expect(csv, isNot(contains(raw)));
      }
      expect(json, contains('journal_'));
      expect(json, contains('position_'));
      expect(json, contains('order_'));
      expect(json, contains('trade_'));

      final imported = TradingJournalExport.fromPrivacySafeJson(json);
      expect(imported.plans, hasLength(1));
      expect(imported.events, hasLength(1));
      expect(
        imported.events.single.journalTradeId,
        imported.plans.single.journalTradeId,
      );
      expect(
        imported.events.single.positionId,
        imported.plans.single.positionId,
      );
    },
  );
}
