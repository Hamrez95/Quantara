from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def write(path: str, content: str) -> None:
    target = ROOT / path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(content, encoding="utf-8")


def replace_once(path: str, old: str, new: str) -> None:
    text = read(path)
    if old not in text:
        raise RuntimeError(f"Patch anchor not found in {path}: {old[:120]!r}")
    write(path, text.replace(old, new, 1))


def replace_between(path: str, start_marker: str, end_marker: str, replacement: str) -> None:
    text = read(path)
    start = text.find(start_marker)
    if start < 0:
        raise RuntimeError(f"Start marker not found in {path}: {start_marker!r}")
    end = text.find(end_marker, start)
    if end < 0:
        raise RuntimeError(f"End marker not found in {path}: {end_marker!r}")
    write(path, text[:start] + replacement + text[end:])


# ---------------------------------------------------------------------------
# Theme and reusable visual language.
# ---------------------------------------------------------------------------
theme = "src/client/quantara_app/lib/core/theme/quantara_theme.dart"
replace_once(theme, "  static const ink = Color(0xFF07090D);\n  static const deepNavy = Color(0xFF0B0E14);\n  static const navy = Color(0xFF11151D);\n  static const elevatedNavy = Color(0xFF181D27);\n  static const cyan = Color(0xFF22B8A5);\n  static const violet = Color(0xFF8175F5);\n", "  static const ink = Color(0xFF05070B);\n  static const deepNavy = Color(0xFF090D14);\n  static const navy = Color(0xFF101620);\n  static const elevatedNavy = Color(0xFF171F2C);\n  static const cyan = Color(0xFF25C7B2);\n  static const electricBlue = Color(0xFF4E8CFF);\n  static const violet = Color(0xFF8B7CFF);\n")
replace_once(theme, "  static const control = 10.0;\n  static const card = 14.0;\n  static const large = 18.0;\n", "  static const control = 13.0;\n  static const card = 18.0;\n  static const large = 24.0;\n")
replace_once(theme, "  static const fast = Duration(milliseconds: 160);\n  static const standard = Duration(milliseconds: 220);\n  static const curve = Curves.easeOutCubic;\n", "  static const fast = Duration(milliseconds: 140);\n  static const standard = Duration(milliseconds: 240);\n  static const slow = Duration(milliseconds: 360);\n  static const curve = Curves.easeOutCubic;\n")
replace_once(theme, "      visualDensity: VisualDensity.standard,\n      splashFactory: InkSparkle.splashFactory,\n", "      visualDensity: VisualDensity.standard,\n      splashFactory: InkSparkle.splashFactory,\n      appBarTheme: AppBarTheme(\n        elevation: 0,\n        scrolledUnderElevation: 0,\n        centerTitle: false,\n        backgroundColor: scheme.brightness == Brightness.dark\n            ? QuantaraColors.deepNavy\n            : QuantaraColors.lightSurface,\n        foregroundColor: scheme.onSurface,\n        surfaceTintColor: Colors.transparent,\n        toolbarHeight: 64,\n        titleSpacing: 14,\n        shape: Border(\n          bottom: BorderSide(\n            color: scheme.outline.withValues(alpha: 0.55),\n            width: 0.8,\n          ),\n        ),\n      ),\n      snackBarTheme: SnackBarThemeData(\n        behavior: SnackBarBehavior.floating,\n        elevation: 8,\n        backgroundColor: scheme.surfaceContainerHighest,\n        contentTextStyle: TextStyle(color: scheme.onSurface, height: 1.45),\n        shape: RoundedRectangleBorder(\n          borderRadius: BorderRadius.circular(QuantaraRadius.card),\n          side: BorderSide(color: scheme.outline.withValues(alpha: 0.7)),\n        ),\n      ),\n")
replace_once(theme, "      cardTheme: CardThemeData(\n        color: scheme.surface,\n        elevation: 0,\n", "      cardTheme: CardThemeData(\n        color: scheme.surface,\n        surfaceTintColor: Colors.transparent,\n        shadowColor: Colors.black.withValues(alpha: 0.22),\n        elevation: 0,\n")
replace_once(theme, "        height: 72,\n", "        height: 70,\n")
replace_once(theme, "        height: 72,\n", "        height: 70,\n")

