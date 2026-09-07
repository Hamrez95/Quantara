import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/owner_alpha/domain/owner_alpha_models.dart';
import 'package:quantara_app/features/owner_alpha/domain/setup_performance_reporting.dart';
import 'package:quantara_app/features/trading_journal/domain/trading_journal_models.dart';
import 'package:quantara_app/features/trading_journal/domain/trading_journal_projection.dart';

void main() {
  final now = DateTime.utc(2026, 9, 7, 12);

  group('SetupPerformanceReport analytical evidence', () {
    test('counts all 82 resolved setup outcomes without inventing trades', () {
      final signals = List.generate(
        82,
        (index) => _signal(
          setupId: 'setup-$index',
          resolvedAt: now.subtract(Duration(hours: index)),
          simulatedPnl: index.isEven ? 2 : -1,
          outcome: index.isEven ? SignalOutcome.tp3 : SignalOutcome.stopped,
        ),
      );

      final report = SetupPerformanceReport.build(
        signals: signals,
        projections: const [],
        filter: const SetupPerformanceFilter(range: SetupPerformanceRange.all),
        now: now,
      );

      expect(report.summary.resolvedCount, 82);
      expect(report.summary.analyticalWins, 41);
      expect(report.summary.analyticalLosses, 41);
      expect(report.summary.actualConfirmedClosedCount, 0);
      expect(report.summary.actualNetRealizedPnl, isNull);
      expect(report.summary.actualUnavailableCount, 82);
    });

    test('aggregates win loss breakeven R and simulated net PnL', () {
      final report = SetupPerformanceReport.build(
        signals: [
          _signal(
            setupId: 'win',
            resolvedAt: now,
            simulatedPnl: 10,
            maximumLoss: 5,
          ),
          _signal(
            setupId: 'loss',
            resolvedAt: now,
            simulatedPnl: -5,
            maximumLoss: 5,
            outcome: SignalOutcome.stopped,
          ),
          _signal(
            setupId: 'flat',
            resolvedAt: now,
            simulatedPnl: 0,
            maximumLoss: 5,
          ),
          _signal(setupId: 'missing', resolvedAt: now, simulatedPnl: null),
        ],
        projections: const [],
        filter: const SetupPerformanceFilter(range: SetupPerformanceRange.all),
        now: now,
      );

      expect(report.summary.resolvedCount, 4);
      expect(report.summary.analyticalWins, 1);
      expect(report.summary.analyticalLosses, 1);
      expect(report.summary.analyticalBreakeven, 1);
      expect(report.summary.analyticalUnavailable, 1);
      expect(report.summary.analyticalWinRatePercent, 50);
      expect(report.summary.totalAnalyticalR, closeTo(1, 1e-9));
      expect(report.summary.averageAnalyticalR, closeTo(1 / 3, 1e-9));
      expect(report.summary.totalSimulatedNetPnl, closeTo(5, 1e-9));
      expect(report.summary.averageSimulatedNetPnl, closeTo(5 / 3, 1e-9));
    });

    test('applies time strategy symbol and timeframe filters', () {
      final signals = [
        _signal(
          setupId: 'match',
          resolvedAt: now.subtract(const Duration(days: 2)),
          symbol: 'BTCUSDT',
          timeframe: '1h',
          strategy: AnalysisStrategy.trendPullback,
        ),
        _signal(
          setupId: 'old',
          resolvedAt: now.subtract(const Duration(days: 9)),
          symbol: 'BTCUSDT',
          timeframe: '1h',
          strategy: AnalysisStrategy.trendPullback,
        ),
        _signal(
          setupId: 'other-symbol',
          resolvedAt: now.subtract(const Duration(days: 1)),
          symbol: 'ETHUSDT',
          timeframe: '1h',
          strategy: AnalysisStrategy.trendPullback,
        ),
        _signal(
          setupId: 'other-timeframe',
          resolvedAt: now.subtract(const Duration(days: 1)),
          symbol: 'BTCUSDT',
          timeframe: '4h',
          strategy: AnalysisStrategy.trendPullback,
        ),
        _signal(
          setupId: 'other-strategy',
          resolvedAt: now.subtract(const Duration(days: 1)),
          symbol: 'BTCUSDT',
          timeframe: '1h',
          strategy: AnalysisStrategy.structureZones,
        ),
      ];

      final report = SetupPerformanceReport.build(
        signals: signals,
        projections: const [],
        filter: const SetupPerformanceFilter(
          range: SetupPerformanceRange.sevenDays,
          strategy: AnalysisStrategy.trendPullback,
          symbol: 'btcusdt',
          timeframe: '1h',
        ),
        now: now,
      );

      expect(report.rows, hasLength(1));
      expect(report.rows.single.entry.setupId, 'match');
    });

    test('invalid custom range fails closed with no included rows', () {
      final report = SetupPerformanceReport.build(
        signals: [_signal(setupId: 'x', resolvedAt: now)],
        projections: const [],
        filter: SetupPerformanceFilter(
          range: SetupPerformanceRange.custom,
          customStartUtc: now,
          customEndUtcExclusive: now,
        ),
        now: now,
      );

      expect(report.rows, isEmpty);
      expect(report.summary.actualNetRealizedPnl, isNull);
    });
  });

  group('SetupPerformanceReport exchange evidence', () {
    test(
      'does not report actual zero when no linked exchange trade exists',
      () {
        final report = SetupPerformanceReport.build(
          signals: [_signal(setupId: 'unlinked', resolvedAt: now)],
          projections: const [],
          filter: const SetupPerformanceFilter(
            range: SetupPerformanceRange.all,
          ),
          now: now,
        );

        expect(
          report.rows.single.actual.status,
          SetupActualEvidenceStatus.unavailable,
        );
        expect(report.rows.single.actual.netRealizedPnl, isNull);
        expect(report.summary.actualNetRealizedPnl, isNull);
        expect(report.summary.actualWinRatePercent, isNull);
      },
    );

    test('uses complete confirmed exchange economics for real net PnL', () {
      final projection = _exchangeProjection(
        setupId: 'linked',
        journalTradeId: 'local-live:p-1',
        positionId: 'p-1',
        decidedAt: now.subtract(const Duration(hours: 3)),
        closedAt: now.subtract(const Duration(hours: 1)),
        grossPnl: 12,
        fee: 2,
        funding: -1,
      );
      final report = SetupPerformanceReport.build(
        signals: [_signal(setupId: 'linked', resolvedAt: now)],
        projections: [projection],
        filter: const SetupPerformanceFilter(range: SetupPerformanceRange.all),
        now: now,
      );

      final actual = report.rows.single.actual;
      expect(actual.status, SetupActualEvidenceStatus.confirmedClosed);
      expect(actual.netRealizedPnl, closeTo(9, 1e-9));
      expect(actual.grossRealizedPnl, closeTo(12, 1e-9));
      expect(actual.fees, closeTo(2, 1e-9));
      expect(actual.funding, closeTo(-1, 1e-9));
      expect(actual.provenance, 'confirmed_exchange_reconciliation');
      expect(report.summary.actualNetRealizedPnl, closeTo(9, 1e-9));
      expect(report.summary.actualWinRatePercent, 100);
    });

    test('stale exchange evidence stays pending and is excluded', () {
      final projection = _exchangeProjection(
        setupId: 'stale',
        journalTradeId: 'local-live:p-stale',
        positionId: 'p-stale',
        decidedAt: now.subtract(const Duration(hours: 3)),
        closedAt: now.subtract(const Duration(hours: 1)),
        grossPnl: 20,
        fee: 1,
        funding: 0,
        quality: TradingJournalFactQuality.stale,
      );
      final report = SetupPerformanceReport.build(
        signals: [_signal(setupId: 'stale', resolvedAt: now)],
        projections: [projection],
        filter: const SetupPerformanceFilter(range: SetupPerformanceRange.all),
        now: now,
      );

      expect(
        report.rows.single.actual.status,
        SetupActualEvidenceStatus.pendingReconciliation,
      );
      expect(report.rows.single.actual.netRealizedPnl, isNull);
      expect(report.summary.actualNetRealizedPnl, isNull);
    });

    test('multiple journal trades for one setup are a mismatch', () {
      final projections = [
        _exchangeProjection(
          setupId: 'duplicate',
          journalTradeId: 'local-live:p-a',
          positionId: 'p-a',
          decidedAt: now.subtract(const Duration(hours: 3)),
          closedAt: now.subtract(const Duration(hours: 2)),
          grossPnl: 3,
          fee: 1,
          funding: 0,
        ),
        _exchangeProjection(
          setupId: 'duplicate',
          journalTradeId: 'local-live:p-b',
          positionId: 'p-b',
          decidedAt: now.subtract(const Duration(hours: 3)),
          closedAt: now.subtract(const Duration(hours: 1)),
          grossPnl: -2,
          fee: 1,
          funding: 0,
        ),
      ];
      final report = SetupPerformanceReport.build(
        signals: [_signal(setupId: 'duplicate', resolvedAt: now)],
        projections: projections,
        filter: const SetupPerformanceFilter(range: SetupPerformanceRange.all),
        now: now,
      );

      expect(
        report.rows.single.actual.status,
        SetupActualEvidenceStatus.mismatch,
      );
      expect(report.summary.actualMismatchCount, 1);
      expect(report.summary.actualNetRealizedPnl, isNull);
    });

    test(
      'CSV keeps simulated and actual PnL in separate auditable columns',
      () {
        final report = SetupPerformanceReport.build(
          signals: [_signal(setupId: 'csv', resolvedAt: now, simulatedPnl: 5)],
          projections: [
            _exchangeProjection(
              setupId: 'csv',
              journalTradeId: 'local-live:p-csv',
              positionId: 'p-csv',
              decidedAt: now.subtract(const Duration(hours: 2)),
              closedAt: now.subtract(const Duration(hours: 1)),
              grossPnl: -3,
              fee: 1,
              funding: 0,
            ),
          ],
          filter: const SetupPerformanceFilter(
            range: SetupPerformanceRange.all,
          ),
          now: now,
        );

        final csv = report.toCsv();
        expect(csv, contains('analytical_net_pnl_simulated'));
        expect(csv, contains('actual_net_realized_pnl'));
        expect(csv, contains('closed_candle_replay_after_defined_costs'));
        expect(csv, contains('confirmed_exchange_reconciliation'));
      },
    );
  });
}

