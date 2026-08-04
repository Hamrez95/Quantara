part of 'owner_alpha_page.dart';

class _StrategyCard extends StatelessWidget {
  const _StrategyCard();

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final persian = Directionality.of(context) == TextDirection.rtl;
    final strategies = [
      (
        'Trend Pullback',
        persian
            ? 'پولبک به EMA20 در روند هم‌سو با EMA50، ADX/DMI و تایم‌فریم بالاتر'
            : 'EMA20 pullback aligned with EMA50, ADX/DMI and the higher timeframe',
        Icons.trending_up_rounded,
      ),
      (
        'Breakout + Retest',
        persian
            ? 'شکست روی کندل بسته با حجم نسبی، سپس Retest و پس‌گرفتن سطح'
            : 'Closed-candle breakout with relative volume, followed by a level retest and reclaim',
        Icons.show_chart_rounded,
      ),
      (
        'Arshia Candle Setup',
        persian
            ? 'کندل جهت‌دار ۱۵ دقیقه یا بالاتر با SMA7، EMA20/50، حجم و Stop ساختاری'
            : 'Directional candle at 15m or higher with SMA7, EMA20/50, volume and a structural stop',
        Icons.candlestick_chart_rounded,
      ),
      (
        'Range Reversal',
        persian
            ? 'برگشت از مرز حمایت یا مقاومت فقط در رنج کم‌ADX و بدون گسترش نوسان'
            : 'Support/resistance reversal only in a low-ADX range without volatility expansion',
        Icons.swap_horiz_rounded,
      ),
    ];
    final gates = persian
        ? const [
            'فقط کندل بسته و بدون Lookahead',
            'هم‌سویی و تازگی چندتایم‌فریمی',
            'Stop سمت درست و ساختاری',
            'کارمزد، لغزش و Funding',
            'حداقل حجم و Notional صرافی',
            'شناسه قطعی و جلوگیری از Duplicate',
            'رزرو اتمیک Risk و Margin',
            'قفل کامل ورود واقعی',
          ]
        : const [
            'Closed candles only; no lookahead',
            'Fresh multi-timeframe alignment',
            'Correct-side structural stop',
            'Fees, slippage and funding reserve',
            'Exchange quantity and notional minimums',
            'Deterministic identity and duplicate prevention',
            'Atomic risk and margin reservation',
            'Real-entry lock remains active',
          ];
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.schema_outlined, color: QuantaraColors.violet),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  strings.strategies,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
              _InfoButton(
                title: strings.strategies,
                paragraphs: [
                  strings.strategyDescription,
                  strings.strategyRules,
                  persian
                      ? 'این قواعد از اصول عمومی تحلیل روند، کندل، حمایت و مقاومت، حجم و مدیریت سرمایه الهام گرفته‌اند؛ سیگنال شخص یا دوره‌ای کپی نشده و سود تضمین نمی‌شود.'
                      : 'These rules apply general trend, candle, support/resistance, volume and risk-management principles. No educator signal is copied and profit is never guaranteed.',
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              StatusPill(
                label: 'Professional Pack 1.0',
                color: QuantaraColors.violet,
                icon: Icons.verified_outlined,
              ),
              StatusPill(
                label: persian ? 'Paper / تحلیل فقط' : 'Paper / analysis only',
                color: QuantaraColors.warning,
                icon: Icons.lock_outline_rounded,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            persian ? 'استراتژی‌های فعال' : 'Active strategies',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          for (final strategy in strategies) ...[
            _StrategyPackRow(
              title: strategy.$1,
              description: strategy.$2,
              icon: strategy.$3,
            ),
            const SizedBox(height: 8),
          ],
          const Divider(height: 28),
          Text(
            persian ? 'گیت‌های ایمنی اجباری' : 'Mandatory safety gates',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final gate in gates)
                StatusPill(
                  label: gate,
                  color: QuantaraColors.cyan,
                  icon: Icons.shield_outlined,
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            persian
                ? 'هر Candidate قابل اقدام قبل از ورود شبیه‌سازی‌شده به PortfolioEntryCandidate تبدیل می‌شود و باید بودجه Risk و Margin را به‌صورت اتمیک رزرو کند. realEntriesAllowed همچنان false است.'
                : 'Every actionable setup becomes a PortfolioEntryCandidate and must atomically reserve portfolio risk and margin before simulated admission. realEntriesAllowed remains false.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _StrategyPackRow extends StatelessWidget {
  const _StrategyPackRow({
    required this.title,
    required this.description,
    required this.icon,
  });

  final String title;
  final String description;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: QuantaraColors.violet, size: 21),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    textDirection: TextDirection.ltr,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(description, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoButton extends StatelessWidget {
  const _InfoButton({required this.title, required this.paragraphs});

  final String title;
  final List<String> paragraphs;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return IconButton(
      tooltip: strings.info,
      icon: const Icon(Icons.info_outline_rounded, size: 20),
      onPressed: () {
        showModalBottomSheet<void>(
          context: context,
          showDragHandle: true,
          builder: (context) => SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 4, 22, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 14),
                  for (final paragraph in paragraphs) ...[
                    Text(paragraph),
                    const SizedBox(height: 12),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