ui = "src/client/quantara_app/lib/core/widgets/quantara_ui.dart"
replace_between(
    ui,
    "    Widget card = Material(",
    "\n\n    if (semanticLabel != null)",
    """    Widget card = TweenAnimationBuilder<double>(
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
    );""",
)
replace_once(
    ui,
    """        DecoratedBox(
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
""",
    """        SymbolAvatar(
          symbol: symbol,
          size: 40,
          fallbackLabel: leadingLabel,
        ),
""",
)
replace_once(
    ui,
    "class SectionHeading extends StatelessWidget {",
    r'''class QuantaraBrandMark extends StatelessWidget {
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
            colors: [QuantaraColors.cyan, QuantaraColors.electricBlue, QuantaraColors.violet],
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

  static const _brand = <String, (String, Color)> {
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
    'USDC': ('$', Color(0xFF2775CA)),
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
    return palette[base.codeUnits.fold<int>(0, (sum, value) => sum + value) % palette.length];
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

class SectionHeading extends StatelessWidget {''',
)

# ---------------------------------------------------------------------------
# Local-live presentation localization and structured affordability parsing.
# ---------------------------------------------------------------------------
write(
    "src/client/quantara_app/lib/core/localization/local_live_message_localizer.dart",
    r'''import 'package:flutter/foundation.dart';

@immutable
class LocalLiveAffordabilitySummary {
  const LocalLiveAffordabilitySummary({
    required this.availableMargin,
    required this.minimumMargin,
    required this.symbol,
    required this.shortfall,
  });

  final String availableMargin;
  final String minimumMargin;
  final String symbol;
  final String shortfall;
}

abstract final class LocalLiveMessageLocalizer {
  static final RegExp _affordability = RegExp(
    r'^Available margin is ([0-9.]+) USDT\. The smallest exchange/margin floor among the selected symbols is about ([0-9.]+) USDT \(([^,]+), including three TP quantities and the safety buffer\)\. Shortfall: ([0-9.]+) USDT\. The actual risk and stop distance checks may require more capital\.$',
  );

  static LocalLiveAffordabilitySummary? affordability(String message) {
    final match = _affordability.firstMatch(message.trim());
    if (match == null) return null;
    return LocalLiveAffordabilitySummary(
      availableMargin: match.group(1)!,
      minimumMargin: match.group(2)!,
      symbol: match.group(3)!,
      shortfall: match.group(4)!,
    );
  }

  static String localize(String message, {required bool persian}) {
    final value = message.trim();
    if (!persian || value.isEmpty || _containsPersian(value)) return value;
    final summary = affordability(value);
    if (summary != null) {
      return 'موجودی قابل استفاده ${summary.availableMargin} USDT است؛ حداقل سرمایه لازم برای ${summary.symbol} حدود ${summary.minimumMargin} USDT و کسری سرمایه ${summary.shortfall} USDT است. با توجه به فاصله حد ضرر و کنترل ریسک ممکن است سرمایه بیشتری لازم باشد.';
    }
    const exact = <String, String>{
      'Local live trading is stopped.': 'ترید واقعی محلی متوقف است.',
      'Local live service is starting on this device.': 'سرویس ترید محلی روی این دستگاه در حال راه‌اندازی است.',
      'Local live trading was already stopped.': 'ترید محلی از قبل متوقف بوده است.',
      'Local service stopped. Existing exchange SL/TP remains active.': 'سرویس محلی متوقف شد؛ حد ضرر و حد سود ثبت‌شده در صرافی فعال می‌مانند.',
      'Local service stopped after emergency close requests.': 'سرویس محلی پس از ارسال درخواست‌های بستن اضطراری متوقف شد.',
      'Local live service started; waiting for in-memory credentials.': 'سرویس محلی شروع شد و در انتظار دریافت امن اطلاعات اتصال است.',
      'New entries stopped; exchange-native protection remains active.': 'ورودهای جدید متوقف شده‌اند و حفاظت ثبت‌شده در صرافی فعال است.',
      'Local live service stopped.': 'سرویس ترید محلی متوقف شد.',
      'Android stopped the local live service after a timeout.': 'اندروید پس از پایان مهلت، سرویس ترید محلی را متوقف کرد.',
      'Local live configuration was missing.': 'تنظیمات ترید محلی پیدا نشد.',
      'Bitunix credentials were unavailable to the local service.': 'اطلاعات اتصال Bitunix در اختیار سرویس محلی قرار نگرفت.',
      'Local live canary is armed on this Android device.': 'نسخه Canary ترید محلی روی این دستگاه آماده و فعال است.',
      'New entries stopped; existing exchange SL/TP orders remain active.': 'ورود جدید متوقف شد و سفارش‌های حد ضرر و حد سود صرافی فعال می‌مانند.',
      'Emergency reduce-only close requests were submitted.': 'درخواست‌های بستن اضطراری Reduce-only ارسال شدند.',
      'Daily loss cap reached. New entries are blocked.': 'سقف ضرر روزانه پر شده و ورود جدید مسدود است.',
      'Local live scan and exchange reconciliation completed.': 'اسکن بازار و تطبیق وضعیت صرافی با موفقیت انجام شد.',
      'Only exchange-protected positions are being reconciled.': 'فقط پوزیشن‌های دارای حفاظت صرافی در حال پایش و تطبیق هستند.',
      'Three consecutive local execution failures. New entries blocked.': 'سه خطای پیاپی در اجرای محلی رخ داد و ورود جدید مسدود شد.',
      'Guarded local live trading is available only on Android.': 'ترید واقعی محلی فقط در نسخه اندروید در دسترس است.',
      'Connect and validate the Bitunix account before starting local live trading.': 'پیش از شروع ترید محلی، حساب Bitunix را متصل و اعتبارسنجی کن.',
      'Notification permission is required for the visible local execution service.': 'برای نمایش و کنترل سرویس ترید محلی، اجازه اعلان لازم است.',
      'No available USDT margin is available for a new isolated position.': 'برای بازکردن پوزیشن Isolated جدید، مارجین USDT قابل استفاده وجود ندارد.',
      'Quantara could not confirm an affordable API-supported symbol from the selected allow-list.': 'Quantara نتوانست میان نمادهای انتخاب‌شده، نمادی معتبر و متناسب با موجودی تأیید کند.',
    };
    final known = exact[value];
    if (known != null) return known;
    if (value.startsWith('Local cycle failed safely:')) {
      return 'چرخه ترید محلی به‌صورت ایمن متوقف شد. جزئیات در گزارش اجرا ثبت شده است.';
    }
    if (value.startsWith('Android is not running the local execution service.')) {
      return 'سرویس اجرای محلی اندروید فعال نیست؛ سفارش‌های حد ضرر و حد سود ثبت‌شده در صرافی همچنان مرجع هستند.';
    }
    if (value.startsWith('Android foreground service')) {
      return 'راه‌اندازی سرویس پس‌زمینه اندروید ناموفق بود. برنامه را باز نگه دار و اجازه اعلان را بررسی کن.';
    }
    if (value.startsWith('Local live service could not start safely')) {
      return 'سرویس ترید محلی نتوانست به‌صورت ایمن شروع شود.';
    }
    if (value.startsWith('The local stop request failed')) {
      return 'درخواست توقف سرویس محلی ناموفق بود؛ وضعیت سفارش‌های محافظتی صرافی را بررسی کن.';
    }
    return 'سرویس ترید محلی یک وضعیت فنی ثبت کرده است. برای جزئیات، گزارش اجرا را باز کن.';
  }

  static bool _containsPersian(String value) =>
      RegExp(r'[\u0600-\u06FF]').hasMatch(value);
}
''',
)

