import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/quantara_theme.dart';

class SectionCard extends StatelessWidget {
  const SectionCard({
    required this.child,
    this.padding = const EdgeInsets.all(QuantaraSpacing.md),
    this.semanticLabel,
    this.onTap,
    this.accentColor,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final String? semanticLabel;
  final VoidCallback? onTap;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final radius = BorderRadius.circular(QuantaraRadius.card);
    Widget card = Material(
      color: scheme.surface,
      elevation: dark ? 0 : 0.5,
      shadowColor: Colors.black.withValues(alpha: 0.12),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: scheme.outline.withValues(alpha: 0.78)),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Stack(
          children: [
            Padding(padding: padding, child: child),
            if (accentColor != null)
              PositionedDirectional(
                top: 0,
                bottom: 0,
                start: 0,
                child: ColoredBox(
                  color: accentColor!,
                  child: const SizedBox(width: 3),
                ),
              ),
          ],
        ),
      ),
    );

    if (semanticLabel != null) {
      card = Semantics(
        container: true,
        button: onTap != null,
        label: semanticLabel,
        child: card,
      );
    }
    return card;
  }
}

class SectionHeading extends StatelessWidget {
  const SectionHeading({
    required this.title,
    this.subtitle,
    this.trailing,
    super.key,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: QuantaraSpacing.xxs),
                Text(
                  subtitle!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: QuantaraSpacing.sm),
          trailing!,
        ],
      ],
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
      child: ExcludeSemantics(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.11),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: color.withValues(alpha: 0.26)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 14, color: color),
                  const SizedBox(width: 5),
                ],
                Flexible(
                  child: Text(
                    label,
                    softWrap: true,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
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
    final theme = Theme.of(context);
    final marketType =
        theme.extension<QuantaraMarketTypography>() ??
        const QuantaraMarketTypography(numericFeatures: []);
    return Semantics(
      label: '$label: $value',
      child: ExcludeSemantics(
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 92),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: QuantaraSpacing.xxs),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.fade,
                softWrap: false,
                textDirection: TextDirection.ltr,
                style: marketType.numeric(
                  theme.textTheme.titleMedium?.copyWith(
                    color: valueColor,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.15,
                  ),
                ),
              ),
              if (caption != null) ...[
                const SizedBox(height: 3),
                Text(
                  caption!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class MarketListRow extends StatelessWidget {
  const MarketListRow({
    required this.symbol,
    required this.name,
    required this.price,
    required this.change,
    required this.changeColor,
    required this.onTap,
    this.leadingLabel,
    this.trailing,
    super.key,
  });

  final String symbol;
  final String name;
  final String price;
  final String change;
  final Color changeColor;
  final VoidCallback onTap;
  final String? leadingLabel;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final marketType =
        theme.extension<QuantaraMarketTypography>() ??
        const QuantaraMarketTypography(numericFeatures: []);
    final largeText = MediaQuery.textScalerOf(context).scale(1) > 1.35;
    final identity = Row(
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            shape: BoxShape.circle,
            border: Border.all(
              color: theme.colorScheme.outline.withValues(alpha: 0.7),
            ),
          ),
          child: SizedBox.square(
            dimension: 40,
            child: Center(
              child: Text(
                leadingLabel ?? symbol.characters.first,
                textDirection: TextDirection.ltr,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: QuantaraSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                symbol,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textDirection: TextDirection.ltr,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                name,
                maxLines: largeText ? 2 : 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
    final quote = Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          price,
          textDirection: TextDirection.ltr,
          style: marketType.numeric(
            theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          change,
          textDirection: TextDirection.ltr,
          style: marketType.numeric(
            theme.textTheme.bodyMedium?.copyWith(
              color: changeColor,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
    return Semantics(
      button: true,
      label: '$symbol، $price، $change',
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: QuantaraSpacing.sm,
            vertical: QuantaraSpacing.sm,
          ),
          child: largeText
              ? Column(
                  children: [
                    identity,
                    const SizedBox(height: QuantaraSpacing.xs),
                    Row(
                      children: [
                        Expanded(
                          child: Align(
                            alignment: AlignmentDirectional.centerEnd,
                            child: quote,
                          ),
                        ),
                        if (trailing != null) ...[
                          const SizedBox(width: QuantaraSpacing.xs),
                          trailing!,
                        ],
                      ],
                    ),
                  ],
                )
              : Row(
                  children: [
                    Expanded(child: identity),
                    const SizedBox(width: QuantaraSpacing.sm),
                    quote,
                    if (trailing != null) ...[
                      const SizedBox(width: QuantaraSpacing.xs),
                      trailing!,
                    ],
                  ],
                ),
        ),
      ),
    );
  }
}

class RiskProgress extends StatelessWidget {
  const RiskProgress({required this.current, required this.maximum, super.key});

  final double current;
  final double maximum;

  @override
  Widget build(BuildContext context) {
    final safeMaximum = maximum <= 0 ? 1 : maximum;
    final value = (current / safeMaximum).clamp(0.0, 1.0);
    final scheme = Theme.of(context).colorScheme;

    return Semantics(
      label: 'میزان مصرف ریسک روزانه',
      value: '${(value * 100).round()}%',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: LinearProgressIndicator(
          value: value,
          minHeight: 7,
          backgroundColor: scheme.outline.withValues(alpha: 0.32),
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
      child: RepaintBoundary(
        child: SizedBox(
          height: height,
          width: double.infinity,
          child: CustomPaint(
            painter: _SparklinePainter(values: values, color: color),
          ),
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
      index == 0 ? path.moveTo(dx, dy) : path.lineTo(dx, dy);
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke,
    );

    final fillPath = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.18), color.withValues(alpha: 0)],
        ).createShader(Offset.zero & size)
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) {
    return oldDelegate.values != values || oldDelegate.color != color;
  }
}
