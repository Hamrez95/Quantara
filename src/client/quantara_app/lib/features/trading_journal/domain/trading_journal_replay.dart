import '../../market_analysis/domain/market_chart_models.dart';
import 'trading_journal_chart_snapshot.dart';
import 'trading_journal_models.dart';

/// Resolves the immutable chart that belongs to the trade decision itself.
/// Newer live market data is intentionally not consulted here: callers either
/// receive attributable decision-time evidence or an explicit null for legacy
/// records that predate chart snapshots.
abstract final class TradingJournalReplay {
  static TimeframeChartAnalysis? decisionChart(TradingJournalPlan? plan) {
    if (plan == null) return null;
    return TradingJournalChartSnapshot.decodeFromIndicatorSnapshot(
      plan.indicatorSnapshot,
      symbol: plan.symbol,
      timeframe: plan.timeframe,
    );
  }

  static bool hasDecisionChart(TradingJournalPlan? plan) =>
      decisionChart(plan) != null;
}
