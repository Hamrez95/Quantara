import 'package:flutter/material.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/theme/quantara_theme.dart';
import '../../../core/widgets/quantara_ui.dart';
import '../domain/cockpit_models.dart';

class CockpitPage extends StatefulWidget {
  const CockpitPage({
    required this.repository,
    required this.themeMode,
    required this.onToggleTheme,
    super.key,
  });

  final CockpitRepository repository;
  final ThemeMode themeMode;
  final VoidCallback onToggleTheme;

  @override
  State<CockpitPage> createState() => _CockpitPageState();
}

class _CockpitPageState extends State<CockpitPage> {
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

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 1024;
        final page = _PageBody(
          selectedDestination: _selectedDestination,
          snapshotFuture: _snapshotFuture,
          onRetry: _retry,
          onToggleTheme: widget.onToggleTheme,
          themeMode: widget.themeMode,
        );

        if (isDesktop) {
          return Scaffold(
            body: SafeArea(
              child: Row(
                children: [
                  _DesktopNavigation(
                    selectedIndex: _selectedDestination,
                    onSelected: (value) {
                      setState(() => _selectedDestination = value);
                    },
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(child: page),
                ],
              ),
            ),
          );
        }

        return Scaffold(
          body: SafeArea(child: page),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _selectedDestination,
            onDestinationSelected: (value) {
              setState(() => _selectedDestination = value);
            },
            destinations: [
              NavigationDestination(
                icon: const Icon(Icons.space_dashboard_outlined),
                selectedIcon: const Icon(Icons.space_dashboard_rounded),
                label: strings.cockpit,
              ),
              NavigationDestination(
                icon: const Icon(Icons.candlestick_chart_outlined),
                selectedIcon: const Icon(Icons.candlestick_chart_rounded),
                label: strings.markets,
              ),
              NavigationDestination(
                icon: const Icon(Icons.psychology_alt_outlined),
                selectedIcon: const Icon(Icons.psychology_alt_rounded),
                label: strings.research,
              ),
              NavigationDestination(
                icon: const Icon(Icons.account_balance_wallet_outlined),
                selectedIcon: const Icon(Icons.account_balance_wallet_rounded),
                label: strings.paperAccount,
              ),
            ],
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
    final strings = AppStrings.of(context);
    final scheme = Theme.of(context).colorScheme;

    return NavigationRail(
      extended: MediaQuery.sizeOf(context).width >= 1320,
      minExtendedWidth: 230,
      selectedIndex: selectedIndex,
      onDestinationSelected: onSelected,
      leading: Padding(
        padding: const EdgeInsets.fromLTRB(12, 18, 12, 24),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [QuantaraColors.cyan, QuantaraColors.violet],
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const SizedBox(
                width: 42,
                height: 42,
                child: Icon(
                  Icons.auto_graph_rounded,
                  color: QuantaraColors.ink,
                ),
              ),
            ),
            if (MediaQuery.sizeOf(context).width >= 1320) ...[
              const SizedBox(width: 12),
              Text(
                strings.appName,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.8,
                ),
              ),
            ],
          ],
        ),
      ),
      destinations: [
        NavigationRailDestination(
          icon: const Icon(Icons.space_dashboard_outlined),
          selectedIcon: const Icon(Icons.space_dashboard_rounded),
          label: Text(strings.cockpit),
        ),
        NavigationRailDestination(
          icon: const Icon(Icons.candlestick_chart_outlined),
          selectedIcon: const Icon(Icons.candlestick_chart_rounded),
          label: Text(strings.markets),
        ),
        NavigationRailDestination(
          icon: const Icon(Icons.psychology_alt_outlined),
          selectedIcon: const Icon(Icons.psychology_alt_rounded),
          label: Text(strings.research),
        ),
        NavigationRailDestination(
          icon: const Icon(Icons.account_balance_wallet_outlined),
          selectedIcon: const Icon(Icons.account_balance_wallet_rounded),
          label: Text(strings.paperAccount),
        ),
      ],
      trailing: Padding(
        padding: const EdgeInsets.only(top: 18),
        child: Tooltip(
          message: strings.lockedRealMoney,
          child: Icon(Icons.lock_outline_rounded, color: scheme.error),
        ),
      ),
    );
  }
}

class _PageBody extends StatelessWidget {
  const _PageBody({
    required this.selectedDestination,
    required this.snapshotFuture,
    required this.onRetry,
    required this.onToggleTheme,
    required this.themeMode,
  });

