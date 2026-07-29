import 'package:flutter/material.dart';

import '../../../core/formatting/number_formatters.dart';
import '../../../core/localization/app_strings.dart';
import '../../owner_alpha/domain/owner_alpha_models.dart';
import '../domain/market_chart_models.dart';
import 'quantara_candlestick_chart.dart';

class TradingViewLightweightChart extends StatelessWidget {
  const TradingViewLightweightChart({
    required this.analysis,
    required this.idea,
    this.height = 390,
    super.key,
  });

  final TimeframeChartAnalysis analysis;
  final TradeIdea idea;
  final double height;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final overlay = idea.isActionable
        ? ChartTradeOverlay(
            entry: (idea.entryLower! + idea.entryUpper!) / 2,
            stop: idea.stopLoss!,
            targets: idea.targets,
            isLong: idea.direction == TradeDirection.long,
          )
        : null;
    final chart = RepaintBoundary(
      key: ValueKey('quantara-chart-${analysis.fingerprint}-${idea.setupId}'),
      child: QuantaraCandlestickChart(
        analysis: analysis,
        tradeOverlay: overlay,
        height: height,
      ),
    );
    return Semantics(
      container: true,
      image: true,
      label: strings.chartSemantic(
        symbol: analysis.symbol,
        timeframe: analysis.timeframe,
        direction: strings.direction(analysis.direction.name),
        close: QuantaraNumberFormat.marketValue(analysis.latestCandle.close),
        zones: analysis.strongestZones.length,
      ),
      child: ExcludeSemantics(child: chart),
    );
  }
}