SignalJournalEntry _signal({
  required String setupId,
  required DateTime resolvedAt,
  double? simulatedPnl = 5,
  double maximumLoss = 5,
  SignalOutcome outcome = SignalOutcome.tp3,
  String symbol = 'BTCUSDT',
  String timeframe = '1h',
  AnalysisStrategy strategy = AnalysisStrategy.structureZones,
}) => SignalJournalEntry(
  setupId: setupId,
  symbol: symbol,
  timeframe: timeframe,
  direction: TradeDirection.long,
  strategy: strategy,
  strategyVersion: '1.0',
  createdAt: resolvedAt.subtract(const Duration(hours: 2)),
  validUntil: resolvedAt.subtract(const Duration(hours: 1)),
  entryLower: 100,
  entryUpper: 101,
  stopLoss: 95,
  targets: const [105, 110, 115],
  maximumLoss: maximumLoss,
  positionSize: 1,
  notionalValue: 100,
  estimatedRoundTripCosts: 0.2,
  recommendedLeverage: 2,
  maximumSafeLeverage: 5,
  selectedLeverage: 2,
  summary: 'Test setup',
  invalidation: 'Test invalidation',
  confidencePercent: 70,
  riskReward: 2,
  outcome: outcome,
  highestTargetHit: outcome == SignalOutcome.stopped ? 0 : 3,
  activatedAt: resolvedAt.subtract(const Duration(minutes: 90)),
  resolvedAt: resolvedAt,
  priceChangePercent: simulatedPnl == null ? null : simulatedPnl / 10,
  simulatedPnl: simulatedPnl,
  marginReturnPercent: simulatedPnl,
);

