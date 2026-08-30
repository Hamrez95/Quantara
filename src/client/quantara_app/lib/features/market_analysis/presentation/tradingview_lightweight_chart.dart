import 'package:flutter/material.dart';

import '../../../core/formatting/number_formatters.dart';
import '../../../core/localization/app_strings.dart';
import '../../owner_alpha/domain/owner_alpha_models.dart';
import '../domain/market_chart_models.dart';
import 'quantara_candlestick_chart.dart';

abstract final class ChartSignalOverlayPolicy {
  static ChartTradeOverlay? create({
    required TimeframeChartAnalysis analysis,
    required SignalJournalEntry signal,
  }) {
    if (!canRender(analysis: analysis, signal: signal)) return null;
    return ChartTradeOverlay(
      entry: (signal.entryLower! + signal.entryUpper!) / 2,
      stop: signal.stopLoss!,
      targets: signal.targets,
      isLong: signal.direction == TradeDirection.long,
    );
  }

  static bool canRender({
    required TimeframeChartAnalysis analysis,
    required SignalJournalEntry signal,
  }) {
    final entryLower = signal.entryLower;
    final entryUpper = signal.entryUpper;
    final stopLoss = signal.stopLoss;
    if (analysis.symbol != signal.symbol ||
        analysis.timeframe != signal.timeframe ||
        signal.direction == TradeDirection.wait ||
        entryLower == null ||
        entryUpper == null ||
        stopLoss == null ||
        !entryLower.isFinite ||
        !entryUpper.isFinite ||
        !stopLoss.isFinite ||
        entryLower <= 0 ||
        entryUpper < entryLower ||
        stopLoss <= 0 ||
        signal.targets.length != 3 ||
        signal.targets.any((target) => !target.isFinite || target <= 0)) {
      return false;
    }
    final candles = analysis.candles;
    if (candles.isEmpty ||
        candles.any(
          (candle) =>
              !candle.open.isFinite ||
              !candle.high.isFinite ||
              !candle.low.isFinite ||
              !candle.close.isFinite,
        )) {
      return false;
    }
    final coverageStart = candles.first.openTime;
    final lastCandleEnd = candles.last.openTime.add(
      _timeframeDuration(analysis.timeframe),
    );
    final coverageEnd = analysis.generatedAt.isAfter(lastCandleEnd)
        ? analysis.generatedAt
        : lastCandleEnd;
    return !coverageStart.isAfter(signal.createdAt) &&
        !coverageEnd.isBefore(signal.createdAt);
  }

  static Duration _timeframeDuration(String timeframe) => switch (timeframe) {
    '5m' => const Duration(minutes: 5),
    '15m' => const Duration(minutes: 15),
    '1h' => const Duration(hours: 1),
    '4h' => const Duration(hours: 4),
    '1D' || '1d' => const Duration(days: 1),
    _ => const Duration(minutes: 1),
  };
}

class TradingViewLightweightChart extends StatelessWidget {
  const TradingViewLightweightChart({
    required this.analysis,
    this.idea,
    this.frozenSignal,
    this.tradeOverlay,
    this.height = 390,
    super.key,
  });

  final TimeframeChartAnalysis analysis;
  final TradeIdea? idea;
  final SignalJournalEntry? frozenSignal;
  final ChartTradeOverlay? tradeOverlay;
  final double height;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final frozen = frozenSignal;
    final currentIdea = idea;
    final overlay =
        tradeOverlay ??
        (frozen != null
            ? ChartSignalOverlayPolicy.create(
                analysis: analysis,
                signal: frozen,
              )
            : currentIdea?.isActionable == true
            ? ChartTradeOverlay(
                entry: (currentIdea!.entryLower! + currentIdea.entryUpper!) / 2,
                stop: currentIdea.stopLoss!,
                targets: currentIdea.targets,
                isLong: currentIdea.direction == TradeDirection.long,
              )
            : null);
    final chart = RepaintBoundary(
      key: ValueKey(
        'quantara-chart-${analysis.fingerprint}-${frozen?.setupId ?? currentIdea?.setupId ?? 'explicit-overlay'}',
      ),
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