# ---------------------------------------------------------------------------
# App shell: persistent branded header, compact navigation, destination motion.
# ---------------------------------------------------------------------------
page = "src/client/quantara_app/lib/features/owner_alpha/presentation/owner_alpha_page.dart"
replace_once(
    page,
    "import '../../../core/localization/app_strings.dart';\n",
    "import '../../../core/localization/app_strings.dart';\nimport '../../../core/localization/local_live_message_localizer.dart';\n",
)
replace_once(
    page,
    """            onOpenStrategyLab: () => setState(() => _destination = 4),
          ),
        );
""",
    """            onOpenStrategyLab: () => setState(() => _destination = 4),
            showTopBar: desktop,
          ),
        );
""",
)
replace_once(
    page,
    """                  Expanded(child: body),
""",
    """                  Expanded(
                    child: _DestinationTransition(
                      destination: _destination,
                      child: body,
                    ),
                  ),
""",
)
replace_once(
    page,
    """        return Scaffold(
          body: SafeArea(bottom: false, child: body),
          bottomNavigationBar: SafeArea(
""",
    """        return Scaffold(
          appBar: _QuantaraMobileAppBar(
            controller: _controller,
            destination: _destination,
            themeMode: widget.themeMode,
            onToggleTheme: widget.onToggleTheme,
            onRefresh: _controller.refresh,
          ),
          body: SafeArea(
            bottom: false,
            child: _DestinationTransition(
              destination: _destination,
              child: body,
            ),
          ),
          bottomNavigationBar: SafeArea(
""",
)
replace_once(
    page,
    """              labelBehavior: constraints.maxWidth < 380
                  ? NavigationDestinationLabelBehavior.onlyShowSelected
                  : NavigationDestinationLabelBehavior.alwaysShow,
""",
    """              labelBehavior: constraints.maxWidth < 440
                  ? NavigationDestinationLabelBehavior.onlyShowSelected
                  : NavigationDestinationLabelBehavior.alwaysShow,
""",
)
replace_once(
    page,
    """    required this.onOpenStrategyLab,
  });
""",
    """    required this.onOpenStrategyLab,
    required this.showTopBar,
  });
""",
)
replace_once(
    page,
    """  final VoidCallback onOpenStrategyLab;

  @override
""",
    """  final VoidCallback onOpenStrategyLab;
  final bool showTopBar;

  @override
""",
)
replace_once(
    page,
    """                  _AlphaTopBar(
                    controller: controller,
                    themeMode: themeMode,
                    onToggleTheme: onToggleTheme,
                  ),
                  const SizedBox(height: 14),
""",
    """                  if (showTopBar) ...[
                    _AlphaTopBar(
                      controller: controller,
                      themeMode: themeMode,
                      onToggleTheme: onToggleTheme,
                    ),
                    const SizedBox(height: 14),
                  ],
""",
)
replace_once(
    page,
    "class _AddSymbolDialog extends StatefulWidget {",
    r'''class _DestinationTransition extends StatelessWidget {
  const _DestinationTransition({required this.destination, required this.child});

  final int destination;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return AnimatedSwitcher(
      duration: reduceMotion ? Duration.zero : QuantaraMotion.standard,
      switchInCurve: QuantaraMotion.curve,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        final offset = Tween<Offset>(
          begin: const Offset(0.025, 0),
          end: Offset.zero,
        ).animate(animation);
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(position: offset, child: child),
        );
      },
      child: KeyedSubtree(key: ValueKey('destination-$destination'), child: child),
    );
  }
}

class _QuantaraMobileAppBar extends StatelessWidget
    implements PreferredSizeWidget {
  const _QuantaraMobileAppBar({
    required this.controller,
    required this.destination,
    required this.themeMode,
    required this.onToggleTheme,
    required this.onRefresh,
  });

  final OwnerAlphaController controller;
  final int destination;
  final ThemeMode themeMode;
  final VoidCallback onToggleTheme;
  final VoidCallback onRefresh;

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final scheme = Theme.of(context).colorScheme;
    final state = controller.connectionState;
    final healthy = state == OwnerAlphaConnectionState.fresh ||
        state == OwnerAlphaConnectionState.refreshing;
    return AppBar(
      leadingWidth: 56,
      leading: const Padding(
        padding: EdgeInsetsDirectional.only(start: 14, top: 10, bottom: 10),
        child: QuantaraBrandMark(size: 40),
      ),
      title: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Quantara',
            style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: -0.55),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: QuantaraMotion.fast,
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: healthy ? QuantaraColors.success : QuantaraColors.warning,
                  boxShadow: [
                    BoxShadow(
                      color: (healthy ? QuantaraColors.success : QuantaraColors.warning)
                          .withValues(alpha: 0.35),
                      blurRadius: 7,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  _destinationLabel(strings, destination),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        IconButton(
          onPressed: controller.isLoading ? null : onRefresh,
          tooltip: strings.refresh,
          icon: AnimatedRotation(
            duration: QuantaraMotion.standard,
            turns: controller.isLoading ? 0.5 : 0,
            child: const Icon(Icons.refresh_rounded),
          ),
        ),
        IconButton(
          onPressed: onToggleTheme,
          tooltip: themeMode == ThemeMode.dark
              ? strings.lightAppearance
              : strings.darkAppearance,
          icon: Icon(
            themeMode == ThemeMode.dark
                ? Icons.light_mode_outlined
                : Icons.dark_mode_outlined,
          ),
        ),
        const SizedBox(width: 6),
      ],
    );
  }
}

class _AddSymbolDialog extends StatefulWidget {''',
)
replace_between(
    page,
    "  @override\n  Widget build(BuildContext context) {\n    return DecoratedBox(\n      decoration: BoxDecoration(\n        gradient: const LinearGradient(\n          colors: [QuantaraColors.cyan, QuantaraColors.violet],",
    "\n  }\n}\n\nColor _ideaColor",
    """  @override
  Widget build(BuildContext context) {
    return QuantaraBrandMark(size: size);
  }
}
""",
)

