part of 'stable_cockpit_page.dart';

class _MarketsView extends StatefulWidget {
  const _MarketsView({required this.quotes});

  final List<MarketQuote> quotes;

  @override
  State<_MarketsView> createState() => _MarketsViewState();
}

class _MarketsViewState extends State<_MarketsView> {
  int _selectedIndex = 0;
  String _timeframe = '1h';

  @override
  void didUpdateWidget(covariant _MarketsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_selectedIndex >= widget.quotes.length) {
      _selectedIndex = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    if (widget.quotes.isEmpty) {
      return SectionCard(
        child: Text('${strings.markets} برای نمایش وجود ندارد.'),
      );
    }

    final selected = widget.quotes[_selectedIndex];
    final analysis = DemoMarketChartFactory.create(
      quote: selected,
      timeframe: _timeframe,
    );
    final positive = selected.changePercent >= 0;
    final changeColor = positive
        ? QuantaraColors.success
        : QuantaraColors.danger;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionCard(
          semanticLabel: strings.markets,
          padding: const EdgeInsets.all(18),
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
                          selected.symbol,
                          textDirection: TextDirection.ltr,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          QuantaraNumberFormat.marketValue(
                            selected.price,
                            unit: 'USDT',
                          ),
                          textDirection: TextDirection.ltr,
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                      ],
                    ),
                  ),
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: StatusPill(
                      label: QuantaraNumberFormat.marketPercent(
                        selected.changePercent,
                      ),
                      color: changeColor,
                      icon: positive
                          ? Icons.arrow_upward_rounded
                          : Icons.arrow_downward_rounded,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: ['15m', '1h', '4h', '1D']
                    .map(
                      (value) => ChoiceChip(
                        key: ValueKey('timeframe-$value'),
                        label: Text(value, textDirection: TextDirection.ltr),
                        selected: _timeframe == value,
                        onSelected: (_) => setState(() => _timeframe = value),
                      ),
                    )
                    .toList(growable: false),
              ),
              const SizedBox(height: 18),
              Text(
                'نمودار کندل‌استیک',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              QuantaraCandlestickChart(analysis: analysis),
              const SizedBox(height: 14),
              _StructureSummary(analysis: analysis),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _ImportantZones(analysis: analysis),
        const SizedBox(height: 16),
        SectionCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              for (var index = 0; index < widget.quotes.length; index++) ...[
                _QuoteRow(
                  quote: widget.quotes[index],
                  selected: index == _selectedIndex,
                  onTap: () => setState(() => _selectedIndex = index),
                ),
                if (index != widget.quotes.length - 1)
                  const Divider(height: 1),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _StructureSummary extends StatelessWidget {
  const _StructureSummary({required this.analysis});

  final TimeframeChartAnalysis analysis;

  @override
  Widget build(BuildContext context) {
    final directionColor = switch (analysis.direction) {
      ChartDirection.bullish => QuantaraColors.success,
      ChartDirection.bearish => QuantaraColors.danger,
      ChartDirection.sideways => QuantaraColors.warning,
    };
    final directionLabel = switch (analysis.direction) {
      ChartDirection.bullish => 'ساختار صعودی',
      ChartDirection.bearish => 'ساختار نزولی',
      ChartDirection.sideways => 'ساختار خنثی',
    };

    return DecoratedBox(
      decoration: BoxDecoration(
        color: directionColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: directionColor.withValues(alpha: 0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                StatusPill(
                  label: directionLabel,
                  color: directionColor,
                  icon: switch (analysis.direction) {
                    ChartDirection.bullish => Icons.trending_up_rounded,
                    ChartDirection.bearish => Icons.trending_down_rounded,
                    ChartDirection.sideways => Icons.swap_horiz_rounded,
                  },
                ),
                StatusPill(
                  label:
                      'نوسان ${QuantaraNumberFormat.persianDecimal(analysis.volatilityPercent, decimals: 1)}٪',
                  color: Theme.of(context).colorScheme.secondary,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              analysis.summary,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                height: 1.55,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'تحلیل فعلی قطعی و نمایشی است؛ اتصال داده بیرونی در مرحله بعد انجام می‌شود.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _ImportantZones extends StatelessWidget {
  const _ImportantZones({required this.analysis});

  final TimeframeChartAnalysis analysis;

  @override
  Widget build(BuildContext context) {
    final zones = analysis.strongestZones.take(3).toList(growable: false);
    return SectionCard(
      semanticLabel: 'ناحیه‌های مهم قیمت',
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'حمایت و مقاومت',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                analysis.timeframe,
                textDirection: TextDirection.ltr,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'ناحیه‌ها از واکنش‌های تأییدشده، تازگی و شدت برگشت امتیاز می‌گیرند.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          if (zones.isEmpty)
            const Text('در این بازه ناحیه‌ای با شواهد کافی پیدا نشد.')
          else
            for (var index = 0; index < zones.length; index++) ...[
              _ZoneRow(zone: zones[index]),
              if (index != zones.length - 1) const Divider(height: 1),
            ],
        ],
      ),
    );
  }
}

class _ZoneRow extends StatelessWidget {
  const _ZoneRow({required this.zone});

  final ChartPriceZone zone;

  @override
  Widget build(BuildContext context) {
    final color = switch (zone.role) {
      ChartZoneRole.support => QuantaraColors.success,
      ChartZoneRole.resistance => QuantaraColors.warning,
      ChartZoneRole.pivot => QuantaraColors.violet,
    };
    final role = switch (zone.role) {
      ChartZoneRole.support => 'حمایت',
      ChartZoneRole.resistance => 'مقاومت',
      ChartZoneRole.pivot => 'ناحیه تصمیم',
    };
    final strength = (zone.strength * 100).round();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(13),
            ),
            child: SizedBox.square(
              dimension: 42,
              child: Icon(
                zone.role == ChartZoneRole.support
                    ? Icons.vertical_align_bottom_rounded
                    : zone.role == ChartZoneRole.resistance
                    ? Icons.vertical_align_top_rounded
                    : Icons.swap_vert_rounded,
                color: color,
              ),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 5,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      role,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (zone.state == ChartZoneState.flipped)
                      const StatusPill(
                        label: 'تغییر نقش',
                        color: QuantaraColors.violet,
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${QuantaraNumberFormat.marketValue(zone.lower)} – ${QuantaraNumberFormat.marketValue(zone.upper)}',
                  textDirection: TextDirection.ltr,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${QuantaraNumberFormat.persianInteger(zone.touchCount)} واکنش · قدرت ${QuantaraNumberFormat.persianInteger(strength)}٪ · فاصله ${QuantaraNumberFormat.persianDecimal(zone.distancePercent, decimals: 1)}٪',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
