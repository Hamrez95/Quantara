import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/owner_alpha/domain/strategy_evaluation_extended_scorecard.dart';
import 'package:quantara_app/features/owner_alpha/domain/strategy_evaluation_run.dart';

void main() {
  StrategyEvaluationTrade trade({
    required String id,
    required int startHour,
    required int durationHours,
    required double grossPnl,
    required double cost,
  }) => StrategyEvaluationTrade(
    tradeId: id,
    openedAtUtc: DateTime.utc(2026, 9, 1, startHour),
    closedAtUtc: DateTime.utc(2026, 9, 1, startHour + durationHours),
    grossPnl: grossPnl,
    cost: cost,
    maximumFavorableExcursion: grossPnl > 0 ? grossPnl : 0,
    maximumAdverseExcursion: grossPnl < 0 ? grossPnl.abs() : 0,
  );

  test('derives wins losses breakeven gross legs and holding time', () {
    final scorecard = StrategyEvaluationExtendedScorecard.fromTrades(
      <StrategyEvaluationTrade>[
        trade(id: 'w1', startHour: 0, durationHours: 1, grossPnl: 12, cost: 2),
        trade(id: 'l1', startHour: 2, durationHours: 2, grossPnl: -5, cost: 1),
        trade(id: 'b1', startHour: 5, durationHours: 3, grossPnl: 1, cost: 1),
        trade(id: 'l2', startHour: 9, durationHours: 2, grossPnl: -3, cost: 1),
        trade(id: 'l3', startHour: 12, durationHours: 2, grossPnl: -2, cost: 1),
      ],
    );

    expect(scorecard.wins, 1);
    expect(scorecard.losses, 3);
    expect(scorecard.breakeven, 1);
    expect(scorecard.grossProfit, 10);
    expect(scorecard.grossLoss, 13);
    expect(scorecard.averageHoldingTime, const Duration(hours: 2));
    expect(scorecard.maximumLosingStreak, 2);
  });

  test('empty scorecard remains deterministic', () {
    final scorecard = StrategyEvaluationExtendedScorecard.fromTrades(
      const <StrategyEvaluationTrade>[],
    );

    expect(scorecard.wins, 0);
    expect(scorecard.losses, 0);
    expect(scorecard.breakeven, 0);
    expect(scorecard.grossProfit, 0);
    expect(scorecard.grossLoss, 0);
    expect(scorecard.averageHoldingTime, Duration.zero);
    expect(scorecard.maximumLosingStreak, 0);
  });
}
