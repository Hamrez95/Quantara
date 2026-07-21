part of 'stable_cockpit_page.dart';

class _AnalysisDetails extends StatelessWidget {
  const _AnalysisDetails({required this.analysis});

  final ExplainableAnalysis analysis;

  @override
  Widget build(BuildContext context) {
    final decisionColor = _decisionColor(context, analysis.decision);
    return SectionCard(
      semanticLabel: 'تحلیل و دلیل تصمیم',
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'تحلیل و دلیل تصمیم',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
              StatusPill(
                label: _decisionLabel(analysis.decision),
                color: decisionColor,
                icon: _decisionIcon(analysis.decision),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            analysis.summary,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.6),
          ),
          const SizedBox(height: 20),
          Text(
            'دلایل اصلی',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          for (final factor in analysis.factors)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _FactorTile(factor: factor),
            ),
          const SizedBox(height: 8),
          _ReconsiderationCard(text: analysis.invalidation),
        ],
      ),
    );
  }
}

class _FactorTile extends StatelessWidget {
  const _FactorTile({required this.factor});

  final AnalysisFactor factor;

  @override
  Widget build(BuildContext context) {
    final color = _impactColor(context, factor.impact);
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
                color: color.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: SizedBox.square(
                dimension: 34,
                child: Icon(_impactIcon(factor.impact), color: color, size: 19),
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    factor.title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    factor.detail,
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(height: 1.5),
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

class _ReconsiderationCard extends StatelessWidget {
  const _ReconsiderationCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
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
            Icon(Icons.refresh_rounded, color: scheme.primary, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'چه زمانی دوباره بررسی شود؟',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    text,
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
    );
  }
}

class _PaperAccountDetails extends StatelessWidget {
  const _PaperAccountDetails({required this.account});

  final PaperAccountSummary account;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _AccountSummary(account: account),
        const SizedBox(height: 16),
        SectionCard(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'جزئیات حساب آزمایشی',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 18),
              _AccountLine(
                label: 'وجه تضمین درگیر',
                value: QuantaraNumberFormat.marketValue(
                  account.usedMargin,
                  unit: 'USDT',
                ),
                ltr: true,
              ),
              _AccountLine(
                label: 'موقعیت‌های باز',
                value: QuantaraNumberFormat.persianInteger(
                  account.openPositions,
                ),
              ),
              _AccountLine(
                label: 'سقف ریسک روزانه',
                value: QuantaraNumberFormat.persianPercent(
                  account.maximumDailyRiskPercent,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const _RealMoneyLockCard(),
      ],
    );
  }
}

class _AccountLine extends StatelessWidget {
  const _AccountLine({
    required this.label,
    required this.value,
    this.ltr = false,
  });

  final String label;
  final String value;
  final bool ltr;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(
            value,
            textDirection: ltr ? TextDirection.ltr : null,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

