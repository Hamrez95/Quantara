part of 'owner_alpha_page.dart';

class _HomeDashboard extends StatelessWidget {
  const _HomeDashboard({
    required this.controller,
    required this.snapshot,
    required this.realtimeMonitor,
    required this.onOpenAnalysis,
    required this.onNavigate,
    required this.onOpenPortfolioRisk,
  });

  final OwnerAlphaController controller;
  final OwnerAlphaSnapshot snapshot;
  final ValueListenable<RealtimeMarketMonitorSnapshot>? realtimeMonitor;
  final _OpenAnalysis onOpenAnalysis;
  final ValueChanged<int> onNavigate;
  final VoidCallback onOpenPortfolioRisk;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _HomeHero(controller: controller, snapshot: snapshot),
        const SizedBox(height: 16),
        _HomeQuickActions(onNavigate: onNavigate),
        const SizedBox(height: 16),
        _HomeOverviewGrid(
          controller: controller,
          snapshot: snapshot,
          onOpenPortfolioRisk: onOpenPortfolioRisk,
          onNavigate: onNavigate,
        ),
        const SizedBox(height: 16),
        _RadarDashboard(
          controller: controller,
          snapshot: snapshot,
          realtimeMonitor: realtimeMonitor,
          onOpenAnalysis: onOpenAnalysis,
        ),
      ],
    );
  }
}

class _HomeHero extends StatelessWidget {
  const _HomeHero({required this.controller, required this.snapshot});

  final OwnerAlphaController controller;
  final OwnerAlphaSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final scheme = Theme.of(context).colorScheme;
    final healthy =
        controller.connectionState == OwnerAlphaConnectionState.fresh ||
        controller.connectionState == OwnerAlphaConnectionState.refreshing;
    final statusColor = healthy
        ? QuantaraColors.success
        : QuantaraColors.warning;
    final statusLabel = healthy
        ? strings.t(
            'بازار متصل و آماده پایش',
            'Market connected and monitoring',
          )
        : strings.t('داده بازار نیازمند بررسی', 'Market data needs attention');

    return Semantics(
      container: true,
      label: strings.t(
        'خانه Quantara. $statusLabel',
        'Quantara Home. $statusLabel',
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(QuantaraRadius.large),
          border: Border.all(
            color: QuantaraColors.violet.withValues(alpha: 0.32),
          ),
          gradient: LinearGradient(
            begin: AlignmentDirectional.topStart,
            end: AlignmentDirectional.bottomEnd,
            colors: [
              Color.alphaBlend(
                QuantaraColors.electricBlue.withValues(alpha: 0.2),
                scheme.surface,
              ),
              Color.alphaBlend(
                QuantaraColors.violet.withValues(alpha: 0.14),
                scheme.surface,
              ),
              scheme.surface,
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: QuantaraColors.violet.withValues(alpha: 0.1),
              blurRadius: 32,
              spreadRadius: -18,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: Stack(
          children: [
            PositionedDirectional(
              top: -70,
              end: -54,
              child: Container(
                width: 190,
                height: 190,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      QuantaraColors.cyan.withValues(alpha: 0.2),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 620;
                  final identity = Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const QuantaraBrandMark(size: 56),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              strings.t('خانه Quantara', 'Quantara Home'),
                              style: Theme.of(context).textTheme.headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.w900),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              strings.t(
                                'رادار فرصت‌ها، کنترل ریسک و ابزارهای معامله در یک نمای شفاف و حرفه‌ای.',
                                'Opportunity radar, risk control and trading tools in one clear professional view.',
                              ),
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                  final health = StatusPill(
                    label: statusLabel,
                    color: statusColor,
                    icon: healthy
                        ? Icons.verified_user_rounded
                        : Icons.info_outline_rounded,
                  );
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (compact) ...[
                        identity,
                        const SizedBox(height: 14),
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: health,
                        ),
                      ] else
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: identity),
                            const SizedBox(width: 16),
                            health,
                          ],
                        ),
                      const SizedBox(height: 20),
                      _HomeHeroMetrics(
                        opportunities: snapshot.opportunities.length,
                        scanned: snapshot.diagnostics.completedAnalyses,
                        requested: snapshot.diagnostics.requestedAnalyses,
                        symbols: controller.symbols.length,
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeHeroMetrics extends StatelessWidget {
  const _HomeHeroMetrics({
    required this.opportunities,
    required this.scanned,
    required this.requested,
    required this.symbols,
  });

  final int opportunities;
  final int scanned;
  final int requested;
  final int symbols;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final items = <_HomeMetricData>[
      _HomeMetricData(
        icon: Icons.radar_rounded,
        label: strings.t('فرصت فعال', 'Active setups'),
        value: '$opportunities',
        color: opportunities > 0
            ? QuantaraColors.success
            : QuantaraColors.warning,
      ),
      _HomeMetricData(
        icon: Icons.fact_check_outlined,
        label: strings.t('پوشش اسکن', 'Scan coverage'),
        value: '$scanned/$requested',
        color: QuantaraColors.cyan,
      ),
      _HomeMetricData(
        icon: Icons.token_rounded,
        label: strings.t('نمادهای پایش', 'Tracked symbols'),
        value: '$symbols',
        color: QuantaraColors.violet,
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 720 ? 3 : 1;
        const gap = 10.0;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final item in items)
              SizedBox(
                width: width,
                child: _HomeMetric(data: item),
              ),
          ],
        );
      },
    );
  }
}

class _HomeMetric extends StatelessWidget {
  const _HomeMetric({required this.data});

