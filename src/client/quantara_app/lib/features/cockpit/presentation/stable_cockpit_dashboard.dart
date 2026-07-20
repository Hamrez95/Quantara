part of 'stable_cockpit_page.dart';

class _Dashboard extends StatelessWidget {
  const _Dashboard({required this.snapshot});

  final CockpitSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _DecisionSummary(analysis: snapshot.analysis),
        const SizedBox(height: 16),
        _AccountSummary(account: snapshot.paperAccount),
        const SizedBox(height: 16),
        _CompactMarketList(quotes: snapshot.watchlist),
        const SizedBox(height: 16),
        const _RealMoneyLockCard(compact: true),
      ],
    );
  }
}

class _DecisionSummary extends StatelessWidget {
  const _DecisionSummary({required this.analysis});

  final ExplainableAnalysis analysis;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final decisionColor = _decisionColor(context, analysis.decision);
    final leadingFactors = analysis.factors.take(2).toList(growable: false);

    return SectionCard(
      semanticLabel: 'نتیجه فعلی تحلیل',
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: decisionColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: SizedBox.square(
                  dimension: 52,
                  child: Icon(
                    _decisionIcon(analysis.decision),
                    color: decisionColor,
                    size: 28,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'نتیجه فعلی',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: scheme.onSurface.withValues(alpha: 0.62),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _decisionLabel(analysis.decision),
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: decisionColor,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              StatusPill(
                label:
                    'اطمینان ${QuantaraNumberFormat.persianInteger(analysis.confidencePercent)}٪',
                color: scheme.secondary,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            analysis.summary,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.55),
          ),
          if (leadingFactors.isNotEmpty) ...[
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: leadingFactors
                  .map((factor) => _ReasonChip(factor: factor))
                  .toList(growable: false),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Icon(Icons.schedule_rounded, size: 18, color: scheme.outline),
              const SizedBox(width: 6),
              Text(
                QuantaraNumberFormat.relativePersian(analysis.freshness),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const Spacer(),
              Text(
                analysis.symbol,
                textDirection: TextDirection.ltr,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReasonChip extends StatelessWidget {
  const _ReasonChip({required this.factor});

  final AnalysisFactor factor;

  @override
  Widget build(BuildContext context) {
    final color = _impactColor(context, factor.impact);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_impactIcon(factor.impact), color: color, size: 16),
            const SizedBox(width: 6),
            Text(
              factor.title,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AccountSummary extends StatelessWidget {
  const _AccountSummary({required this.account});

  final PaperAccountSummary account;

  @override
  Widget build(BuildContext context) {
    final pnlColor = account.dailyPnl >= 0
        ? QuantaraColors.success
        : Theme.of(context).colorScheme.error;

    return SectionCard(
      semanticLabel: 'خلاصه حساب آزمایشی',
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'حساب آزمایشی',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const StatusPill(
                label: 'آزمایشی',
                color: QuantaraColors.cyan,
                icon: Icons.wallet_outlined,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            QuantaraNumberFormat.marketValue(account.equity, unit: 'USDT'),
            textDirection: TextDirection.ltr,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 20,
            runSpacing: 14,
            children: [
              _SmallMetric(
                label: 'موجودی آزاد',
                value: QuantaraNumberFormat.marketValue(account.availableBalance),
                ltr: true,
              ),
              _SmallMetric(
                label: 'سود و زیان امروز',
                value:
                    '${account.dailyPnl > 0 ? '+' : ''}${QuantaraNumberFormat.marketValue(account.dailyPnl)}',
                valueColor: pnlColor,
                ltr: true,
              ),
              _SmallMetric(
                label: 'موقعیت باز',
                value: QuantaraNumberFormat.persianInteger(account.openPositions),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: Text(
                  'مصرف ریسک امروز',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                '${QuantaraNumberFormat.persianPercent(account.currentDailyRiskPercent, decimals: 1)} از ${QuantaraNumberFormat.persianPercent(account.maximumDailyRiskPercent)}',
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ],
          ),
          const SizedBox(height: 9),
          RiskProgress(
            current: account.currentDailyRiskPercent,
            maximum: account.maximumDailyRiskPercent,
          ),
        ],
      ),
    );
  }
}

class _SmallMetric extends StatelessWidget {
  const _SmallMetric({
    required this.label,
    required this.value,
    this.valueColor,
    this.ltr = false,
  });

  final String label;
  final String value;
  final Color? valueColor;
  final bool ltr;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 105),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 3),
          Text(
            value,
            textDirection: ltr ? TextDirection.ltr : null,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: valueColor,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactMarketList extends StatelessWidget {
  const _CompactMarketList({required this.quotes});

  final List<MarketQuote> quotes;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      semanticLabel: 'بازارهای منتخب',
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'بازارهای منتخب',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const StatusPill(
                label: 'نمایشی',
                color: QuantaraColors.warning,
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (var index = 0; index < quotes.length; index++) ...[
            _QuoteRow(quote: quotes[index]),
            if (index != quotes.length - 1) const Divider(height: 1),
          ],
        ],
      ),
    );
  }
}
