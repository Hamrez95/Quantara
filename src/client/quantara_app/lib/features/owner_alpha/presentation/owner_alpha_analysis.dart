part of 'owner_alpha_page.dart';

class _AlphaAnalysisView extends StatelessWidget {
  const _AlphaAnalysisView({required this.controller, required this.snapshot});

  final OwnerAlphaController controller;
  final OwnerAlphaSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final analysis = snapshot.selectedAnalysis;
    final idea = snapshot.selectedIdea;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _AnalysisHero(analysis: analysis, idea: idea),
        const SizedBox(height: 16),
        _AnalysisMarketSelector(controller: controller),
        const SizedBox(height: 16),
        _AnalysisChartCard(
          controller: controller,
          analysis: analysis,
          idea: idea,
        ),
        const SizedBox(height: 16),
        _MultiTimeframeCard(directions: snapshot.timeframeDirections),
        const SizedBox(height: 16),
        _TradePlanCard(controller: controller, idea: idea),
        const SizedBox(height: 16),
        _PriceZonesCard(analysis: analysis),
      ],
    );
  }
}

class _AnalysisHero extends StatelessWidget {
  const _AnalysisHero({required this.analysis, required this.idea});

  final TimeframeChartAnalysis analysis;
  final TradeIdea idea;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final scheme = Theme.of(context).colorScheme;
    final directionColor = _chartDirectionColor(analysis.direction);
    final actionableColor = _ideaColor(context, idea.direction);
    return Semantics(
      container: true,
      label: '${strings.analysis}. ${analysis.symbol}. ${analysis.timeframe}',
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(QuantaraRadius.large),
          border: Border.all(
            color: directionColor.withValues(alpha: 0.3),
          ),
          gradient: LinearGradient(
            begin: AlignmentDirectional.topStart,
            end: AlignmentDirectional.bottomEnd,
            colors: [
              Color.alphaBlend(
                directionColor.withValues(alpha: 0.17),
                scheme.surface,
              ),
              Color.alphaBlend(
                QuantaraColors.violet.withValues(alpha: 0.11),
                scheme.surface,
              ),
              scheme.surface,
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: directionColor.withValues(alpha: 0.1),
              blurRadius: 34,
              spreadRadius: -18,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: Stack(
          children: [
            PositionedDirectional(
              top: -78,
              end: -66,
              child: IgnorePointer(
                child: Container(
                  width: 210,
                  height: 210,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        QuantaraColors.cyan.withValues(alpha: 0.18),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final compact = constraints.maxWidth < 620;
                      final identity = Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SymbolAvatar(symbol: analysis.symbol, size: 58),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  strings.t('تحلیل بازار', 'Market analysis'),
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall
                                      ?.copyWith(fontWeight: FontWeight.w900),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  '${analysis.symbol} · ${analysis.timeframe}',
                                  textDirection: TextDirection.ltr,
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(
                                        color: directionColor,
                                        fontWeight: FontWeight.w900,
                                      ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  analysis.summary,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: scheme.onSurfaceVariant,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                      final pills = Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: compact
                            ? WrapAlignment.start
                            : WrapAlignment.end,
                        children: [
                          StatusPill(
                            label: _directionLabel(
                              context,
                              analysis.direction,
                            ),
                            color: directionColor,
                            icon: analysis.direction == ChartDirection.bullish
                                ? Icons.north_east_rounded
                                : analysis.direction == ChartDirection.bearish
                                ? Icons.south_east_rounded
                                : Icons.east_rounded,
                          ),
                          StatusPill(
                            label: _ideaLabel(context, idea.direction),
                            color: actionableColor,
                            icon: idea.isActionable
                                ? Icons.bolt_rounded
                                : Icons.pause_rounded,
                          ),
                        ],
                      );
                      if (compact) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            identity,
                            const SizedBox(height: 14),
                            pills,
                          ],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: identity),
                          const SizedBox(width: 16),
                          Flexible(child: pills),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 18),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final columns = constraints.maxWidth >= 720 ? 3 : 1;
                      const gap = 10.0;
                      final width =
                          (constraints.maxWidth - gap * (columns - 1)) /
                          columns;
                      final metrics = [
                        (
                          strings.t('قدرت ساختار', 'Structure strength'),
                          '${(analysis.directionStrength * 100).round()}%',
                          Icons.speed_rounded,
                          directionColor,
                        ),
                        (
                          strings.t('نواحی فعال', 'Active zones'),
                          '${analysis.zones.length}',
                          Icons.layers_outlined,
                          QuantaraColors.violet,
                        ),
                        (
                          strings.score,
                          '${idea.confidencePercent}/100',
                          Icons.analytics_outlined,
                          idea.isActionable
                              ? QuantaraColors.success
                              : QuantaraColors.warning,
                        ),
                      ];
                      return Wrap(
                        spacing: gap,
                        runSpacing: gap,
                        children: [
                          for (final metric in metrics)
                            SizedBox(
                              width: width,
                              child: FinanceMetricPanel(
                                label: metric.$1,
                                value: metric.$2,
                                icon: metric.$3,
                                color: metric.$4,
                              ),
                            ),
                        ],
                      );
                    },
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

class _AnalysisMarketSelector extends StatelessWidget {
  const _AnalysisMarketSelector({required this.controller});

  final OwnerAlphaController controller;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return SectionCard(
      accentColor: QuantaraColors.electricBlue,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeading(
            title: strings.t('بازار و بازه زمانی', 'Market and timeframe'),
            subtitle: strings.t(
              'نماد و تایم‌فریم را انتخاب کن؛ چارت و برنامه ریسک با یک Snapshot سازگار تازه می‌شوند.',
              'Choose a symbol and timeframe; chart and risk plan refresh from one consistent snapshot.',
            ),
          ),
          const SizedBox(height: 14),
          Text(
            strings.symbol,
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final symbol in controller.symbols) ...[
                  ChoiceChip(
                    showCheckmark: false,
                    avatar: SymbolAvatar(
                      symbol: symbol,
                      size: 23,
                      showBorder: false,
                    ),
                    label: Text(
                      symbol,
                      textDirection: TextDirection.ltr,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    selected: symbol == controller.selectedSymbol,
                    onSelected: controller.isLoading
                        ? null
                        : (_) => controller.selectSymbol(symbol),
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          Text(
            strings.timeframe,
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<String>(
              showSelectedIcon: false,
              segments: [
                for (final timeframe in OwnerAlphaController.timeframes)
                  ButtonSegment(
                    value: timeframe,
                    icon: const Icon(Icons.schedule_rounded, size: 16),
                    label: Text(
                      timeframe,
                      key: ValueKey('alpha-timeframe-$timeframe'),
                    ),
                  ),
              ],
              selected: {controller.selectedTimeframe},
              onSelectionChanged: controller.isLoading
                  ? null
                  : (value) => controller.selectTimeframe(value.single),
            ),
          ),
        ],
      ),
    );
  }
}

class _AnalysisChartCard extends StatelessWidget {
  const _AnalysisChartCard({
    required this.controller,
    required this.analysis,
    required this.idea,
  });

  final OwnerAlphaController controller;
  final TimeframeChartAnalysis analysis;
  final TradeIdea idea;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final scheme = Theme.of(context).colorScheme;
    return SectionCard(
      accentColor: _chartDirectionColor(analysis.direction),
      padding: const EdgeInsets.fromLTRB(10, 14, 10, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 520;
                final title = Row(
                  children: [
                    SymbolAvatar(symbol: analysis.symbol, size: 44),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${analysis.symbol} · ${analysis.timeframe}',
                            textDirection: TextDirection.ltr,
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                          Text(
                            strings.t(
                              'چارت، نواحی و سناریوی مدیریت سرمایه',
                              'Chart, zones and risk-managed scenario',
                            ),
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
                final overlay = controller.selectedChartSignal == null
                    ? const SizedBox.shrink()
                    : StatusPill(
                        label: strings.isPersian
                            ? 'ستاپ ذخیره‌شده روی چارت'
                            : 'Frozen setup overlay',
                        color: QuantaraColors.violet,
                        icon: Icons.layers_rounded,
                      );
                if (compact) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      title,
                      if (controller.selectedChartSignal != null) ...[
                        const SizedBox(height: 10),
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: overlay,
                        ),
                      ],
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: title),
                    const SizedBox(width: 10),
                    overlay,
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: TradingViewLightweightChart(
              analysis: analysis,
              idea: idea,
              frozenSignal: controller.selectedChartSignal,
            ),
          ),
          const SizedBox(height: 9),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 16,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    strings.chartAttribution,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
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

class _MultiTimeframeCard extends StatelessWidget {
  const _MultiTimeframeCard({required this.directions});

  final Map<String, ChartDirection> directions;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return SectionCard(
      accentColor: QuantaraColors.cyan,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeading(
            title: strings.multiTimeframe,
            subtitle: strings.t(
              'جهت هر بازه مستقل محاسبه می‌شود؛ توافق بیشتر یعنی ساختار شفاف‌تر، نه تضمین نتیجه.',
              'Each timeframe is calculated independently; more agreement means clearer structure, not guaranteed outcome.',
            ),
            trailing: _InfoButton(
              title: strings.multiTimeframe,
              paragraphs: [strings.strategyDescription],
            ),
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth >= 720
                  ? (constraints.maxWidth - 30) / 4
                  : constraints.maxWidth >= 420
                  ? (constraints.maxWidth - 10) / 2
                  : constraints.maxWidth;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final entry in directions.entries)
                    SizedBox(
                      width: width,
                      child: _TimeframeDirectionTile(
                        timeframe: entry.key,
                        direction: entry.value,
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

class _TimeframeDirectionTile extends StatelessWidget {
  const _TimeframeDirectionTile({
    required this.timeframe,
    required this.direction,
  });

  final String timeframe;
  final ChartDirection direction;

  @override
  Widget build(BuildContext context) {
    final color = _chartDirectionColor(direction);
    final icon = direction == ChartDirection.bullish
        ? Icons.north_east_rounded
        : direction == ChartDirection.bearish
        ? Icons.south_east_rounded
        : Icons.east_rounded;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            color.withValues(alpha: 0.13),
            Theme.of(
              context,
            ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          ],
        ),
        borderRadius: BorderRadius.circular(QuantaraRadius.control),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        child: Row(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(10),
              ),
              child: SizedBox.square(
                dimension: 34,
                child: Icon(icon, size: 19, color: color),
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    timeframe,
                    textDirection: TextDirection.ltr,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    _directionLabel(context, direction),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w800,
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

class _TradePlanCard extends StatelessWidget {
  const _TradePlanCard({required this.controller, required this.idea});

  final OwnerAlphaController controller;
  final TradeIdea idea;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final color = _ideaColor(context, idea.direction);
    final journalEntry = controller.signalEntry(idea.setupId);
    final selectedLeverage =
        journalEntry?.selectedLeverage ?? idea.recommendedLeverage ?? 1;
    final selectedMargin = idea.marginAt(selectedLeverage);
    final persian = Directionality.of(context) == TextDirection.rtl;
    return SectionCard(
      accentColor: color,
      semanticLabel: strings.riskPlan,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeading(
            title: strings.riskPlan,
            subtitle: strings.t(
              'ورود، حد ضرر، تارگت‌ها، اندازه پوزیشن و هزینه‌ها در یک برنامه منسجم',
              'Entry, stop, targets, position size and costs in one coherent plan',
            ),
            trailing: _InfoButton(
              title: strings.riskPlan,
              paragraphs: [
                strings.riskSettingsDescription,
                strings.leverageCaption,
                strings.lossEstimateWarning,
              ],
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              StatusPill(
                label: _ideaLabel(context, idea.direction),
                color: color,
                icon: idea.direction == TradeDirection.wait
                    ? Icons.pause_rounded
                    : idea.direction == TradeDirection.long
                    ? Icons.north_east_rounded
                    : Icons.south_east_rounded,
              ),
              StatusPill(
                label: strings.t(
                  'امتیاز ${idea.confidencePercent}',
                  'Score ${idea.confidencePercent}',
                ),
                color: QuantaraColors.violet,
                icon: Icons.analytics_outlined,
              ),
              if (idea.riskReward != null)
                StatusPill(
                  label: 'R:R 1:${idea.riskReward!.toStringAsFixed(2)}',
                  color: QuantaraColors.cyan,
                  icon: Icons.balance_rounded,
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(idea.summary),
          const SizedBox(height: 16),
          if (!idea.isActionable)
            DecoratedBox(
              decoration: BoxDecoration(
                color: QuantaraColors.warning.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: QuantaraColors.warning.withValues(alpha: 0.24),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.hourglass_top_rounded,
                      color: QuantaraColors.warning,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        strings.t(
                          'ساختار فعلی هنوز شرایط ورود ایمن را ندارد؛ Quantara به‌جای تولید سیگنال ضعیف منتظر می‌ماند.',
                          'The current structure does not meet safe-entry requirements; Quantara waits instead of producing a weak setup.',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else ...[
            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth >= 760
                    ? (constraints.maxWidth - 30) / 4
                    : constraints.maxWidth >= 430
                    ? (constraints.maxWidth - 10) / 2
                    : constraints.maxWidth;
                final metrics = <(String, String, Color?)>[
                  (
                    strings.entryRange,
                    '${QuantaraNumberFormat.marketValue(idea.entryLower!)} – ${QuantaraNumberFormat.marketValue(idea.entryUpper!)}',
                    null,
                  ),
                  (
                    strings.stopLoss,
                    QuantaraNumberFormat.marketValue(idea.stopLoss!),
                    QuantaraColors.danger,
                  ),
                  for (var index = 0; index < idea.targets.length; index++)
                    (
                      strings.target(index + 1),
                      QuantaraNumberFormat.marketValue(idea.targets[index]),
                      QuantaraColors.success,
                    ),
                  (
                    strings.positionSize,
                    idea.positionSize!.toStringAsFixed(5),
                    null,
                  ),
                  (
                    strings.notionalValue,
                    QuantaraNumberFormat.marketValue(
                      idea.notionalValue!,
                      unit: 'USDT',
                    ),
                    QuantaraColors.cyan,
                  ),
                  (
                    strings.requiredMargin,
                    QuantaraNumberFormat.marketValue(
                      selectedMargin ?? idea.requiredMargin!,
                      unit: 'USDT',
                    ),
                    QuantaraColors.violet,
                  ),
                  (
                    strings.maximumLoss,
                    QuantaraNumberFormat.marketValue(
                      idea.maximumLoss,
                      unit: 'USDT',
                    ),
                    QuantaraColors.warning,
                  ),
                  (
                    strings.estimatedCost,
                    QuantaraNumberFormat.marketValue(
                      idea.estimatedRoundTripCosts,
                      unit: 'USDT',
                    ),
                    null,
                  ),
                ];
                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final metric in metrics)
                      SizedBox(
                        width: width,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: (metric.$3 ?? color).withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: (metric.$3 ?? color).withValues(
                                alpha: 0.17,
                              ),
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: MetricTile(
                              label: metric.$1,
                              value: metric.$2,
                              valueColor: metric.$3,
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            _LeverageControl(
              selected: selectedLeverage,
              recommended: idea.recommendedLeverage!,
              safeCap: idea.maximumSafeLeverage!,
              onChanged: (leverage) =>
                  controller.setSignalLeverage(idea.setupId, leverage),
            ),
            const SizedBox(height: 12),
            DecoratedBox(
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.075),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: color.withValues(alpha: 0.2)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(
                  persian
                      ? 'در اهرم ${selectedLeverage}x حدود ${QuantaraNumberFormat.marketValue(selectedMargin ?? idea.requiredMargin!, unit: 'USDT')} مارجین درگیر می‌شود؛ ارزش پوزیشن و سقف زیان برنامه‌ریزی‌شده تغییر نمی‌کند.'
                      : 'At ${selectedLeverage}x about ${QuantaraNumberFormat.marketValue(selectedMargin ?? idea.requiredMargin!, unit: 'USDT')} margin is used; position notional and planned loss cap do not change.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          Text(
            strings.t('دلایل تحلیل', 'Analysis reasons'),
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          for (final reason in idea.reasons) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.check_circle_outline, size: 18, color: color),
                const SizedBox(width: 8),
                Expanded(child: Text(reason)),
              ],
            ),
            const SizedBox(height: 7),
          ],
          const Divider(height: 24),
          DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.error.withValues(alpha: 0.075),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: Theme.of(
                  context,
                ).colorScheme.error.withValues(alpha: 0.2),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: Theme.of(context).colorScheme.error,
                    size: 20,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      strings.invalidation(idea.invalidation),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.error,
                        fontWeight: FontWeight.w800,
                      ),
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

class _PriceZonesCard extends StatelessWidget {
  const _PriceZonesCard({required this.analysis});

  final TimeframeChartAnalysis analysis;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return SectionCard(
      accentColor: QuantaraColors.violet,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeading(
            title: strings.priceZones,
            subtitle: strings.t(
              'نواحی براساس تماس‌ها، قدرت ساختار و فاصله از قیمت فعلی رتبه‌بندی می‌شوند.',
              'Zones are ranked by touches, structural strength and distance from current price.',
            ),
            trailing: _InfoButton(
              title: strings.priceZones,
              paragraphs: [strings.strategyDescription],
            ),
          ),
          const SizedBox(height: 14),
          if (analysis.strongestZones.isEmpty)
            Text(strings.noZones)
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth >= 760
                    ? (constraints.maxWidth - 10) / 2
                    : constraints.maxWidth;
                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final zone in analysis.strongestZones)
                      SizedBox(
                        width: width,
                        child: _AlphaZoneRow(zone: zone),
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

class _AlphaZoneRow extends StatelessWidget {
  const _AlphaZoneRow({required this.zone});

  final ChartPriceZone zone;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final label = switch (zone.role) {
      ChartZoneRole.support => strings.support,
      ChartZoneRole.resistance => strings.resistance,
      ChartZoneRole.pivot => strings.decisionZone,
    };
    final color = switch (zone.role) {
      ChartZoneRole.support => QuantaraColors.success,
      ChartZoneRole.resistance => QuantaraColors.danger,
      ChartZoneRole.pivot => QuantaraColors.violet,
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: [
            color.withValues(alpha: 0.12),
            Theme.of(
              context,
            ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.48),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: SizedBox.square(
                    dimension: 38,
                    child: Icon(
                      zone.role == ChartZoneRole.support
                          ? Icons.south_rounded
                          : zone.role == ChartZoneRole.resistance
                          ? Icons.north_rounded
                          : Icons.my_location_rounded,
                      color: color,
                      size: 20,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: color,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        '${QuantaraNumberFormat.marketValue(zone.lower)} – ${QuantaraNumberFormat.marketValue(zone.upper)}',
                        textDirection: TextDirection.ltr,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            RiskProgress(current: zone.strength, maximum: 1),
            const SizedBox(height: 7),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                StatusPill(
                  label: strings.strength((zone.strength * 100).round()),
                  color: color,
                  icon: Icons.signal_cellular_alt_rounded,
                ),
                StatusPill(
                  label: strings.t(
                    '${zone.touchCount} تماس',
                    '${zone.touchCount} touches',
                  ),
                  color: QuantaraColors.cyan,
                  icon: Icons.touch_app_outlined,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              zone.explanation,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