# ---------------------------------------------------------------------------
# Symbol identity across signals and analysis.
# ---------------------------------------------------------------------------
signals = "src/client/quantara_app/lib/features/owner_alpha/presentation/owner_alpha_signals.dart"
replace_once(
    signals,
    """      child: SectionCard(
        child: Column(
""",
    """      child: SectionCard(
        accentColor: color,
        child: Column(
""",
)
replace_once(
    signals,
    """                DecoratedBox(
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: SizedBox.square(
                    dimension: 48,
                    child: Icon(
                      entry.direction == TradeDirection.long
                          ? Icons.north_east_rounded
                          : Icons.south_east_rounded,
                      color: color,
                    ),
                  ),
                ),
""",
    """                SymbolAvatar(symbol: entry.symbol, size: 48),
""",
)

analysis = "src/client/quantara_app/lib/features/owner_alpha/presentation/owner_alpha_analysis.dart"
replace_once(
    analysis,
    """                        avatar: Icon(
                          symbol == controller.selectedSymbol
                              ? Icons.bolt_rounded
                              : Icons.show_chart_rounded,
                          size: 18,
                        ),
""",
    """                        avatar: SymbolAvatar(
                          symbol: symbol,
                          size: 22,
                          showBorder: false,
                        ),
""",
)
replace_once(
    analysis,
    """                    Text(
                      '${analysis.symbol} · ${analysis.timeframe}',
                      textDirection: TextDirection.ltr,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      strings.structureSummary(
                        timeframe: analysis.timeframe,
                        direction: strings.direction(analysis.direction.name),
                        strength: (analysis.directionStrength * 100).round(),
                        zones: analysis.zones.length,
                      ),
                    ),
                    const SizedBox(height: 8),
                    StatusPill(
                      label: _directionLabel(context, analysis.direction),
                      color: _chartDirectionColor(analysis.direction),
                    ),
""",
    """                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        SymbolAvatar(symbol: analysis.symbol, size: 48),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${analysis.symbol} · ${analysis.timeframe}',
                                textDirection: TextDirection.ltr,
                                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              Text(
                                strings.structureSummary(
                                  timeframe: analysis.timeframe,
                                  direction: strings.direction(analysis.direction.name),
                                  strength: (analysis.directionStrength * 100).round(),
                                  zones: analysis.zones.length,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        StatusPill(
                          label: _directionLabel(context, analysis.direction),
                          color: _chartDirectionColor(analysis.direction),
                        ),
                      ],
                    ),
                    if (controller.selectedChartSignal != null) ...[
                      const SizedBox(height: 10),
                      StatusPill(
                        label: strings.isPersian
                            ? 'نمایش ستاپ ذخیره‌شده روی چارت'
                            : 'Frozen setup overlay active',
                        color: QuantaraColors.violet,
                        icon: Icons.layers_rounded,
                      ),
                    ],
""",
)

