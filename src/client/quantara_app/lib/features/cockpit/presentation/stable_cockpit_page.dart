import 'package:flutter/material.dart';

import '../../../core/formatting/number_formatters.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/theme/quantara_theme.dart';
import '../../../core/widgets/quantara_ui.dart';
import '../domain/cockpit_models.dart';
import '../../market_analysis/data/demo_market_chart_factory.dart';
import '../../market_analysis/domain/market_chart_models.dart';
import '../../market_analysis/presentation/quantara_candlestick_chart.dart';

part 'stable_cockpit_dashboard.dart';
part 'stable_cockpit_markets.dart';
part 'stable_cockpit_details.dart';

class StableCockpitPage extends StatefulWidget {
  const StableCockpitPage({
    required this.repository,
    required this.themeMode,
    required this.onToggleTheme,
    super.key,
  });

  final CockpitRepository repository;
  final ThemeMode themeMode;
  final VoidCallback onToggleTheme;

  @override
  State<StableCockpitPage> createState() => _StableCockpitPageState();
}

class _StableCockpitPageState extends State<StableCockpitPage> {
  late Future<CockpitSnapshot> _snapshotFuture;
  int _selectedDestination = 0;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _snapshotFuture = widget.repository.load();
  }

  void _retry() {
    setState(_reload);
  }

  void _selectDestination(int value) {
    if (_selectedDestination == value) {
      return;
    }
    setState(() => _selectedDestination = value);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final desktop = constraints.maxWidth >= 1024;
        final content = _SnapshotBody(
          future: _snapshotFuture,
          selectedDestination: _selectedDestination,
          onRetry: _retry,
          onToggleTheme: widget.onToggleTheme,
          themeMode: widget.themeMode,
        );

        if (desktop) {
          return Scaffold(
            body: SafeArea(
              child: Row(
                children: [
                  _DesktopNavigation(
                    selectedIndex: _selectedDestination,
                    onSelected: _selectDestination,
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(child: content),
                ],
              ),
            ),
          );
        }

        return Scaffold(
          body: SafeArea(bottom: false, child: content),
          bottomNavigationBar: SafeArea(
            top: false,
            child: NavigationBar(
              selectedIndex: _selectedDestination,
              onDestinationSelected: _selectDestination,
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home_rounded),
                  label: 'خانه',
                ),
                NavigationDestination(
                  icon: Icon(Icons.candlestick_chart_outlined),
                  selectedIcon: Icon(Icons.candlestick_chart_rounded),
                  label: 'بازار',
                ),
                NavigationDestination(
                  icon: Icon(Icons.psychology_alt_outlined),
                  selectedIcon: Icon(Icons.psychology_alt_rounded),
                  label: 'تحلیل',
                ),
                NavigationDestination(
                  icon: Icon(Icons.account_balance_wallet_outlined),
                  selectedIcon: Icon(Icons.account_balance_wallet_rounded),
                  label: 'حساب',
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _DesktopNavigation extends StatelessWidget {
  const _DesktopNavigation({
    required this.selectedIndex,
    required this.onSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final extended = MediaQuery.sizeOf(context).width >= 1320;
    return NavigationRail(
      extended: extended,
      minExtendedWidth: 220,
      selectedIndex: selectedIndex,
      onDestinationSelected: onSelected,
      leading: Padding(
        padding: const EdgeInsets.fromLTRB(12, 18, 12, 20),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _QuantaraMark(size: 42),
            if (extended) ...[
              const SizedBox(width: 12),
              Text(
                'Quantara',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.8,
                ),
              ),
            ],
          ],
        ),
      ),
      destinations: const [
        NavigationRailDestination(
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home_rounded),
          label: Text('خانه'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.candlestick_chart_outlined),
          selectedIcon: Icon(Icons.candlestick_chart_rounded),
          label: Text('بازار'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.psychology_alt_outlined),
          selectedIcon: Icon(Icons.psychology_alt_rounded),
          label: Text('تحلیل'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.account_balance_wallet_outlined),
          selectedIcon: Icon(Icons.account_balance_wallet_rounded),
          label: Text('حساب'),
        ),
      ],
    );
  }
}

class _SnapshotBody extends StatelessWidget {
  const _SnapshotBody({
    required this.future,
    required this.selectedDestination,
    required this.onRetry,
    required this.onToggleTheme,
    required this.themeMode,
  });

  final Future<CockpitSnapshot> future;
  final int selectedDestination;
  final VoidCallback onRetry;
  final VoidCallback onToggleTheme;
  final ThemeMode themeMode;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<CockpitSnapshot>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(
            child: SizedBox.square(
              dimension: 42,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
          );
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return _ErrorView(onRetry: onRetry);
        }
        return _LoadedContent(
          snapshot: snapshot.requireData,
          selectedDestination: selectedDestination,
          onToggleTheme: onToggleTheme,
          themeMode: themeMode,
        );
      },
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: SectionCard(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.cloud_off_outlined,
                  size: 44,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(height: 16),
                const Text(
                  'داده در دسترس نیست. دوباره تلاش کنید.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('تلاش دوباره'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LoadedContent extends StatelessWidget {
  const _LoadedContent({
    required this.snapshot,
    required this.selectedDestination,
    required this.onToggleTheme,
    required this.themeMode,
  });

  final CockpitSnapshot snapshot;
  final int selectedDestination;
  final VoidCallback onToggleTheme;
  final ThemeMode themeMode;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 1024;
    return ListView(
      key: PageStorageKey<String>('quantara-page-$selectedDestination'),
      padding: EdgeInsets.fromLTRB(wide ? 28 : 16, 14, wide ? 28 : 16, 32),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1280),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _TopBar(
                  marketStatus: snapshot.marketStatus,
                  onToggleTheme: onToggleTheme,
                  themeMode: themeMode,
                ),
                const SizedBox(height: 14),
                const _DemoStrip(),
                const SizedBox(height: 16),
                switch (selectedDestination) {
                  1 => _MarketsView(quotes: snapshot.watchlist),
                  2 => _AnalysisDetails(analysis: snapshot.analysis),
                  3 => _PaperAccountDetails(account: snapshot.paperAccount),
                  _ => _Dashboard(snapshot: snapshot),
                },
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.marketStatus,
    required this.onToggleTheme,
    required this.themeMode,
  });

  final String marketStatus;
  final VoidCallback onToggleTheme;
  final ThemeMode themeMode;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        const _QuantaraMark(size: 46),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Quantara',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.8,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                marketStatus,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurface.withValues(alpha: 0.62),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        IconButton.filledTonal(
          onPressed: onToggleTheme,
          tooltip: themeMode == ThemeMode.dark ? 'حالت روشن' : 'حالت تیره',
          icon: Icon(
            themeMode == ThemeMode.dark
                ? Icons.light_mode_outlined
                : Icons.dark_mode_outlined,
          ),
        ),
      ],
    );
  }
}