TradingJournalProjection _exchangeProjection({
  required String setupId,
  required String journalTradeId,
  required String positionId,
  required DateTime decidedAt,
  required DateTime closedAt,
  required double grossPnl,
  required double fee,
  required double funding,
  TradingJournalFactQuality quality = TradingJournalFactQuality.confirmed,
}) {
  final plan = _plan(
    setupId: setupId,
    journalTradeId: journalTradeId,
    positionId: positionId,
    decidedAt: decidedAt,
  );
  final entry = TradingJournalEvent(
    eventId: 'entry:$positionId',
    journalTradeId: journalTradeId,
    type: TradingJournalEventType.entryFilled,
    occurredAt: decidedAt.add(const Duration(minutes: 5)),
    recordedAt: decidedAt.add(const Duration(minutes: 5)),
    source: TradingJournalFactSource.exchange,
    quality: quality,
    scope: TradingJournalScope.position,
    currency: 'USDT',
    asOf: decidedAt.add(const Duration(minutes: 5)),
    exchangeEventId: 'entry-exchange:$positionId',
    positionId: positionId,
    orderId: 'entry-order-$positionId',
    tradeId: 'entry-trade-$positionId',
    quantity: 1,
    price: 100,
    remainingQuantity: 1,
  );
  final close = TradingJournalEvent(
    eventId: 'close:$positionId',
    journalTradeId: journalTradeId,
    type: TradingJournalEventType.positionClosed,
    occurredAt: closedAt,
    recordedAt: closedAt,
    source: TradingJournalFactSource.exchange,
    quality: quality,
    scope: TradingJournalScope.position,
    currency: 'USDT',
    asOf: closedAt,
    exchangeEventId: 'close-exchange:$positionId',
    positionId: positionId,
    orderId: 'close-order-$positionId',
    tradeId: 'close-trade-$positionId',
    quantity: 1,
    price: 110,
    grossPnl: grossPnl,
    fee: fee,
    funding: funding,
    remainingQuantity: 0,
    details: const {'closeReason': 'exchange'},
  );
  final ledger = TradingJournalLedger.empty()
      .appendPlan(plan)
      .appendEvent(entry)
      .appendEvent(close);
  return TradingJournalProjector.project(
    ledger: ledger,
    journalTradeId: journalTradeId,
  );
}