  final int selectedDestination;
  final Future<CockpitSnapshot> snapshotFuture;
  final VoidCallback onRetry;
  final VoidCallback onToggleTheme;
  final ThemeMode themeMode;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<CockpitSnapshot>(
      future: snapshotFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _LoadingView();
        }

        if (snapshot.hasError || !snapshot.hasData) {
          return _ErrorView(onRetry: onRetry);
        }

        return _LoadedView(
          snapshot: snapshot.requireData,
          selectedDestination: selectedDestination,
          onToggleTheme: onToggleTheme,
          themeMode: themeMode,
        );
      },
    );
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Center(
      child: Semantics(
        liveRegion: true,
        label: strings.loading,
        child: const SizedBox(
          width: 42,
          height: 42,
          child: CircularProgressIndicator(strokeWidth: 3),
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
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
                Text(
                  strings.dataError,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text(strings.retry),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LoadedView extends StatelessWidget {
  const _LoadedView({
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
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: _TopBar(
            snapshot: snapshot,
            onToggleTheme: onToggleTheme,
            themeMode: themeMode,
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
          sliver: SliverToBoxAdapter(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1480),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _DemoBanner(),
                    const SizedBox(height: 18),
                    _selectedContent(context),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _selectedContent(BuildContext context) {
    return switch (selectedDestination) {
      1 => _MarketsSection(quotes: snapshot.watchlist, expanded: true),
      2 => _AnalysisSection(analysis: snapshot.analysis, expanded: true),
      3 => _PaperAccountSection(account: snapshot.paperAccount, expanded: true),
      _ => _Dashboard(snapshot: snapshot),
    };
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.snapshot,
    required this.onToggleTheme,
    required this.themeMode,
  });

  final CockpitSnapshot snapshot;
  final VoidCallback onToggleTheme;
  final ThemeMode themeMode;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1480),
          child: Row(
            children: [
              if (MediaQuery.sizeOf(context).width < 1024) ...[
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [QuantaraColors.cyan, QuantaraColors.violet],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const SizedBox(
                    width: 38,
                    height: 38,
                    child: Icon(
                      Icons.auto_graph_rounded,
                      color: QuantaraColors.ink,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      strings.appName,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.8,
                      ),
                    ),
                    Text(
                      snapshot.marketStatus,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurface.withValues(alpha: 0.58),
                      ),
                    ),
                  ],
                ),
              ),
              StatusPill(
                label: strings.demoEnvironment,
                color: QuantaraColors.warning,
                icon: Icons.science_outlined,
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                onPressed: onToggleTheme,
                tooltip: themeMode == ThemeMode.dark
                    ? 'حالت روشن'
                    : 'حالت تیره',
                icon: Icon(
                  themeMode == ThemeMode.dark
                      ? Icons.light_mode_outlined
                      : Icons.dark_mode_outlined,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DemoBanner extends StatelessWidget {
  const _DemoBanner();

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final warning = QuantaraColors.warning;

    return Semantics(
      container: true,
      liveRegion: true,
      label: '${strings.demoEnvironment}. ${strings.demoDescription}',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: warning.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: warning.withValues(alpha: 0.34)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded, color: warning),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      strings.demoEnvironment,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: warning,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      strings.demoDescription,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.lock_rounded, color: warning, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _Dashboard extends StatelessWidget {
  const _Dashboard({required this.snapshot});

  final CockpitSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final useColumns = constraints.maxWidth >= 1080;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (useColumns)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 7,
                    child: _AnalysisSection(analysis: snapshot.analysis),
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    flex: 5,
                    child: _PaperAccountSection(account: snapshot.paperAccount),
                  ),
                ],
              )
            else ...[
              _AnalysisSection(analysis: snapshot.analysis),
              const SizedBox(height: 18),
              _PaperAccountSection(account: snapshot.paperAccount),
            ],
            const SizedBox(height: 18),
            _MarketsSection(quotes: snapshot.watchlist),
            const SizedBox(height: 18),
            const _RealMoneyLockCard(),
          ],
        );
      },
    );
  }
}

class _AnalysisSection extends StatelessWidget {
  const _AnalysisSection({required this.analysis, this.expanded = false});

  final ExplainableAnalysis analysis;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final scheme = Theme.of(context).colorScheme;