class _QuantaraMark extends StatelessWidget {
  const _QuantaraMark({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            QuantaraColors.cyan,
            Color(0xFF3E86F5),
            QuantaraColors.violet,
          ],
        ),
        borderRadius: BorderRadius.circular(size * 0.28),
      ),
      child: SizedBox.square(
        dimension: size,
        child: Icon(
          Icons.trending_up_rounded,
          size: size * 0.62,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _DemoStrip extends StatelessWidget {
  const _DemoStrip();

  @override
  Widget build(BuildContext context) {
    const warning = QuantaraColors.warning;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: warning.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: warning.withValues(alpha: 0.3)),
      ),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(Icons.science_outlined, color: warning, size: 22),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'نسخه آزمایشی؛ بدون اتصال به بازار زنده و بدون سفارش واقعی',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            SizedBox(width: 8),
            Icon(Icons.lock_outline_rounded, color: warning, size: 20),
          ],
        ),
      ),
    );
  }
}

class _QuoteRow extends StatelessWidget {
  const _QuoteRow({required this.quote, this.onTap, this.selected = false});

  final MarketQuote quote;
  final VoidCallback? onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final positive = quote.changePercent >= 0;
    final changeColor = positive
        ? QuantaraColors.success
        : QuantaraColors.danger;
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: selected
          ? scheme.primary.withValues(alpha: 0.08)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
          child: Row(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: SizedBox.square(
                  dimension: 40,
                  child: Center(
                    child: Text(
                      quote.symbol.substring(0, 1),
                      textDirection: TextDirection.ltr,
                      style: TextStyle(
                        color: scheme.primary,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      quote.symbol,
                      textDirection: TextDirection.ltr,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      QuantaraNumberFormat.relativePersian(quote.freshness),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurface.withValues(alpha: 0.55),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 72,
                height: 38,
                child: SparklineChart(
                  values: quote.sparkline,
                  color: changeColor,
                  height: 38,
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 94,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text(
                        QuantaraNumberFormat.marketValue(quote.price),
                        textDirection: TextDirection.ltr,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      QuantaraNumberFormat.marketPercent(quote.changePercent),
                      textDirection: TextDirection.ltr,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: changeColor,
                        fontWeight: FontWeight.w800,
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

class _RealMoneyLockCard extends StatelessWidget {
  const _RealMoneyLockCard({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SectionCard(
      padding: const EdgeInsets.all(18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.error.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: SizedBox.square(
              dimension: 44,
              child: Icon(Icons.lock_rounded, color: scheme.error),
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'معامله با پول واقعی غیرفعال است',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  compact
                      ? 'فعلاً فقط مشاهده و آزمایش؛ هیچ سفارش واقعی ارسال نمی‌شود.'
                      : 'فعال‌سازی پول واقعی فقط پس از حساب کاغذی، حالت سایه، محدودیت زیان و کلید توقف امکان‌پذیر خواهد بود.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(height: 1.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _decisionLabel(AnalysisDecision decision) {
  return switch (decision) {
    AnalysisDecision.bullish => 'صعودی',
    AnalysisDecision.bearish => 'نزولی',
    AnalysisDecision.noTrade => 'عدم معامله',
  };
}

Color _decisionColor(BuildContext context, AnalysisDecision decision) {
  return switch (decision) {
    AnalysisDecision.bullish => QuantaraColors.success,
    AnalysisDecision.bearish => QuantaraColors.danger,
    AnalysisDecision.noTrade => QuantaraColors.warning,
  };
}

IconData _decisionIcon(AnalysisDecision decision) {
  return switch (decision) {
    AnalysisDecision.bullish => Icons.trending_up_rounded,
    AnalysisDecision.bearish => Icons.trending_down_rounded,
    AnalysisDecision.noTrade => Icons.pause_circle_outline_rounded,
  };
}

Color _impactColor(BuildContext context, EvidenceImpact impact) {
  return switch (impact) {
    EvidenceImpact.supportive => QuantaraColors.success,
    EvidenceImpact.caution => QuantaraColors.warning,
    EvidenceImpact.neutral => Theme.of(context).colorScheme.outline,
  };
}

IconData _impactIcon(EvidenceImpact impact) {
  return switch (impact) {
    EvidenceImpact.supportive => Icons.arrow_upward_rounded,
    EvidenceImpact.caution => Icons.priority_high_rounded,
    EvidenceImpact.neutral => Icons.remove_rounded,
  };
}
