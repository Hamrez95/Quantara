import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/quantara_theme.dart';
import '../domain/market_chart_models.dart';

class QuantaraCandlestickChart extends StatelessWidget {
  const QuantaraCandlestickChart({
    required this.analysis,
    this.height = 320,
    this.visibleCandleCount = 56,
    super.key,
  });

  final TimeframeChartAnalysis analysis;
  final double height;
  final int visibleCandleCount;

  @override
  Widget build(BuildContext context) {
    final candles = analysis.candles.length <= visibleCandleCount
        ? analysis.candles.toList(growable: false)
        : analysis.candles
              .skip(analysis.candles.length - visibleCandleCount)
              .toList(growable: false);
    return RepaintBoundary(
      child: SizedBox(
        key: ValueKey(
          'candles-${analysis.symbol}-${analysis.timeframe}-${analysis.fingerprint}',
        ),
        height: height,
        width: double.infinity,
        child: CustomPaint(
          painter: _CandlestickPainter(
            candles: candles,
            zones: analysis.strongestZones,
            currentValue: analysis.latestCandle.close,
            colorScheme: Theme.of(context).colorScheme,
          ),
        ),
      ),
    );
  }
}

final class _CandlestickPainter extends CustomPainter {
  const _CandlestickPainter({
    required this.candles,
    required this.zones,
    required this.currentValue,
    required this.colorScheme,
  });

  final List<ChartCandle> candles;
  final List<ChartPriceZone> zones;
  final double currentValue;
  final ColorScheme colorScheme;

  @override
  void paint(Canvas canvas, Size size) {
    if (candles.isEmpty || size.isEmpty) {
      return;
    }

    const rightScaleWidth = 62.0;
    const topPadding = 12.0;
    const bottomAxisHeight = 26.0;
    const volumeHeight = 42.0;
    const volumeGap = 10.0;
    final plot = Rect.fromLTRB(
      6,
      topPadding,
      math.max(7, size.width - rightScaleWidth),
      math.max(
        topPadding + 1,
        size.height - bottomAxisHeight - volumeHeight - volumeGap,
      ),
    );
    final volumeRect = Rect.fromLTRB(
      plot.left,
      plot.bottom + volumeGap,
      plot.right,
      size.height - bottomAxisHeight,
    );

    var minimum = candles.map((item) => item.low).reduce(math.min);
    var maximum = candles.map((item) => item.high).reduce(math.max);
    for (final zone in zones) {
      minimum = math.min(minimum, zone.lower);
      maximum = math.max(maximum, zone.upper);
    }
    final rawRange = maximum - minimum;
    final padding = rawRange == 0 ? maximum * 0.01 : rawRange * 0.08;
    minimum -= padding;
    maximum += padding;
    final range = math.max(0.00000001, maximum - minimum);

    double yFor(double value) {
      final normalized = (value - minimum) / range;
      return plot.bottom - normalized * plot.height;
    }

    _paintGrid(canvas, plot, minimum, maximum, yFor);
    _paintZones(canvas, plot, yFor);
    _paintCandles(canvas, plot, volumeRect, yFor);
    _paintCurrentValue(canvas, plot, yFor(currentValue));
    _paintTimeAxis(canvas, plot, volumeRect);
  }