  final _HomeMetricData data;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: data.color.withValues(alpha: 0.075),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: data.color.withValues(alpha: 0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        child: Row(
          children: [
            Icon(data.icon, size: 20, color: data.color),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                data.label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              data.value,
              textDirection: TextDirection.ltr,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: data.color,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeQuickActions extends StatelessWidget {
  const _HomeQuickActions({required this.onNavigate});

  final ValueChanged<int> onNavigate;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final actions = <_HomeAction>[
      _HomeAction(
        icon: Icons.smart_toy_rounded,
        label: strings.t('ترید خودکار', 'Auto Trade'),
        caption: strings.t('اتصال حساب و شروع امن', 'Connect and start safely'),
        destination: 5,
        color: QuantaraColors.magenta,
      ),
      _HomeAction(
        icon: Icons.science_rounded,
        label: strings.t('آزمایشگاه بات', 'Bot Lab'),
        caption: strings.t(
          'فوروارد تست و خروجی کامل شواهد',
          'Forward test and full evidence export',
        ),
        destination: 4,
        color: QuantaraColors.warning,
      ),
      _HomeAction(
        icon: Icons.inbox_rounded,
        label: strings.setups,
        caption: strings.t('پیشنهادها و نتیجه آن‌ها', 'Setups and outcomes'),
        destination: 1,
        color: QuantaraColors.violet,
      ),
      _HomeAction(
        icon: Icons.candlestick_chart_rounded,
        label: strings.analysis,
        caption: strings.t(
          'تحلیل روی تایم‌فریم درست',
          'Analysis on the right timeframe',
        ),
        destination: 2,
        color: QuantaraColors.cyan,
      ),
      _HomeAction(
        icon: Icons.view_list_rounded,
        label: strings.watchlist,
        caption: strings.t('نمادها و وضعیت بازار', 'Symbols and market state'),
        destination: 3,
        color: QuantaraColors.electricBlue,
      ),
      _HomeAction(
        icon: Icons.menu_book_rounded,
        label: strings.t('ژورنال', 'Journal'),
        caption: strings.t('معاملات و عملکرد', 'Trades and performance'),
        destination: 6,
        color: QuantaraColors.success,
      ),
    ];
    return SectionCard(
      semanticLabel: strings.t(
        'دسترسی سریع به ابزارهای اصلی',
        'Quick access to primary tools',
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeading(
            title: strings.t('دسترسی سریع', 'Quick access'),
            subtitle: strings.t(
              'ابزارهای اصلی Quantara بر اساس جریان واقعی کار',
              'Core Quantara tools arranged around the real workflow',
            ),
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 1080
                  ? 6
                  : constraints.maxWidth >= 620
                  ? 3
                  : 2;
              const spacing = 10.0;
              final width =
                  (constraints.maxWidth - spacing * (columns - 1)) / columns;
              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: [
                  for (final action in actions)
                    SizedBox(
                      width: width,
                      child: _HomeActionCard(
                        action: action,
                        onTap: () => onNavigate(action.destination),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _HomeActionCard extends StatelessWidget {
  const _HomeActionCard({required this.action, required this.onTap});

  final _HomeAction action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: '${action.label}. ${action.caption}',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: action.color.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: action.color.withValues(alpha: 0.2)),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 122),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: action.color.withValues(alpha: 0.13),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: SizedBox.square(
                    dimension: 36,
                    child: Icon(action.icon, size: 20, color: action.color),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  action.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 2),
                Text(
                  action.caption,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
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

class _HomeOverviewGrid extends StatelessWidget {
  const _HomeOverviewGrid({
    required this.controller,
    required this.snapshot,
    required this.onOpenPortfolioRisk,
    required this.onNavigate,
  });

  final OwnerAlphaController controller;
  final OwnerAlphaSnapshot snapshot;
  final VoidCallback onOpenPortfolioRisk;
  final ValueChanged<int> onNavigate;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final twoColumns = constraints.maxWidth >= 760;
        final risk = _PortfolioRiskExplainerCard(
          controller: controller,
          onOpen: onOpenPortfolioRisk,
        );
        final radar = _HomeRadarSummary(
          snapshot: snapshot,
          onOpen: () => onNavigate(1),
        );
        if (!twoColumns) {
          return Column(children: [risk, const SizedBox(height: 16), radar]);
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: risk),
            const SizedBox(width: 16),
            Expanded(child: radar),
          ],
        );
      },
    );
  }
}

class _PortfolioRiskExplainerCard extends StatelessWidget {
  const _PortfolioRiskExplainerCard({
    required this.controller,
    required this.onOpen,
  });

  final OwnerAlphaController controller;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final scheme = Theme.of(context).colorScheme;
    final maxLoss = controller.capital * controller.riskPercent / 100;
    return SectionCard(
      accentColor: QuantaraColors.success,
      semanticLabel: strings.t(
        'کنترل ریسک معاملات و توضیح بودجه ریسک',
        'Trading risk control and risk-budget explanation',
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: QuantaraColors.success.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const SizedBox.square(
                  dimension: 48,
                  child: Icon(
                    Icons.shield_outlined,
                    color: QuantaraColors.success,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      strings.t('کنترل ریسک معاملات', 'Trading risk control'),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      strings.t(
                        'زیان احتمالی و مارجین رزروشده پیش از ورود جدید با سقف امن کنترل می‌شود؛ این صفحه خودش هیچ سفارشی ارسال نمی‌کند.',
                        'Potential loss and reserved margin are checked before a new entry; this page sends no orders.',
                      ),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FinanceMetricPanel(
                label: strings.baseCapital,
                value: QuantaraNumberFormat.marketValue(
                  controller.capital,
                  unit: 'USDT',
                ),
                icon: Icons.account_balance_wallet_outlined,
                color: QuantaraColors.cyan,
              ),
              FinanceMetricPanel(
                label: strings.t('حد زیان هر پیشنهاد', 'Loss cap per setup'),
                value: QuantaraNumberFormat.marketValue(maxLoss, unit: 'USDT'),
                icon: Icons.health_and_safety_outlined,
                color: QuantaraColors.success,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: FilledButton.tonalIcon(
              onPressed: onOpen,
              icon: const Icon(Icons.account_balance_wallet_outlined),
              label: Text(strings.t('مشاهده بودجه ریسک', 'View risk budget')),
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeRadarSummary extends StatelessWidget {
  const _HomeRadarSummary({required this.snapshot, required this.onOpen});

  final OwnerAlphaSnapshot snapshot;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final scheme = Theme.of(context).colorScheme;
    final opportunities = snapshot.opportunities.length;
    return SectionCard(
      accentColor: QuantaraColors.violet,
      semanticLabel: strings.t(
        'خلاصه رادار فرصت‌ها',
        'Opportunity radar summary',
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: QuantaraColors.violet.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const SizedBox.square(
                  dimension: 48,
                  child: Icon(
                    Icons.radar_rounded,
                    color: QuantaraColors.violet,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      strings.t(
                        'خلاصه فرصت‌های بازار',
                        'Market opportunity summary',
                      ),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      strings.lastScan(
                        DateTime.now().toUtc().difference(snapshot.generatedAt),
                      ),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FinanceMetricPanel(
                  label: strings.t('فرصت‌های فعال', 'Active opportunities'),
                  value: '$opportunities',
                  icon: Icons.bolt_rounded,
                  color: opportunities > 0
                      ? QuantaraColors.success
                      : QuantaraColors.warning,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FinanceMetricPanel(
                  label: strings.t('نماد بررسی‌شده', 'Symbols scanned'),
                  value: '${snapshot.radar.length}',
                  icon: Icons.layers_outlined,
                  color: QuantaraColors.violet,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton.icon(
              onPressed: onOpen,
              icon: const Icon(Icons.arrow_forward_rounded),
              label: Text(strings.t('مشاهده پیشنهادها', 'View setups')),
            ),
          ),
        ],
      ),
    );
  }
}

final class _HomeMetricData {
  const _HomeMetricData({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;
}

final class _HomeAction {
  const _HomeAction({
    required this.icon,
    required this.label,
    required this.caption,
    required this.destination,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String caption;
  final int destination;
  final Color color;
}
