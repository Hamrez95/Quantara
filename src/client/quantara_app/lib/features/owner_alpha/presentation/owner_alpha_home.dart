part of 'owner_alpha_page.dart';

class _HomeDashboard extends StatelessWidget {
  const _HomeDashboard({
    required this.controller,
    required this.snapshot,
    required this.onOpenAnalysis,
    required this.onNavigate,
    required this.onOpenPortfolioRisk,
  });

  final OwnerAlphaController controller;
  final OwnerAlphaSnapshot snapshot;
  final _OpenAnalysis onOpenAnalysis;
  final ValueChanged<int> onNavigate;
  final VoidCallback onOpenPortfolioRisk;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionCard(
          semanticLabel: strings.t(
            'خانه کوانتارا و میان‌برهای اصلی',
            'Quantara home and primary shortcuts',
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(Icons.home_rounded),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          strings.t('خانه Quantara', 'Quantara Home'),
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          strings.t(
                            'نمای کلی بازار، پیشنهادها و وضعیت ترید خودکار؛ ابزارهای تخصصی داخل همین صفحه دسته‌بندی شده‌اند.',
                            'Market, setup and Auto Trade overview, with specialist tools grouped inside this page.',
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _HomeQuickActions(onNavigate: onNavigate),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _PortfolioRiskExplainerCard(onOpen: onOpenPortfolioRisk),
        const SizedBox(height: 16),
        _RadarDashboard(
          controller: controller,
          snapshot: snapshot,
          onOpenAnalysis: (symbol) => onOpenAnalysis(symbol),
        ),
      ],
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
      ),
      _HomeAction(
        icon: Icons.inbox_rounded,
        label: strings.setups,
        caption: strings.t('پیشنهادها و نتیجه آن‌ها', 'Setups and outcomes'),
        destination: 1,
      ),
      _HomeAction(
        icon: Icons.candlestick_chart_rounded,
        label: strings.analysis,
        caption: strings.t(
          'تحلیل روی تایم‌فریم درست',
          'Analysis on the right timeframe',
        ),
        destination: 2,
      ),
      _HomeAction(
        icon: Icons.view_list_rounded,
        label: strings.watchlist,
        caption: strings.t('نمادها و وضعیت بازار', 'Symbols and market state'),
        destination: 3,
      ),
      _HomeAction(
        icon: Icons.menu_book_rounded,
        label: strings.t('ژورنال', 'Journal'),
        caption: strings.t('معاملات و عملکرد', 'Trades and performance'),
        destination: 6,
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 920
            ? 5
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
        borderRadius: BorderRadius.circular(14),
        child: Container(
          constraints: const BoxConstraints(minHeight: 118),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(action.icon, color: scheme.primary),
              const SizedBox(height: 14),
              Text(
                action.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 3),
              Text(
                action.caption,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PortfolioRiskExplainerCard extends StatelessWidget {
  const _PortfolioRiskExplainerCard({required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final scheme = Theme.of(context).colorScheme;
    return SectionCard(
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
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: QuantaraColors.success.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.shield_outlined,
                  color: QuantaraColors.success,
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
                        'قبل از هر ورود جدید بررسی می‌کند مجموع زیان احتمالی معاملات باز و در انتظار، و مارجین رزروشده، از سقف امن بیشتر نشود. این صفحه خودش هیچ سفارشی ارسال نمی‌کند.',
                        'Before a new entry, it checks that aggregate potential loss across open and pending trades, plus reserved margin, stays inside the safety budget. This page sends no orders itself.',
                      ),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
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

final class _HomeAction {
  const _HomeAction({
    required this.icon,
    required this.label,
    required this.caption,
    required this.destination,
  });

  final IconData icon;
  final String label;
  final String caption;
  final int destination;
}
