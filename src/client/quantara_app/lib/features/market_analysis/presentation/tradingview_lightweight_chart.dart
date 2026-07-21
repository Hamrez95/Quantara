import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
    final androidRelease =
        kReleaseMode &&
        !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android;
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final lines = <Map<String, Object>>[];
    if (idea.isActionable) {
      lines.addAll([
        {
          'price': (idea.entryLower! + idea.entryUpper!) / 2,
          'title': 'ENTRY',
          'color': '#43D7C4',
        },
        {'price': idea.stopLoss!, 'title': 'STOP', 'color': '#FF7280'},
        for (var index = 0; index < idea.targets.length; index++)
          {
            'price': idea.targets[index],
            'title': 'TP${index + 1}',
            'color': '#39D58A',
          },
      ]);
    }

    final chart = androidRelease
        ? ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              key: ValueKey('tradingview-${analysis.fingerprint}-$dark'),
              height: height,
              width: double.infinity,
              child: AndroidView(
                viewType: 'quantara/tradingview_chart',
                layoutDirection: TextDirection.ltr,
                creationParamsCodec: const StandardMessageCodec(),
                creationParams: {
                  'symbol': analysis.symbol,
                  'timeframe': analysis.timeframe,
                  'background': _hex(scheme.surface),
                  'textColor': _hex(
                    scheme.onSurface.withValues(alpha: dark ? 0.72 : 0.68),
                  ),
                  'gridColor': _hex(scheme.outline.withValues(alpha: 0.24)),
                  'candles': [
                    for (final candle in analysis.candles)
                      {
                        'time': candle.openTime.millisecondsSinceEpoch ~/ 1000,
                        'open': candle.open,
                        'high': candle.high,
                        'low': candle.low,
                        'close': candle.close,
                        'volume': candle.volume,
                      },
                  ],
                  'zones': [
                    for (final zone in analysis.strongestZones)
                      {
                        'lower': zone.lower,
                        'upper': zone.upper,
                        'strength': zone.strength,
                        'role': zone.role.name,
                      },
                  ],
                  'lines': lines,
                },
              ),
            ),
          )
        : QuantaraCandlestickChart(analysis: analysis, height: height);
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

  static String _hex(Color color) {
    final value = color.toARGB32() & 0xFFFFFF;
    return '#${value.toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }
}