    return SectionCard(
      semanticLabel: strings.explainableAnalysis,
      padding: EdgeInsets.all(expanded ? 26 : 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                strings.explainableAnalysis,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
              StatusPill(
                label: strings.noTrade,
                color: QuantaraColors.warning,
                icon: Icons.pause_circle_outline_rounded,
              ),
              StatusPill(
                label: '${strings.confidence}: ${analysis.confidencePercent}٪',
                color: scheme.secondary,
                icon: Icons.verified_outlined,
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: MetricTile(
                  label: analysis.symbol,
                  value: strings.noTrade,
                  caption: '${strings.marketRegime}: ${strings.uncertain}',
                  valueColor: QuantaraColors.warning,
                ),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.secondary.withValues(alpha: 0.11),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const SizedBox(
                  width: 64,
                  height: 64,
                  child: Icon(Icons.balance_rounded, size: 30),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            analysis.summary,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              height: 1.65,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            strings.whyThisDecision,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          ...analysis.factors.map(
            (factor) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _FactorRow(factor: factor),
            ),
          ),
          const SizedBox(height: 6),
          DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: scheme.primary.withValues(alpha: 0.22)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(15),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.refresh_rounded, color: scheme.primary, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          strings.invalidation,
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          analysis.invalidation,
                          style: Theme.of(
                            context,
                          ).textTheme.bodyMedium?.copyWith(height: 1.55),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FactorRow extends StatelessWidget {
  const _FactorRow({required this.factor});

  final AnalysisFactor factor;

  @override
  Widget build(BuildContext context) {
    final color = switch (factor.impact) {
      EvidenceImpact.supportive => QuantaraColors.success,
      EvidenceImpact.caution => QuantaraColors.warning,
      EvidenceImpact.neutral => Theme.of(context).colorScheme.outline,
    };
    final icon = switch (factor.impact) {
      EvidenceImpact.supportive => Icons.arrow_upward_rounded,
      EvidenceImpact.caution => Icons.priority_high_rounded,
      EvidenceImpact.neutral => Icons.remove_rounded,
    };

    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.16),
                shape: BoxShape.circle,
              ),
              child: SizedBox(
                width: 32,
                height: 32,
                child: Icon(icon, color: color, size: 18),
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    factor.title,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    factor.detail,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      height: 1.45,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.68),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PaperAccountSection extends StatelessWidget {
  const _PaperAccountSection({required this.account, this.expanded = false});

  final PaperAccountSummary account;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final pnlColor = account.dailyPnl >= 0
        ? QuantaraColors.success
        : Theme.of(context).colorScheme.error;

    return SectionCard(
      semanticLabel: strings.paperAccount,
      padding: EdgeInsets.all(expanded ? 26 : 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  strings.paperAccount,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
              StatusPill(
                label: strings.demoEnvironment,
                color: QuantaraColors.cyan,
                icon: Icons.wallet_outlined,
              ),
            ],
          ),
          const SizedBox(height: 24),
          MetricTile(
            label: strings.paperBalance,
            value: '${_formatMoney(account.equity)} USDT',
            caption: 'سرمایه کاملاً آزمایشی',
          ),
          const SizedBox(height: 22),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 650 ? 3 : 2;
              final itemWidth =
                  (constraints.maxWidth - ((columns - 1) * 18)) / columns;
              return Wrap(
                spacing: 18,
                runSpacing: 20,
                children: [
                  SizedBox(
                    width: itemWidth,
                    child: MetricTile(
                      label: strings.available,
                      value: _formatMoney(account.availableBalance),
                    ),
                  ),
                  SizedBox(
                    width: itemWidth,
                    child: MetricTile(
                      label: strings.usedMargin,
                      value: _formatMoney(account.usedMargin),
                    ),
                  ),
                  SizedBox(
                    width: itemWidth,
                    child: MetricTile(
                      label: strings.dailyPnl,
                      value:
                          '${account.dailyPnl >= 0 ? '+' : ''}${_formatMoney(account.dailyPnl)}',
                      valueColor: pnlColor,
                    ),
                  ),
                  SizedBox(
                    width: itemWidth,
                    child: MetricTile(
                      label: strings.openPositions,
                      value: account.openPositions.toString(),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: Text(
                  strings.dailyRisk,
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              Text(
                '${account.currentDailyRiskPercent.toStringAsFixed(2)}٪ از ${account.maximumDailyRiskPercent.toStringAsFixed(0)}٪',
                textDirection: TextDirection.ltr,
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ],
          ),
          const SizedBox(height: 10),
          RiskProgress(
            current: account.currentDailyRiskPercent,
            maximum: account.maximumDailyRiskPercent,
          ),
        ],
      ),
    );
  }
}

class _MarketsSection extends StatelessWidget {
  const _MarketsSection({required this.quotes, this.expanded = false});

  final List<MarketQuote> quotes;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);

    return SectionCard(
      semanticLabel: strings.marketOverview,
      padding: EdgeInsets.all(expanded ? 26 : 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      strings.marketOverview,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      strings.watchlist,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.56),
                      ),
                    ),
                  ],
                ),
              ),
              const StatusPill(
                label: 'داده نمایشی',
                color: QuantaraColors.warning,
                icon: Icons.science_outlined,
              ),
            ],
          ),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) {
              final crossAxisCount = switch (constraints.maxWidth) {
                >= 1180 => 4,
                >= 720 => 2,
                _ => 1,
              };
              final ratio = crossAxisCount == 1 ? 1.75 : 1.45;

              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: quotes.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: ratio,
                ),
                itemBuilder: (context, index) {
                  return _QuoteCard(quote: quotes[index]);
                },
              );
            },
          ),
        ],
      ),
    );
  }
}

