import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/owner_alpha/application/signal_inbox_query.dart';
import 'package:quantara_app/features/owner_alpha/domain/owner_alpha_models.dart';

void main() {
  final now = DateTime.utc(2026, 8, 2, 10);

  test('recommended ordering surfaces open high-score opportunities first', () {
    final entries = [
      _entry('result', score: 95, outcome: SignalOutcome.tp3),
      _entry('low', score: 62),
      _entry('high', score: 84),
      _entry('active', score: 90, outcome: SignalOutcome.active),
    ];

    final result = SignalInboxQuery.apply(
      entries: entries,
      filter: SignalInboxFilter.all,
      sort: SignalInboxSort.recommended,
      now: now,
      isTaken: (_) => false,
    );

    expect(result.map((entry) => entry.setupId), [
      'high',
      'low',
      'active',
      'result',
    ]);
  });

  test('filters distinguish opportunities, active, results and expired', () {
    final entries = [
      _entry('open'),
      _entry('active', outcome: SignalOutcome.active),
      _entry('tp1', outcome: SignalOutcome.tp1),
      _entry('stopped', outcome: SignalOutcome.stopped),
      _entry('expired', validUntil: now.subtract(const Duration(minutes: 1))),
    ];

    List<String> ids(SignalInboxFilter filter) => SignalInboxQuery.apply(
      entries: entries,
      filter: filter,
      sort: SignalInboxSort.newest,
      now: now,
      isTaken: (_) => false,
    ).map((entry) => entry.setupId).toList();

    expect(ids(SignalInboxFilter.opportunities), ['open']);
    expect(ids(SignalInboxFilter.active), containsAll(['active', 'tp1']));
    expect(ids(SignalInboxFilter.results), containsAll(['tp1', 'stopped']));
    expect(ids(SignalInboxFilter.expired), ['expired']);
  });

  test('score sort uses persisted confidence then reward risk', () {
    final result = SignalInboxQuery.apply(
      entries: [
        _entry('rr-low', score: 80, rewardRisk: 1.6),
        _entry('score-high', score: 90, rewardRisk: 1.2),
        _entry('rr-high', score: 80, rewardRisk: 2.4),
      ],
      filter: SignalInboxFilter.all,
      sort: SignalInboxSort.score,
      now: now,
      isTaken: (_) => false,
    );

    expect(result.map((entry) => entry.setupId), [
      'score-high',
      'rr-high',
      'rr-low',
    ]);
  });
}

SignalJournalEntry _entry(
  String id, {
  int score = 70,
  double? rewardRisk = 1.8,
  SignalOutcome outcome = SignalOutcome.pendingEntry,
  DateTime? validUntil,
}) => SignalJournalEntry(
  setupId: id,
  symbol: 'BTCUSDT',
  timeframe: '15m',
  direction: TradeDirection.long,
  strategy: AnalysisStrategy.structureZones,
  strategyVersion: 'test',
  createdAt: DateTime.utc(2026, 8, 2, 9),
  validUntil: validUntil ?? DateTime.utc(2026, 8, 2, 11),
  entryLower: 99,
  entryUpper: 100,
  stopLoss: 98,
  targets: const [102, 104, 106],
  maximumLoss: 10,
  positionSize: 1,
  notionalValue: 100,
  estimatedRoundTripCosts: 0.2,
  recommendedLeverage: 5,
  maximumSafeLeverage: 8,
  selectedLeverage: 5,
  summary: 'test',
  invalidation: 'test',
  confidencePercent: score,
  riskReward: rewardRisk,
  outcome: outcome,
);
