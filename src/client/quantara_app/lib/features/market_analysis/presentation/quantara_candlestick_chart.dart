import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/quantara_theme.dart';
import '../domain/market_chart_models.dart';

@immutable
class ChartTradeOverlay {
  const ChartTradeOverlay({
    required this.entry,
    required this.stop,
    required this.targets,
    required this.isLong,
  });

  final double entry;
  final double stop;
  final List<double> targets;
  final bool isLong;
}

class QuantaraCandlestickChart extends StatelessWidget {
  const QuantaraCandlestickChart({
    required this.analysis,
    this.tradeOverlay,
    this.height = 320,
    this.visibleCandleCount = 56,
    super.key,
  });

  final TimeframeChartAnalysis analysis;
  final ChartTradeOverlay? tradeOverlay;
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
            tradeOverlay: tradeOverlay,
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
    required this.tradeOverlay,
    required this.colorScheme,
  });

  final List<ChartCandle> candles;
  final List<ChartPriceZone> zones;
  final double currentValue;
  final ChartTradeOverlay? tradeOverlay;
  final ColorScheme colorScheme;

  @override
  void paint(Canvas canvas, Size size) {
    if (candles.isEmpty || size.isEmpty) {
      return;
    }

    const rightScaleWidth = 66.0;
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
    final overlay = tradeOverlay;
    if (overlay != null) {
      minimum = math.min(minimum, overlay.stop);
      maximum = math.max(maximum, overlay.stop);
      minimum = math.min(minimum, overlay.entry);
      maximum = math.max(maximum, overlay.entry);
      for (final target in overlay.targets) {
        minimum = math.min(minimum, target);
        maximum = math.max(maximum, target);
      }
    }
    final rawRange = maximum - minimum;
    final padding = rawRange == 0 ? maximum.abs() * 0.01 : rawRange * 0.08;
    minimum -= padding;
    maximum += padding;
    final range = math.max(0.00000001, maximum - minimum);

    double yFor(double value) {
      final normalized = (value - minimum) / range;
      return plot.bottom - normalized * plot.height;
    }

    _paintGrid(canvas, plot, minimum, maximum, yFor);
    _paintZones(canvas, plot, yFor);
    if (overlay != null) {
      _paintTradeOverlay(canvas, plot, overlay, yFor);
    }
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
      ..color = colorScheme.outline.withValues(alpha: 0.26)
      ..strokeWidth = 0.8;
    final labelStyle = TextStyle(
      color: colorScheme.onSurface.withValues(alpha: 0.58),
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
          ..color = color.withValues(alpha: 0.035 + zone.strength * 0.07)
          ..style = PaintingStyle.fill,
      );
      canvas.drawLine(
        Offset(plot.left, rect.center.dy),
        Offset(plot.right, rect.center.dy),
        Paint()
          ..color = color.withValues(alpha: 0.28 + zone.strength * 0.3)
          ..strokeWidth = zone.state == ChartZoneState.flipped ? 1.6 : 1,
      );
    }
  }

  void _paintTradeOverlay(
    Canvas canvas,
    Rect plot,
    ChartTradeOverlay overlay,
    double Function(double value) yFor,
  ) {
    final startX = plot.left + plot.width * 0.66;
    final entryY = yFor(overlay.entry);
    final stopY = yFor(overlay.stop);
    final finalTarget = overlay.targets.isEmpty
        ? overlay.entry
        : overlay.targets.last;
    final targetY = yFor(finalTarget);
    final rewardRect = Rect.fromLTRB(
      startX,
      math.min(entryY, targetY),
      plot.right,
      math.max(entryY, targetY),
    );
    final riskRect = Rect.fromLTRB(
      startX,
      math.min(entryY, stopY),
      plot.right,
      math.max(entryY, stopY),
    );

    canvas.drawRect(
      rewardRect,
      Paint()..color = QuantaraColors.success.withValues(alpha: 0.13),
    );
    canvas.drawRect(
      riskRect,
      Paint()..color = QuantaraColors.danger.withValues(alpha: 0.14),
    );
    canvas.drawRect(
      rewardRect,
      Paint()
        ..color = QuantaraColors.success.withValues(alpha: 0.42)
        ..strokeWidth = 0.8
        ..style = PaintingStyle.stroke,
    );
    canvas.drawRect(
      riskRect,
      Paint()
        ..color = QuantaraColors.danger.withValues(alpha: 0.44)
        ..strokeWidth = 0.8
        ..style = PaintingStyle.stroke,
    );

    _paintTradeLine(
      canvas,
      plot,
      startX,
      entryY,
      'ENTRY',
      colorScheme.onSurface,
    );
    _paintTradeLine(canvas, plot, startX, stopY, 'SL', QuantaraColors.danger);
    for (var index = 0; index < overlay.targets.length; index++) {
      _paintTradeLine(
        canvas,
        plot,
        startX,
        yFor(overlay.targets[index]),
        'TP${index + 1}',
        QuantaraColors.success,
      );
    }
  }

  void _paintTradeLine(
    Canvas canvas,
    Rect plot,
    double startX,
    double y,
    String label,
    Color color,
  ) {
    canvas.drawLine(
      Offset(startX, y),
      Offset(plot.right, y),
      Paint()
        ..color = color.withValues(alpha: 0.8)
        ..strokeWidth = 1,
    );
    _paintText(
      canvas,
      label,
      Offset(startX + 5, y - 14),
      TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w800),
      TextDirection.ltr,
    );
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
      canvas.drawLine(
        Offset(centerX, highY),
        Offset(centerX, lowY),
        Paint()
          ..color = color.withValues(alpha: 0.92)
          ..strokeWidth = math.max(1, bodyWidth * 0.16),
      );

      final bodyTop = math.min(openY, closeY);
      final bodyBottom = math.max(openY, closeY);
      final body = Rect.fromLTRB(
        centerX - bodyWidth / 2,
        bodyTop,
        centerX + bodyWidth / 2,
        math.max(bodyTop + 1.5, bodyBottom),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(body, const Radius.circular(1.1)),
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
      canvas.drawRect(volumeBar, Paint()..color = color.withValues(alpha: 0.3));
    }
  }

  void _paintCurrentValue(Canvas canvas, Rect plot, double y) {
    final paint = Paint()
      ..color = colorScheme.primary.withValues(alpha: 0.9)
      ..strokeWidth = 1;
    var x = plot.left;
    while (x < plot.right) {
      canvas.drawLine(
        Offset(x, y),
        Offset(math.min(x + 4, plot.right), y),
        paint,
      );
      x += 8;
    }
    final labelRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(plot.right + 3, y - 10, 61, 20),
      const Radius.circular(4),
    );
    canvas.drawRRect(labelRect, Paint()..color = colorScheme.primary);
    _paintText(
      canvas,
      _formatValue(currentValue),
      Offset(plot.right + 7, y - 7),
      TextStyle(
        color: colorScheme.onPrimary,
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
        oldDelegate.tradeOverlay != tradeOverlay ||
        oldDelegate.colorScheme != colorScheme;
  }
}