class _QuoteCard extends StatelessWidget {
  const _QuoteCard({required this.quote});

  final MarketQuote quote;

  @override
  Widget build(BuildContext context) {
    final positive = quote.changePercent >= 0;
    final color = positive ? QuantaraColors.success : QuantaraColors.danger;
    final scheme = Theme.of(context).colorScheme;

    return Semantics(
      label:
          '${quote.displayName}, ${_formatMoney(quote.price)}, ${quote.changePercent.toStringAsFixed(2)} percent',
      child: Material(
        color: scheme.onSurface.withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(17),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: null,
          child: Padding(
            padding: const EdgeInsets.all(15),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: scheme.primary.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: SizedBox(
                        width: 36,
                        height: 36,
                        child: Center(
                          child: Text(
                            quote.symbol.substring(0, 1),
                            style: TextStyle(
                              color: scheme.primary,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            quote.symbol,
                            textDirection: TextDirection.ltr,
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                          Text(
                            quote.displayName,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: scheme.onSurface.withValues(
                                    alpha: 0.5,
                                  ),
                                ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '${positive ? '+' : ''}${quote.changePercent.toStringAsFixed(2)}٪',
                      textDirection: TextDirection.ltr,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Text(
                  _formatMoney(quote.price),
                  textDirection: TextDirection.ltr,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: SparklineChart(values: quote.sparkline, color: color),
                ),
                const SizedBox(height: 6),
                Text(
                  'اسپرد ${quote.spreadBps.toStringAsFixed(1)} bps · ${quote.freshness.inSeconds} ثانیه قبل',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.52),
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

class _RealMoneyLockCard extends StatelessWidget {
  const _RealMoneyLockCard();

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final scheme = Theme.of(context).colorScheme;

    return SectionCard(
      semanticLabel: strings.lockedRealMoney,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.error.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(15),
            ),
            child: SizedBox(
              width: 48,
              height: 48,
              child: Icon(Icons.lock_rounded, color: scheme.error),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  strings.lockedRealMoney,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'تا زمانی که آزمایش‌های تاریخی، حساب کاغذی، حالت سایه و کنترل‌های ایمنی کامل نشوند، هیچ کلید یا دکمه‌ای برای ارسال سفارش واقعی نمایش داده نمی‌شود.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    height: 1.55,
                    color: scheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _formatMoney(double value) {
  final decimals = value.abs() >= 10000 ? 0 : 2;
  final parts = value.toStringAsFixed(decimals).split('.');
  final integer = parts.first;
  final isNegative = integer.startsWith('-');
  final digits = isNegative ? integer.substring(1) : integer;
  final buffer = StringBuffer();

  for (var index = 0; index < digits.length; index++) {
    if (index > 0 && (digits.length - index) % 3 == 0) {
      buffer.write(',');
    }
    buffer.write(digits[index]);
  }

  final sign = isNegative ? '-' : '';
  final fraction = parts.length > 1 ? '.${parts[1]}' : '';
  return '$sign$buffer$fraction';
}
