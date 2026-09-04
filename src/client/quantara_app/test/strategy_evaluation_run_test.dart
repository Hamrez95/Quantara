import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/owner_alpha/domain/strategy_evaluation_run.dart';

void main() {
  StrategyEvaluationTrade trade({
    required String id,
    required double grossPnl,
    required double cost,
    required int day,
    double mfe = 3,
    double mae = 1,
  }) => StrategyEvaluationTrade(
    tradeId: id,
    openedAtUtc: DateTime.utc(2026, 1, day, 10),
    closedAtUtc: DateTime.utc(2026, 1, day, 11),
    grossPnl: grossPnl,
    cost: cost,
    maximumFavorableExcursion: mfe,
    maximumAdverseExcursion: mae,
  );

  test('scorecard formulas are deterministic and include costs', () {
    final trades = <StrategyEvaluationTrade>[
      trade(id: 'a', grossPnl: 10, cost: 1, day: 1, mfe: 12, mae: 2),
      trade(id: 'b', grossPnl: -4, cost: 1, day: 2, mfe: 1, mae: 6),
      trade(id: 'c', grossPnl: 5, cost: 1, day: 3, mfe: 7, mae: 1),
    ];

    final first = StrategyEvaluationScorecard.fromTrades(trades);
    final second = StrategyEvaluationScorecard.fromTrades(trades);

    expect(first.toJson(), second.toJson());
    expect(first.tradeCount, 3);
    expect(first.winRate, closeTo(2 / 3, 1e-12));
    expect(first.averageWinner, 6.5);
    expect(first.averageLoser, -5);
    expect(first.expectancy, closeTo(8 / 3, 1e-12));
    expect(first.profitFactor, closeTo(13 / 5, 1e-12));
    expect(first.maximumDrawdown, 5);
    expect(first.totalGrossPnl, 11);
    expect(first.totalCosts, 3);
    expect(first.totalNetPnl, 8);
    expect(first.averageMfe, closeTo(20 / 3, 1e-12));
    expect(first.averageMae, 3);
    expect(first.totalExposure, const Duration(hours: 3));
    expect(first.insufficientSamples, isTrue);
  });

  test('no losses leaves profit factor undefined rather than infinite', () {
    final scorecard = StrategyEvaluationScorecard.fromTrades(<StrategyEvaluationTrade>[
      trade(id: 'a', grossPnl: 3, cost: 1, day: 1),
      trade(id: 'b', grossPnl: 4, cost: 1, day: 2),
    ]);

    expect(scorecard.profitFactor, isNull);
    expect(scorecard.totalNetPnl, 5);
  });

  test('low sample state is explicit and clears at decision threshold', () {
    final trades = List<StrategyEvaluationTrade>.generate(
      StrategyEvaluationScorecard.minimumDecisionSampleSize,
      (index) => StrategyEvaluationTrade(
        tradeId: 'trade-$index',
        openedAtUtc: DateTime.utc(2026, 1, 1).add(Duration(hours: index * 2)),
        closedAtUtc: DateTime.utc(2026, 1, 1).add(Duration(hours: index * 2 + 1)),
        grossPnl: 1,
        cost: 0.1,
        maximumFavorableExcursion: 1.5,
        maximumAdverseExcursion: 0.5,
      ),
    );

    expect(
      StrategyEvaluationScorecard.fromTrades(trades.take(29)).insufficientSamples,
      isTrue,
    );
    expect(
      StrategyEvaluationScorecard.fromTrades(trades).insufficientSamples,
      isFalse,
    );
  });

  test('invalid or impossible observations are rejected', () {
    expect(
      () => StrategyEvaluationScorecard.fromTrades(<StrategyEvaluationTrade>[
        StrategyEvaluationTrade(
          tradeId: 'bad',
          openedAtUtc: DateTime.utc(2026, 1, 2),
          closedAtUtc: DateTime.utc(2026, 1, 1),
          grossPnl: 1,
          cost: 0,
          maximumFavorableExcursion: 1,
          maximumAdverseExcursion: 1,
        ),
      ]),
      throwsArgumentError,
    );
    expect(
      () => StrategyEvaluationScorecard.fromTrades(<StrategyEvaluationTrade>[
        trade(id: 'bad-cost', grossPnl: 1, cost: -1, day: 1),
      ]),
      throwsArgumentError,
    );
  });

  test('run carries exact immutable provenance and grants no live authority', () {
    final parameters = <String, Object?>{'cadence': 'balanced'};
    final identity = StrategyEvaluationIdentity(
      strategyId: 'structure_zones',
      strategyVersion: '1.0.0',
      implementationVersion: 'professional-strategy/1.0',
      managementPolicyVersion: 'structure-zones-management/1.0',
      parameterSchemaVersion: 1,
      normalizedParameters: parameters,
      snapshotHash: 'snapshot-123',
    );
    parameters['cadence'] = 'fast';

    final run = StrategyEvaluationRun(
      runId: 'evaluation-43',
      setupId: 'setup-43',
      identity: identity,
      symbol: 'BTCUSDT',
      market: 'crypto-perpetual',
      timeframe: '15m',
      rangeStartUtc: DateTime.utc(2026, 1, 1),
      rangeEndUtc: DateTime.utc(2026, 2, 1),
      createdAtUtc: DateTime.utc(2026, 2, 2),
      costModel: const StrategyEvaluationCostModel(
        version: 'bitunix-costs/1',
        takerFeeBps: 6,
        slippageBps: 2,
      ),
      deterministicSeed: 43,
      trades: <StrategyEvaluationTrade>[
        trade(id: 'a', grossPnl: 3, cost: 1, day: 1),
      ],
    );

    expect(identity.normalizedParameters['cadence'], 'balanced');
    expect(
      () => identity.normalizedParameters['cadence'] = 'mutated',
      throwsUnsupportedError,
    );
    expect(run.toJson()['runId'], 'evaluation-43');
    expect(run.toJson()['scorecard'], run.scorecard.toJson());
    expect(run.grantsLocalLiveAuthority, isFalse);
  });
}
