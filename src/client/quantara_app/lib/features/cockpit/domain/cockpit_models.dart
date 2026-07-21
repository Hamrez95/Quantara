enum AppEnvironment { demo, paper, shadow, realMoneyLocked }

enum AnalysisDecision { bullish, bearish, noTrade }

enum MarketRegime { trending, ranging, volatile, uncertain }

enum EvidenceImpact { supportive, caution, neutral }

final class MarketQuote {
  const MarketQuote({
    required this.symbol,
    required this.displayName,
    required this.price,
    required this.changePercent,
    required this.spreadBps,
    required this.freshness,
    required this.sparkline,
  });

  final String symbol;
  final String displayName;
  final double price;
  final double changePercent;
  final double spreadBps;
  final Duration freshness;
  final List<double> sparkline;
}

final class AnalysisFactor {
  const AnalysisFactor({
    required this.title,
    required this.detail,
    required this.impact,
  });

  final String title;
  final String detail;
  final EvidenceImpact impact;
}

final class ExplainableAnalysis {
  const ExplainableAnalysis({
    required this.symbol,
    required this.decision,
    required this.confidencePercent,
    required this.regime,
    required this.summary,
    required this.invalidation,
    required this.freshness,
    required this.factors,
  });

  final String symbol;
  final AnalysisDecision decision;
  final int confidencePercent;
  final MarketRegime regime;
  final String summary;
  final String invalidation;
  final Duration freshness;
  final List<AnalysisFactor> factors;
}

final class PaperAccountSummary {
  const PaperAccountSummary({
    required this.equity,
    required this.availableBalance,
    required this.usedMargin,
    required this.dailyPnl,
    required this.openPositions,
    required this.maximumDailyRiskPercent,
    required this.currentDailyRiskPercent,
  });

  final double equity;
  final double availableBalance;
  final double usedMargin;
  final double dailyPnl;
  final int openPositions;
  final double maximumDailyRiskPercent;
  final double currentDailyRiskPercent;
}

final class CockpitSnapshot {
  const CockpitSnapshot({
    required this.environment,
    required this.watchlist,
    required this.analysis,
    required this.paperAccount,
    required this.marketStatus,
  });

  final AppEnvironment environment;
  final List<MarketQuote> watchlist;
  final ExplainableAnalysis analysis;
  final PaperAccountSummary paperAccount;
  final String marketStatus;
}

abstract interface class CockpitRepository {
  Future<CockpitSnapshot> load();
}

