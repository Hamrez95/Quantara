import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/owner_alpha/domain/strategy_evaluation_account_scorecard.dart';
import 'package:quantara_app/features/owner_alpha/domain/strategy_evaluation_run.dart';

void main() {
  StrategyEvaluationRun run() => StrategyEvaluationRun(
    runId: 'run-1',
    setupId: 'setup-1',
    identity: StrategyEvaluationIdentity(
      strategyId: 'structure_zones',
      strategyVersion: '1.2.3',
      implementationVersion: 'engine/7',
      managementPolicyVersion: 'management/2',
      parameterSchemaVersion: 3,
      normalizedParameters: const <String, Object?>{'cadence': 'balanced'},
      snapshotHash: 'sha256-snapshot',
    ),
    symbol: 'BTCUSDT',
    market: 'linear-perpetual',
    timeframe: '15m',
    rangeStartUtc: DateTime.utc(2026, 8, 1),
    rangeEndUtc: DateTime.utc(2026, 8, 3),
    createdAtUtc: DateTime.utc(2026, 9, 4),
    costModel: const StrategyEvaluationCostModel(
      version: 'bitunix-taker/1',
      takerFeeBps: 6,
      slippageBps: 2,
    ),
    trades: <StrategyEvaluationTrade>[
      StrategyEvaluationTrade(
        tradeId: 'long-win',
        openedAtUtc: DateTime.utc(2026, 8, 1, 1),
        closedAtUtc: DateTime.utc(2026, 8, 1, 2),
        grossPnl: 12,
        cost: 2,
        maximumFavorableExcursion: 14,
        maximumAdverseExcursion: 2,
      ),
      StrategyEvaluationTrade(
        tradeId: 'short-loss',
        openedAtUtc: DateTime.utc(2026, 8, 2, 1),
        closedAtUtc: DateTime.utc(2026, 8, 2, 3),
        grossPnl: -4,
        cost: 1,
        maximumFavorableExcursion: 1,
        maximumAdverseExcursion: 5,
      ),
      StrategyEvaluationTrade(
        tradeId: 'long-breakeven',
        openedAtUtc: DateTime.utc(2026, 8, 2, 4),
        closedAtUtc: DateTime.utc(2026, 8, 2, 5),
        grossPnl: 1,
        cost: 1,
        maximumFavorableExcursion: 2,
        maximumAdverseExcursion: 1,
      ),
    ],
  );

  test('scorecard is scoped to one run and manual evaluation baseline', () {
    final scorecard = StrategyEvaluationAccountScorecard.fromRun(
      run: run(),
      baseline: const StrategyEvaluationCapitalBaseline.manualSetting(1000),
      accounting: const <StrategyEvaluationTradeAccounting>[
        StrategyEvaluationTradeAccounting(
          tradeId: 'long-win',
          side: StrategyEvaluationTradeSide.long,
          fees: 0.8,
          funding: 0.2,
        ),
        StrategyEvaluationTradeAccounting(
          tradeId: 'short-loss',
          side: StrategyEvaluationTradeSide.short,
          fees: 0.5,
          funding: -0.1,
        ),
        StrategyEvaluationTradeAccounting(
          tradeId: 'long-breakeven',
          side: StrategyEvaluationTradeSide.long,
          fees: 0.4,
          funding: 0,
        ),
      ],
    );

    expect(scorecard.openedTrades, 3);
    expect(scorecard.longCount, 2);
    expect(scorecard.shortCount, 1);
    expect(scorecard.wins, 1);
    expect(scorecard.losses, 1);
    expect(scorecard.breakeven, 1);
    expect(scorecard.grossProfit, 13);
    expect(scorecard.grossLoss, 4);
    expect(scorecard.fees, closeTo(1.7, 1e-9));
    expect(scorecard.funding, closeTo(0.1, 1e-9));
    expect(scorecard.netPnl, 5);
    expect(scorecard.currentEvaluationEquity, 1005);
    expect(scorecard.roi, closeTo(0.005, 1e-12));
    expect(scorecard.duration, const Duration(days: 2));
    expect(scorecard.grantsLocalLiveAuthority, isFalse);
    expect(scorecard.toJson()['startingCapitalSource'], 'manualSetting');
  });

  test('missing or foreign trade accounting fails closed', () {
    expect(
      () => StrategyEvaluationAccountScorecard.fromRun(
        run: run(),
        baseline: const StrategyEvaluationCapitalBaseline.manualSetting(1000),
        accounting: const <StrategyEvaluationTradeAccounting>[],
      ),
      throwsArgumentError,
    );

    expect(
      () => StrategyEvaluationAccountScorecard.fromRun(
        run: run(),
        baseline: const StrategyEvaluationCapitalBaseline.manualSetting(1000),
        accounting: const <StrategyEvaluationTradeAccounting>[
          StrategyEvaluationTradeAccounting(
            tradeId: 'foreign-trade',
            side: StrategyEvaluationTradeSide.long,
            fees: 0,
            funding: 0,
          ),
        ],
      ),
      throwsArgumentError,
    );
  });

  test('invalid manual capital never falls back to exchange history', () {
    expect(
      () => StrategyEvaluationAccountScorecard.fromRun(
        run: run(),
        baseline: const StrategyEvaluationCapitalBaseline.manualSetting(0),
        accounting: const <StrategyEvaluationTradeAccounting>[],
      ),
      throwsArgumentError,
    );
  });
}