  void _paintGrid(
    Canvas canvas,
    Rect plot,
    double minimum,
    double maximum,
    double Function(double value) yFor,
  ) {
    final gridPaint = Paint()
      ..color = colorScheme.outline.withValues(alpha: 0.24)
      ..strokeWidth = 1;
    final labelStyle = TextStyle(
      color: colorScheme.onSurface.withValues(alpha: 0.55),
      fontSize: 10,
      fontWeight: FontWeight.w600,
    );

    for (var index = 0; index <= 4; index++) {
      final value = minimum + (maximum - minimum) * index / 4;
      final y = yFor(value);
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), gridPaint);
      _paintText(
        canvas,
        _formatValue(value),
        Offset(plot.right + 7, y - 7),
        labelStyle,
        TextDirection.ltr,
      );
    }

    for (var index = 0; index <= 4; index++) {
      final x = plot.left + plot.width * index / 4;
      canvas.drawLine(Offset(x, plot.top), Offset(x, plot.bottom), gridPaint);
    }
  }

  void _paintZones(
    Canvas canvas,
    Rect plot,
    double Function(double value) yFor,
  ) {
    for (final zone in zones) {
      final color = switch (zone.role) {
        ChartZoneRole.support => QuantaraColors.success,
        ChartZoneRole.resistance => QuantaraColors.warning,
        ChartZoneRole.pivot => QuantaraColors.violet,
      };
      final top = yFor(zone.upper);
      final bottom = yFor(zone.lower);
      final rect = Rect.fromLTRB(plot.left, top, plot.right, bottom);
      canvas.drawRect(
        rect,
        Paint()
          ..color = color.withValues(alpha: 0.045 + zone.strength * 0.09)
          ..style = PaintingStyle.fill,
      );
      canvas.drawLine(
        Offset(plot.left, rect.center.dy),
        Offset(plot.right, rect.center.dy),
        Paint()
          ..color = color.withValues(alpha: 0.35 + zone.strength * 0.35)
          ..strokeWidth = zone.state == ChartZoneState.flipped ? 1.8 : 1.2,
      );
    }
  }

  void _paintCandles(
    Canvas canvas,
    Rect plot,
    Rect volumeRect,
    double Function(double value) yFor,
  ) {
    final slot = plot.width / candles.length;
    final bodyWidth = math.max(2.0, slot * 0.62);
    final maximumVolume = candles.map((item) => item.volume).reduce(math.max);

    for (var index = 0; index < candles.length; index++) {
      final candle = candles[index];
      final centerX = plot.left + slot * (index + 0.5);
      final color = candle.isBullish
          ? QuantaraColors.success
          : QuantaraColors.danger;
      final highY = yFor(candle.high);
      final lowY = yFor(candle.low);
      final openY = yFor(candle.open);
      final closeY = yFor(candle.close);
      final wickPaint = Paint()
        ..color = color.withValues(alpha: 0.9)
        ..strokeWidth = math.max(1, bodyWidth * 0.16);
      canvas.drawLine(Offset(centerX, highY), Offset(centerX, lowY), wickPaint);

      final bodyTop = math.min(openY, closeY);
      final bodyBottom = math.max(openY, closeY);
      final body = Rect.fromLTRB(
        centerX - bodyWidth / 2,
        bodyTop,
        centerX + bodyWidth / 2,
        math.max(bodyTop + 1.5, bodyBottom),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(body, const Radius.circular(1.2)),
        Paint()
          ..color = color
          ..style = PaintingStyle.fill,
      );

      final volumeRatio = maximumVolume == 0
          ? 0
          : candle.volume / maximumVolume;
      final volumeBar = Rect.fromLTRB(
        centerX - bodyWidth / 2,
        volumeRect.bottom - volumeRect.height * volumeRatio,
        centerX + bodyWidth / 2,
        volumeRect.bottom,
      );
      canvas.drawRect(
        volumeBar,
        Paint()..color = color.withValues(alpha: 0.28),
      );
    }
  }

  void _paintCurrentValue(Canvas canvas, Rect plot, double y) {
    final paint = Paint()
      ..color = colorScheme.primary.withValues(alpha: 0.85)
      ..strokeWidth = 1.2;
    var x = plot.left;
    while (x < plot.right) {
      canvas.drawLine(
        Offset(x, y),
        Offset(math.min(x + 5, plot.right), y),
        paint,
      );
      x += 9;
    }
    final labelRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(plot.right + 3, y - 10, 57, 20),
      const Radius.circular(5),
    );
    canvas.drawRRect(
      labelRect,
      Paint()..color = colorScheme.primary.withValues(alpha: 0.18),
    );
    _paintText(
      canvas,
      _formatValue(currentValue),
      Offset(plot.right + 7, y - 7),
      TextStyle(
        color: colorScheme.primary,
        fontSize: 9.5,
        fontWeight: FontWeight.w800,
      ),
      TextDirection.ltr,
    );
  }

  void _paintTimeAxis(Canvas canvas, Rect plot, Rect volumeRect) {
    final style = TextStyle(
      color: colorScheme.onSurface.withValues(alpha: 0.48),
      fontSize: 9.5,
      fontWeight: FontWeight.w600,
    );
    final indexes = <int>[0, candles.length ~/ 2, candles.length - 1];
    for (final index in indexes) {
      final candle = candles[index];
      final x =
          plot.left + plot.width * index / math.max(1, candles.length - 1);
      final label = '${candle.openTime.month}/${candle.openTime.day}';
      _paintText(
        canvas,
        label,
        Offset(x - 12, volumeRect.bottom + 7),
        style,
        TextDirection.ltr,
      );
    }
  }

  static String _formatValue(double value) {
    if (value.abs() >= 10000) {
      return value.toStringAsFixed(0);
    }
    if (value.abs() >= 1) {
      return value.toStringAsFixed(2);
    }
    return value.toStringAsFixed(4);
  }

  static void _paintText(
    Canvas canvas,
    String value,
    Offset offset,
    TextStyle style,
    TextDirection direction,
  ) {
    final painter = TextPainter(
      text: TextSpan(text: value, style: style),
      textDirection: direction,
      maxLines: 1,
    )..layout();
    painter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _CandlestickPainter oldDelegate) {
    return oldDelegate.candles != candles ||
        oldDelegate.zones != zones ||
        oldDelegate.currentValue != currentValue ||
        oldDelegate.colorScheme != colorScheme;
  }
}