# ---------------------------------------------------------------------------
# Local live UI: no raw English in Persian and structured capital summary.
# ---------------------------------------------------------------------------
auto = "src/client/quantara_app/lib/features/owner_alpha/presentation/owner_alpha_auto_trade.dart"
replace_once(
    auto,
    """    final color = breaker
        ? QuantaraColors.danger
        : running
        ? QuantaraColors.success
        : QuantaraColors.cyan;
    return SectionCard(
""",
    """    final color = breaker
        ? QuantaraColors.danger
        : running
        ? QuantaraColors.success
        : QuantaraColors.cyan;
    final localizedStatus = LocalLiveMessageLocalizer.localize(
      status.message,
      persian: _fa,
    );
    return SectionCard(
      accentColor: color,
""",
)
replace_once(
    auto,
    """          if (widget.controller.error != null) ...[
            const SizedBox(height: 10),
            _BoundaryNotice(
              text: widget.controller.error!,
              color: QuantaraColors.danger,
            ),
          ],
          const SizedBox(height: 12),
          Text(status.message),
""",
    """          if (widget.controller.error != null) ...[
            const SizedBox(height: 10),
            _LocalLiveStatusNotice(
              message: widget.controller.error!,
              persian: _fa,
              error: true,
            ),
          ],
          const SizedBox(height: 12),
          AnimatedSwitcher(
            duration: QuantaraMotion.fast,
            child: Text(
              localizedStatus,
              key: ValueKey(localizedStatus),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
""",
)
replace_once(
    auto,
    """                        FilterChip(
                          label: Text(symbol, textDirection: TextDirection.ltr),
""",
    """                        FilterChip(
                          avatar: SymbolAvatar(
                            symbol: symbol,
                            size: 22,
                            showBorder: false,
                          ),
                          label: Text(symbol, textDirection: TextDirection.ltr),
""",
)
replace_once(
    auto,
    """            widget.controller.error ??
                _t('شروع امن انجام نشد.', 'Safe start was rejected.'),
""",
    """            LocalLiveMessageLocalizer.localize(
              widget.controller.error ??
                  _t('شروع امن انجام نشد.', 'Safe start was rejected.'),
              persian: _fa,
            ),
""",
)
replace_once(
    auto,
    "class _LockedServerModeCard extends StatelessWidget {",
    r'''class _LocalLiveStatusNotice extends StatelessWidget {
  const _LocalLiveStatusNotice({
    required this.message,
    required this.persian,
    this.error = false,
  });

  final String message;
  final bool persian;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final summary = LocalLiveMessageLocalizer.affordability(message);
    final localized = LocalLiveMessageLocalizer.localize(
      message,
      persian: persian,
    );
    final color = error ? QuantaraColors.danger : QuantaraColors.warning;
    if (summary == null) {
      return _BoundaryNotice(text: localized, color: color);
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(QuantaraRadius.card),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.account_balance_wallet_outlined, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    persian ? 'بررسی حداقل سرمایه لازم' : 'Minimum capital check',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                SymbolAvatar(symbol: summary.symbol, size: 34),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FinanceMetricPanel(
                  label: persian ? 'موجودی قابل استفاده' : 'Available margin',
                  value: '${summary.availableMargin} USDT',
                  icon: Icons.savings_outlined,
                  color: QuantaraColors.cyan,
                ),
                FinanceMetricPanel(
                  label: persian ? 'حداقل سرمایه' : 'Minimum floor',
                  value: '${summary.minimumMargin} USDT',
                  icon: Icons.vertical_align_top_rounded,
                  color: QuantaraColors.warning,
                ),
                FinanceMetricPanel(
                  label: persian ? 'کسری سرمایه' : 'Shortfall',
                  value: '${summary.shortfall} USDT',
                  icon: Icons.trending_down_rounded,
                  color: QuantaraColors.danger,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              persian
                  ? 'محدودکننده فعلی ${summary.symbol} است. با توجه به فاصله حد ضرر، حجم سفارش و کنترل ریسک، ممکن است برای ورود واقعی سرمایه بیشتری لازم باشد.'
                  : '${summary.symbol} is currently the limiting symbol. Stop distance, order sizing and risk checks may require more capital.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.55),
            ),
          ],
        ),
      ),
    );
  }
}

class _LockedServerModeCard extends StatelessWidget {''',
)

