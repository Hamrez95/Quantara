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
    Widget card = TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: QuantaraMotion.standard,
      curve: QuantaraMotion.curve,
      child: Material(
        color: Colors.transparent,
        elevation: dark ? 0 : 1,
        shadowColor: Colors.black.withValues(alpha: 0.16),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: scheme.outline.withValues(alpha: 0.7)),
        ),
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topDirectional,
              end: Alignment.bottomDirectional,
              colors: [
                scheme.surface,
                Color.alphaBlend(
                  scheme.primary.withValues(alpha: dark ? 0.025 : 0.018),
                  scheme.surface,
                ),
              ],
            ),
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
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            accentColor!.withValues(alpha: 0.96),
                            accentColor!.withValues(alpha: 0.45),
                          ],
                        ),
                      ),
                      child: const SizedBox(width: 3),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, 8 * (1 - value)),
          child: child,
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

class QuantaraBrandMark extends StatelessWidget {
  const QuantaraBrandMark({this.size = 42, this.heroTag, super.key});

  final double size;
  final String? heroTag;

  @override
  Widget build(BuildContext context) {
    final mark = Semantics(
      image: true,
      label: 'Quantara',
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [
              QuantaraColors.cyan,
              QuantaraColors.electricBlue,
              QuantaraColors.violet,
            ],
          ),
          borderRadius: BorderRadius.circular(size * 0.31),
          boxShadow: [
            BoxShadow(
              color: QuantaraColors.cyan.withValues(alpha: 0.18),
              blurRadius: size * 0.45,
              spreadRadius: -size * 0.14,
            ),
          ],
        ),
        child: SizedBox.square(
          dimension: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Text(
                'Q',
                style: TextStyle(
                  color: QuantaraColors.ink,
                  fontSize: size * 0.48,
                  height: 1,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1,
                ),
              ),
              Positioned(
                right: size * 0.18,
                bottom: size * 0.2,
                child: Transform.rotate(
                  angle: -0.35,
                  child: Container(
                    width: size * 0.22,
                    height: 2,
                    decoration: BoxDecoration(
                      color: QuantaraColors.ink,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    final tag = heroTag;
    return tag == null ? mark : Hero(tag: tag, child: mark);
  }
}

class SymbolAvatar extends StatelessWidget {
  const SymbolAvatar({
    required this.symbol,
    this.size = 40,
    this.fallbackLabel,
    this.showBorder = true,
    super.key,
  });

  final String symbol;
  final double size;
  final String? fallbackLabel;
  final bool showBorder;

  static const _brand = <String, (String, Color)>{
    'BTC': ('₿', Color(0xFFF7931A)),
    'ETH': ('Ξ', Color(0xFF627EEA)),
    'SOL': ('S', Color(0xFF14F195)),
    'XRP': ('X', Color(0xFFB9C4CF)),
    'AVAX': ('A', Color(0xFFE84142)),
    'ADA': ('A', Color(0xFF2A6EF0)),
    'DOGE': ('Ð', Color(0xFFC2A633)),
    'BNB': ('B', Color(0xFFF3BA2F)),
    'TRX': ('T', Color(0xFFEF0027)),
    'LINK': ('L', Color(0xFF2A5ADA)),
    'DOT': ('●', Color(0xFFE6007A)),
    'MATIC': ('M', Color(0xFF8247E5)),
    'TON': ('T', Color(0xFF0098EA)),
    'LTC': ('Ł', Color(0xFFBEBEBE)),
    'SHIB': ('S', Color(0xFFFF6A3D)),
    'PEPE': ('P', Color(0xFF5AAF46)),
    'USDT': ('₮', Color(0xFF26A17B)),
    'USDC': (r'$', Color(0xFF2775CA)),
    'XAU': ('Au', Color(0xFFD6A936)),
  };

  static String baseSymbol(String raw) {
    var value = raw.toUpperCase().trim();
    if (value.contains('/')) value = value.split('/').first;
    if (value.contains(':')) value = value.split(':').first;
    for (final suffix in const ['USDT', 'USDC', 'BUSD', 'USD', 'PERP']) {
      if (value.endsWith(suffix) && value.length > suffix.length) {
        value = value.substring(0, value.length - suffix.length);
        break;
      }
    }
    return value.isEmpty ? '?' : value;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = baseSymbol(symbol);
    final brand = _brand[base];
    final color = brand?.$2 ?? _fallbackColor(base);
    final label = fallbackLabel ?? brand?.$1 ?? _fallbackText(base);
    return Semantics(
      image: true,
      label: '$base symbol',
      child: ExcludeSemantics(
        child: AnimatedContainer(
          duration: QuantaraMotion.fast,
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                color.withValues(alpha: 0.96),
                Color.alphaBlend(Colors.black.withValues(alpha: 0.22), color),
              ],
            ),
            border: showBorder
                ? Border.all(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.13),
                    width: 1,
                  )
                : null,
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.18),
                blurRadius: 12,
                spreadRadius: -5,
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            maxLines: 1,
            textDirection: TextDirection.ltr,
            style: TextStyle(
              color: _foregroundFor(color),
              fontSize: size * (label.length > 1 ? 0.29 : 0.42),
              height: 1,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.4,
            ),
          ),
        ),
      ),
    );
  }

  static String _fallbackText(String base) =>
      base.length <= 2 ? base : base.substring(0, 2);

  static Color _fallbackColor(String base) {
    const palette = [
      QuantaraColors.cyan,
      QuantaraColors.electricBlue,
      QuantaraColors.violet,
      Color(0xFFEF7D52),
      Color(0xFF46A76B),
      Color(0xFFD45FA6),
    ];
    return palette[base.codeUnits.fold<int>(0, (sum, value) => sum + value) %
        palette.length];
  }

  static Color _foregroundFor(Color color) =>
      color.computeLuminance() > 0.58 ? QuantaraColors.ink : Colors.white;
}

class FinanceMetricPanel extends StatelessWidget {
  const FinanceMetricPanel({
    required this.label,
    required this.value,
    this.icon,
    this.color,
    super.key,
  });

  final String label;
  final String value;
  final IconData? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = color ?? scheme.primary;
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 128),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.075),
          borderRadius: BorderRadius.circular(QuantaraRadius.control),
          border: Border.all(color: accent.withValues(alpha: 0.2)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 15, color: accent),
                    const SizedBox(width: 5),
                  ],
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                value,
                textDirection: TextDirection.ltr,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: accent,
                  fontWeight: FontWeight.w900,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
        SymbolAvatar(symbol: symbol, size: 40, fallbackLabel: leadingLabel),
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
