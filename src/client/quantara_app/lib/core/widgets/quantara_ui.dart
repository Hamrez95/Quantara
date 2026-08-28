import 'dart:math' as math;

import 'package:crypto_icons/crypto_icons.dart';
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final radius = BorderRadius.circular(QuantaraRadius.card);
    final accent = accentColor ?? scheme.primary;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    Widget card = TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: reduceMotion ? Duration.zero : QuantaraMotion.standard,
      curve: QuantaraMotion.curve,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: dark ? 0.32 : 0.11),
              blurRadius: dark ? 26 : 20,
              spreadRadius: -16,
              offset: const Offset(0, 10),
            ),
            if (accentColor != null)
              BoxShadow(
                color: accent.withValues(alpha: dark ? 0.09 : 0.055),
                blurRadius: 28,
                spreadRadius: -18,
                offset: const Offset(0, 9),
              ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: BorderSide(
              color: Color.alphaBlend(
                accent.withValues(alpha: accentColor == null ? 0.04 : 0.2),
                scheme.outline.withValues(alpha: 0.72),
              ),
            ),
          ),
          child: Ink(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: AlignmentDirectional.topStart,
                end: AlignmentDirectional.bottomEnd,
                colors: [
                  Color.alphaBlend(
                    accent.withValues(alpha: dark ? 0.035 : 0.026),
                    scheme.surface,
                  ),
                  scheme.surface,
                  Color.alphaBlend(
                    scheme.secondary.withValues(alpha: dark ? 0.018 : 0.012),
                    scheme.surface,
                  ),
                ],
                stops: const [0, 0.58, 1],
              ),
            ),
            child: InkWell(
              onTap: onTap,
              borderRadius: radius,
              child: Stack(
                children: [
                  PositionedDirectional(
                    top: -86,
                    end: -72,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              accent.withValues(
                                alpha: accentColor == null ? 0.035 : 0.09,
                              ),
                              Colors.transparent,
                            ],
                          ),
                        ),
                        child: const SizedBox.square(dimension: 170),
                      ),
                    ),
                  ),
                  PositionedDirectional(
                    top: 0,
                    start: 22,
                    end: 22,
                    child: IgnorePointer(
                      child: Container(
                        height: 1,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.transparent,
                              scheme.onSurface.withValues(alpha: 0.08),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Padding(padding: padding, child: child),
                  if (accentColor != null)
                    PositionedDirectional(
                      top: 14,
                      bottom: 14,
                      start: 0,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius:
                              const BorderRadiusDirectional.horizontal(
                                end: Radius.circular(999),
                              ),
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              accent.withValues(alpha: 0.98),
                              accent.withValues(alpha: 0.38),
                            ],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: accent.withValues(alpha: 0.24),
                              blurRadius: 9,
                            ),
                          ],
                        ),
                        child: const SizedBox(width: 3),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, 7 * (1 - value)),
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
          gradient: QuantaraColors.premiumGradient,
          borderRadius: BorderRadius.circular(size * 0.31),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.14),
            width: 0.8,
          ),
          boxShadow: [
            BoxShadow(
              color: QuantaraColors.cyan.withValues(alpha: 0.2),
              blurRadius: size * 0.56,
              spreadRadius: -size * 0.15,
            ),
            BoxShadow(
              color: QuantaraColors.violet.withValues(alpha: 0.18),
              blurRadius: size * 0.44,
              spreadRadius: -size * 0.18,
              offset: Offset(size * -0.08, size * 0.12),
            ),
          ],
        ),
        child: SizedBox.square(
          dimension: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned(
                top: size * 0.08,
                left: size * 0.12,
                right: size * 0.12,
                child: Container(
                  height: size * 0.22,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    gradient: LinearGradient(
                      colors: [
                        Colors.white.withValues(alpha: 0.22),
                        Colors.white.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
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
    'HYPE': ('H', Color(0xFF1B1B1B)),
    'ENA': ('E', Color(0xFF2E7CF6)),
    'SUI': ('S', Color(0xFF6FBCF0)),
    'TAO': ('τ', Color(0xFF111111)),
    '1000PEPE': ('P', Color(0xFF5AAF46)),
    'PUMPFUN': ('P', Color(0xFFFA53C4)),
    'UNI': ('U', Color(0xFFFF007A)),
    'AAVE': ('A', Color(0xFFB6509E)),
    'WLD': ('W', Color(0xFF202020)),
    'NEAR': ('N', Color(0xFF111111)),
    'FARTCOIN': ('F', Color(0xFF6DDB8C)),
    'BEAMX': ('B', Color(0xFF22B7ED)),
    'BCH': ('₿', Color(0xFF8DC351)),
    'WIF': ('W', Color(0xFF815CD1)),
    'ARB': ('A', Color(0xFF2D374B)),
    'OP': ('O', Color(0xFFFF0420)),
    'PENDLE': ('P', Color(0xFF7B61FF)),
    'SUSHI': ('S', Color(0xFFFA52A0)),
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
    final iconData = _iconFor(base);
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
                color.withValues(alpha: 0.98),
                Color.alphaBlend(Colors.black.withValues(alpha: 0.28), color),
              ],
            ),
            border: showBorder
                ? Border.all(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.16),
                    width: 1,
                  )
                : null,
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.22),
                blurRadius: 14,
                spreadRadius: -5,
              ),
            ],
          ),
          alignment: Alignment.center,
          child: iconData == null || fallbackLabel != null
              ? Text(
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
                )
              : Icon(iconData, color: _foregroundFor(color), size: size * 0.56),
        ),
      ),
    );
  }

  static String _fallbackText(String base) =>
      base.length <= 2 ? base : base.substring(0, 2);

  static IconData? _iconFor(String base) {
    try {
      return CryptoIcons.fromSymbol(base);
    } on Object {
      return null;
    }
  }

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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = color ?? scheme.primary;
    final marketType =
        theme.extension<QuantaraMarketTypography>() ??
        const QuantaraMarketTypography(numericFeatures: []);
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 128, minHeight: 78),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: AlignmentDirectional.topStart,
            end: AlignmentDirectional.bottomEnd,
            colors: [
              accent.withValues(alpha: 0.12),
              scheme.surfaceContainerHighest.withValues(alpha: 0.58),
            ],
          ),
          borderRadius: BorderRadius.circular(QuantaraRadius.control),
          border: Border.all(color: accent.withValues(alpha: 0.22)),
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: 0.08),
              blurRadius: 18,
              spreadRadius: -12,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Row(
            children: [
              if (icon != null) ...[
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(color: accent.withValues(alpha: 0.2)),
                  ),
                  child: SizedBox.square(
                    dimension: 36,
                    child: Icon(icon, size: 19, color: accent),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.fade,
                      softWrap: false,
                      textDirection: TextDirection.ltr,
                      style: marketType.numeric(
                        theme.textTheme.titleMedium?.copyWith(
                          color: accent,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                  ],
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
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.28,
                ),
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
            gradient: LinearGradient(
              colors: [
                color.withValues(alpha: 0.15),
                color.withValues(alpha: 0.075),
              ],
            ),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: color.withValues(alpha: 0.3)),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.07),
                blurRadius: 12,
                spreadRadius: -8,
              ),
            ],
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
                      fontWeight: FontWeight.w900,
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
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.2,
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
    final scheme = theme.colorScheme;
    final marketType =
        theme.extension<QuantaraMarketTypography>() ??
        const QuantaraMarketTypography(numericFeatures: []);
    final largeText = MediaQuery.textScalerOf(context).scale(1) > 1.35;
    final identity = Row(
      children: [
        SymbolAvatar(symbol: symbol, size: 42, fallbackLabel: leadingLabel),
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
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.18,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                name,
                maxLines: largeText ? 2 : 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
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
            theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
        ),
        const SizedBox(height: 3),
        DecoratedBox(
          decoration: BoxDecoration(
            color: changeColor.withValues(alpha: 0.11),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: changeColor.withValues(alpha: 0.2)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            child: Text(
              change,
              textDirection: TextDirection.ltr,
              style: marketType.numeric(
                theme.textTheme.bodySmall?.copyWith(
                  color: changeColor,
                  fontWeight: FontWeight.w900,
                ),
              ),
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
        borderRadius: BorderRadius.circular(QuantaraRadius.control),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(QuantaraRadius.control),
            gradient: LinearGradient(
              begin: AlignmentDirectional.topStart,
              end: AlignmentDirectional.bottomEnd,
              colors: [
                changeColor.withValues(alpha: 0.035),
                scheme.surface.withValues(alpha: 0),
              ],
            ),
          ),
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
          colors: [color.withValues(alpha: 0.2), color.withValues(alpha: 0)],
        ).createShader(Offset.zero & size)
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) {
    return oldDelegate.values != values || oldDelegate.color != color;
  }
}