TradingJournalPlan _plan({
  required String setupId,
  required String journalTradeId,
  required String positionId,
  required DateTime decidedAt,
}) => TradingJournalPlan(
  journalTradeId: journalTradeId,
  setupId: setupId,
  analysisVersion: '1.0',
  symbol: 'BTCUSDT',
  market: 'USDT_PERPETUAL',
  timeframe: '1h',
  direction: TradingJournalDirection.long,
  strategy: AnalysisStrategy.structureZones.name,
  cadence: 'local-live',
  source: TradingJournalSource.localLive,
  decidedAt: decidedAt,
  decisionPrice: 100,
  entryLower: 99,
  entryUpper: 101,
  plannedEntry: 100,
  originalStopLoss: 95,
  targets: const [105, 110, 115],
  expectedRMultiples: const [1, 2, 3],
  confidencePercent: 70,
  confluence: const ['test'],
  regime: 'trend',
  rationale: 'test',
  invalidation: 'test',
  accountEquity: 1000,
  riskPercent: 1,
  riskBudget: 10,
  leverage: 2,
  expectedMargin: 50,
  passedGates: const ['verified-exchange'],
  blockedGates: const [],
  appVersion: 'test',
  strategyRulesVersion: '1.0',
  positionId: positionId,
  entryOrderId: 'entry-order-$positionId',
  clientId: 'q-local-1234abcd',
);
