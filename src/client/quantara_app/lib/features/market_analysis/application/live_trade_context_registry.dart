import 'package:flutter/foundation.dart';

import '../../owner_alpha/domain/owner_alpha_models.dart';
import '../domain/market_chart_models.dart';

@immutable
final class LiveTradeContext {
  const LiveTradeContext({
    required this.analysis,
    required this.idea,
    required this.observedAt,
  });

  final TimeframeChartAnalysis analysis;
  final TradeIdea idea;
  final DateTime observedAt;
}

/// In-memory, public-market-only bridge between the analysis runtime and
/// read-only Journal presentation. Nothing in this registry grants exchange
/// mutation authority and no API credential is stored here.
abstract final class LiveTradeContextRegistry {
  static final ValueNotifier<Map<String, LiveTradeContext>> listenable =
      ValueNotifier<Map<String, LiveTradeContext>>(const {});

  static String key({
    required String symbol,
    required String timeframe,
    required AnalysisStrategy strategy,
  }) =>
      '${symbol.trim().toUpperCase()}|${timeframe.trim()}|${strategy.name}';

  static LiveTradeContext? find({
    required String symbol,
    required String timeframe,
    required String strategy,
  }) {
    final parsedStrategy = AnalysisStrategy.values.where(
      (item) => item.name == strategy.trim(),
    );
    if (parsedStrategy.isEmpty) return null;
    return listenable.value[key(
      symbol: symbol,
      timeframe: timeframe,
      strategy: parsedStrategy.first,
    )];
  }

  static void publish({
    required TimeframeChartAnalysis analysis,
    required TradeIdea idea,
  }) {
    if (analysis.symbol.trim().toUpperCase() != idea.symbol.trim().toUpperCase() ||
        analysis.timeframe.trim() != idea.timeframe.trim()) {
      return;
    }
    final next = Map<String, LiveTradeContext>.of(listenable.value);
    next[key(
      symbol: idea.symbol,
      timeframe: idea.timeframe,
      strategy: idea.strategy,
    )] = LiveTradeContext(
      analysis: analysis,
      idea: idea,
      observedAt: analysis.generatedAt.toUtc(),
    );
    listenable.value = Map.unmodifiable(next);
  }

  @visibleForTesting
  static void clear() {
    listenable.value = const {};
  }
}
