import '../../market_analysis/domain/market_chart_models.dart';

enum TradeDirection { long, short, wait }

final class AlphaMarketQuote {
  const AlphaMarketQuote({
    required this.symbol,
    required this.displayName,
    required this.lastPrice,
    required this.changePercent,
    required this.high24h,
    required this.low24h,
    required this.observedAt,
  });

  final String symbol;
  final String displayName;
  final double lastPrice;
  final double changePercent;
  final double high24h;
  final double low24h;
  final DateTime observedAt;
}

final class TradeIdea {
  const TradeIdea({
    required this.symbol,
    required this.timeframe,
    required this.direction,
    required this.confidencePercent,
    required this.entryLower,
    required this.entryUpper,
    required this.stopLoss,
    required this.targets,
    required this.riskReward,
    required this.maximumLoss,
    required this.positionSize,
    required this.estimatedRoundTripCosts,
    required this.summary,
    required this.invalidation,
    required this.reasons,
  });

  final String symbol;
  final String timeframe;
  final TradeDirection direction;
  final int confidencePercent;
  final double? entryLower;
  final double? entryUpper;
  final double? stopLoss;
  final List<double> targets;
  final double? riskReward;
  final double maximumLoss;
  final double? positionSize;
  final double estimatedRoundTripCosts;
  final String summary;
  final String invalidation;
  final List<String> reasons;

  bool get isActionable => direction != TradeDirection.wait;

  static TradeIdea wait({
    required String symbol,
    required String timeframe,
    required int confidencePercent,
    required double maximumLoss,
    required String summary,
    required String invalidation,
    required List<String> reasons,
  }) {
    return TradeIdea(
      symbol: symbol,
      timeframe: timeframe,
      direction: TradeDirection.wait,
      confidencePercent: confidencePercent,
      entryLower: null,
      entryUpper: null,
      stopLoss: null,
      targets: const [],
      riskReward: null,
      maximumLoss: maximumLoss,
      positionSize: null,
      estimatedRoundTripCosts: 0,
      summary: summary,
      invalidation: invalidation,
      reasons: List.unmodifiable(reasons),
    );
  }
}

final class SymbolRadarResult {
  const SymbolRadarResult({
    required this.quote,
    required this.idea,
    required this.analysis,
  });

  final AlphaMarketQuote quote;
  final TradeIdea idea;
  final TimeframeChartAnalysis analysis;
}

final class OwnerAlphaSnapshot {
  OwnerAlphaSnapshot({
    required Iterable<SymbolRadarResult> radar,
    required this.selectedSymbol,
    required this.selectedTimeframe,
    required this.selectedAnalysis,
    required this.selectedIdea,
    required Map<String, ChartDirection> timeframeDirections,
    required this.generatedAt,
  }) : radar = List.unmodifiable(radar),
       timeframeDirections = Map.unmodifiable(timeframeDirections) {
    if (this.radar.isEmpty) {
      throw ArgumentError('Radar results must not be empty.');
    }
    if (!generatedAt.isUtc) {
      throw ArgumentError('Snapshot time must be UTC.');
    }
  }

  final List<SymbolRadarResult> radar;
  final String selectedSymbol;
  final String selectedTimeframe;
  final TimeframeChartAnalysis selectedAnalysis;
  final TradeIdea selectedIdea;
  final Map<String, ChartDirection> timeframeDirections;
  final DateTime generatedAt;

  List<TradeIdea> get opportunities {
    final result = radar
        .map((item) => item.idea)
        .where((idea) => idea.isActionable)
        .toList(growable: false);
    result.sort(
      (left, right) =>
          right.confidencePercent.compareTo(left.confidencePercent),
    );
    return result;
  }

  AlphaMarketQuote quoteFor(String symbol) {
    return radar.firstWhere((item) => item.quote.symbol == symbol).quote;
  }
}

abstract interface class OwnerAlphaRepository {
  Future<OwnerAlphaSnapshot> scan({
    required List<String> symbols,
    required String selectedSymbol,
    required String selectedTimeframe,
    required double capital,
    required double riskPercent,
    required String languageCode,
  });
}

final class OwnerAlphaSettings {
  const OwnerAlphaSettings({
    required this.symbols,
    required this.capital,
    required this.riskPercent,
  });

  final List<String> symbols;
  final double capital;
  final double riskPercent;
}

abstract interface class OwnerAlphaSettingsStore {
  Future<OwnerAlphaSettings?> load();

  Future<void> save(OwnerAlphaSettings settings);
}
