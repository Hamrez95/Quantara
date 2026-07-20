import 'dart:math' as math;

import 'package:flutter/material.dart';

class SectionCard extends StatelessWidget {
  const SectionCard({
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.semanticLabel,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final card = DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: scheme.outline.withValues(alpha: 0.8)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Padding(padding: padding, child: child),
    );

    if (semanticLabel == null) {
      return card;
    }

    return Semantics(
      container: true,
      label: semanticLabel,
      child: card,
    );
  }
}

class StatusPill extends StatelessWidget {
  const StatusPill({
    required this.label,
    required this.color,
    this.icon,
    super.key,
  });

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.32)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 15, color: color),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class MetricTile extends StatelessWidget {
  const MetricTile({
    required this.label,
    required this.value,
    this.caption,
    this.valueColor,
    super.key,
  });

  final String label;
  final String value;
  final String? caption;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Semantics(
      label: '$label: $value',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.62),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            value,
            style: textTheme.titleLarge?.copyWith(
              color: valueColor,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
            ),
          ),
          if (caption != null) ...[
            const SizedBox(height: 4),
            Text(
              caption!,
              style: textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.52),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class RiskProgress extends StatelessWidget {
  const RiskProgress({
    required this.current,
    required this.maximum,
    super.key,
  });

  final double current;
  final double maximum;

  @override
  Widget build(BuildContext context) {
    final safeMaximum = maximum <= 0 ? 1 : maximum;
    final value = (current / safeMaximum).clamp(0.0, 1.0);
    final scheme = Theme.of(context).colorScheme;

    return Semantics(
      label: 'Risk usage ${(value * 100).round()} percent',
      value: '${(value * 100).round()}%',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: LinearProgressIndicator(
          value: value,
          minHeight: 9,
          backgroundColor: scheme.outline.withValues(alpha: 0.35),
          valueColor: AlwaysStoppedAnimation<Color>(
            value > 0.75 ? scheme.error : scheme.primary,
          ),
        ),
      ),
    );
  }
}

class SparklineChart extends StatelessWidget {
  const SparklineChart({
    required this.values,
    required this.color,
    this.height = 48,
    super.key,
  });

  final List<double> values;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(
          painter: _SparklinePainter(values: values, color: color),
        ),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  const _SparklinePainter({required this.values, required this.color});

  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2 || size.isEmpty) {
      return;
    }

    final minimum = values.reduce(math.min);
    final maximum = values.reduce(math.max);
    final range = maximum - minimum;
    final path = Path();

    for (var index = 0; index < values.length; index++) {
      final dx = size.width * index / (values.length - 1);
      final normalized = range == 0 ? 0.5 : (values[index] - minimum) / range;
      final dy = size.height - (normalized * (size.height - 8)) - 4;
      if (index == 0) {
        path.moveTo(dx, dy);
      } else {
        path.lineTo(dx, dy);
      }
    }

    final stroke = Paint()
      ..color = color
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    canvas.drawPath(path, stroke);

    final fillPath = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    final fill = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          color.withValues(alpha: 0.22),
          color.withValues(alpha: 0),
        ],
      ).createShader(Offset.zero & size)
      ..style = PaintingStyle.fill;
    canvas.drawPath(fillPath, fill);
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) {
    return oldDelegate.values != values || oldDelegate.color != color;
  }
}