# ---------------------------------------------------------------------------
# First-frame frozen overlay: treat the last candle as an interval, not a point.
# ---------------------------------------------------------------------------
chart = "src/client/quantara_app/lib/features/market_analysis/presentation/tradingview_lightweight_chart.dart"
replace_once(
    chart,
    """    return !candles.first.openTime.isAfter(signal.createdAt) &&
        !candles.last.openTime.isBefore(signal.createdAt);
  }
}
""",
    """    final coverageStart = candles.first.openTime;
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
    '15m' => const Duration(minutes: 15),
    '1h' => const Duration(hours: 1),
    '4h' => const Duration(hours: 4),
    '1D' || '1d' => const Duration(days: 1),
    _ => const Duration(minutes: 1),
  };
}
""",
)

# ---------------------------------------------------------------------------
# Tests for the reported refresh regression, localization and symbol identity.
# ---------------------------------------------------------------------------
overlay_test = "src/client/quantara_app/test/chart_signal_overlay_policy_test.dart"
replace_once(
    overlay_test,
    """  test('rejects a frozen overlay for a different timeframe', () {
""",
    """  test('renders immediately when signal was created inside the last candle', () {
    final analysis = _analysis(
      start: _origin.subtract(const Duration(minutes: 20)),
    );

    expect(
      ChartSignalOverlayPolicy.canRender(
        analysis: analysis,
        signal: _signal(),
      ),
      isTrue,
    );
  });

  test('rejects a frozen overlay for a different timeframe', () {
""",
)
write(
    "src/client/quantara_app/test/local_live_message_localizer_test.dart",
    r'''import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/core/localization/local_live_message_localizer.dart';

void main() {
  test('parses and localizes the dynamic affordability failure', () {
    const raw = 'Available margin is 0.2522 USDT. The smallest exchange/margin '
        'floor among the selected symbols is about 1.9085 USDT '
        '(ETHUSDT, including three TP quantities and the safety buffer). '
        'Shortfall: 1.6563 USDT. The actual risk and stop distance checks may '
        'require more capital.';

    final summary = LocalLiveMessageLocalizer.affordability(raw);
    expect(summary, isNotNull);
    expect(summary!.symbol, 'ETHUSDT');
    expect(summary.availableMargin, '0.2522');
    expect(summary.minimumMargin, '1.9085');
    expect(summary.shortfall, '1.6563');
    final localized = LocalLiveMessageLocalizer.localize(
      raw,
      persian: true,
    );
    expect(localized, contains('موجودی قابل استفاده'));
    expect(localized, contains('ETHUSDT'));
    expect(localized, isNot(contains('Available margin is')));
  });

  test('keeps English when the app language is English', () {
    const raw = 'Local live trading is stopped.';
    expect(
      LocalLiveMessageLocalizer.localize(raw, persian: false),
      raw,
    );
  });
}
''',
)
write(
    "src/client/quantara_app/test/quantara_symbol_avatar_test.dart",
    r'''import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/core/widgets/quantara_ui.dart';

void main() {
  testWidgets('shows a local Bitcoin identity without network assets', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SymbolAvatar(symbol: 'BTCUSDT')),
      ),
    );

    expect(find.text('₿'), findsOneWidget);
    expect(find.byType(SymbolAvatar), findsOneWidget);
  });

  testWidgets('unknown symbols receive a deterministic monogram', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SymbolAvatar(symbol: 'ABCUSDT')),
      ),
    );

    expect(find.text('AB'), findsOneWidget);
  });
}
''',
)

# Remove one-shot patch machinery in the generated implementation commit.
(ROOT / ".github/workflows/apply-ui-finalization.yml").unlink(missing_ok=True)
Path(__file__).unlink(missing_ok=True)
