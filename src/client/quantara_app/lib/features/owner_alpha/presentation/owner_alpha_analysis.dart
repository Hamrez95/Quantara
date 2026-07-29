part of 'owner_alpha_page.dart';

class _AlphaAnalysisView extends StatelessWidget {
  const _AlphaAnalysisView({required this.controller, required this.snapshot});

  final OwnerAlphaController controller;
  final OwnerAlphaSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final analysis = snapshot.selectedAnalysis;
    final idea = snapshot.selectedIdea;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
                        avatar: Icon(
                          symbol == controller.selectedSymbol
                              ? Icons.bolt_rounded
                              : Icons.show_chart_rounded,
                          size: 18,
                        ),
                        label: Text(
                          symbol,
                          textDirection: TextDirection.ltr,
                          style: const TextStyle(fontWeight: FontWeight.w800),
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
        ),
        const SizedBox(height: 16),
        SectionCard(
          padding: const EdgeInsets.fromLTRB(10, 14, 10, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
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
                    ),
                    const SizedBox(height: 8),
                    StatusPill(
                      label: _directionLabel(context, analysis.direction),
                      color: _chartDirectionColor(analysis.direction),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              TradingViewLightweightChart(analysis: analysis, idea: idea),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  strings.chartAttribution,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
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

class _MultiTimeframeCard extends StatelessWidget {
  const _MultiTimeframeCard({required this.directions});

  final Map<String, ChartDirection> directions;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  strings.multiTimeframe,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              _InfoButton(
                title: strings.multiTimeframe,
                paragraphs: [strings.strategyDescription],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final entry in directions.entries)
                StatusPill(
                  label:
                      '${entry.key} · ${_directionLabel(context, entry.value)}',
                  color: _chartDirectionColor(entry.value),
                ),
            ],
          ),
        ],
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
      semanticLabel: strings.riskPlan,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  strings.riskPlan,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
              _InfoButton(
                title: strings.riskPlan,
                paragraphs: [
                  strings.riskSettingsDescription,
                  strings.leverageCaption,
                  strings.lossEstimateWarning,
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          StatusPill(
            label: _ideaLabel(context, idea.direction),
            color: color,
            icon: idea.direction == TradeDirection.wait
                ? Icons.pause_rounded
                : idea.direction == TradeDirection.long
                ? Icons.north_east_rounded
                : Icons.south_east_rounded,
          ),
          const SizedBox(height: 12),
          Text(idea.summary),
          const SizedBox(height: 16),
          if (idea.isActionable) ...[
            Wrap(
              spacing: 24,
              runSpacing: 16,
              children: [
                MetricTile(
                  label: strings.entryRange,
                  value:
                      '${QuantaraNumberFormat.marketValue(idea.entryLower!)} – ${QuantaraNumberFormat.marketValue(idea.entryUpper!)}',
                ),
                MetricTile(
                  label: strings.stopLoss,
                  value: QuantaraNumberFormat.marketValue(idea.stopLoss!),
                  valueColor: QuantaraColors.danger,
                ),
                for (var index = 0; index < idea.targets.length; index++)
                  MetricTile(
                    label: strings.target(index + 1),
                    value: QuantaraNumberFormat.marketValue(
                      idea.targets[index],
                    ),
                    valueColor: QuantaraColors.success,
                  ),
                MetricTile(
                  label: strings.positionSize,
                  value: idea.positionSize!.toStringAsFixed(5),
                  caption: strings.unitsNoLeverage,
                ),
                MetricTile(
                  label: strings.notionalValue,
                  value: QuantaraNumberFormat.marketValue(
                    idea.notionalValue!,
                    unit: 'USDT',
                  ),
                ),
                MetricTile(
                  label: strings.recommendedLeverage,
                  value: '${idea.recommendedLeverage}x',
                  caption: strings.leverageCaption,
                ),
                MetricTile(
                  label: strings.requiredMargin,
                  value: QuantaraNumberFormat.marketValue(
                    selectedMargin ?? idea.requiredMargin!,
                    unit: 'USDT',
                  ),
                ),
                MetricTile(
                  label: strings.maximumLoss,
                  value: QuantaraNumberFormat.marketValue(
                    idea.maximumLoss,
                    unit: 'USDT',
                  ),
                  caption: strings.maximumLossCaption,
                  valueColor: QuantaraColors.warning,
                ),
                MetricTile(
                  label: strings.estimatedCost,
                  value: QuantaraNumberFormat.marketValue(
                    idea.estimatedRoundTripCosts,
                    unit: 'USDT',
                  ),
                  caption: strings.estimatedCostCaption,
                ),
                MetricTile(
                  label: strings.riskReward,
                  value: '1:${idea.riskReward!.toStringAsFixed(2)}',
                ),
              ],
            ),
            const SizedBox(height: 18),
            DecoratedBox(
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: color.withValues(alpha: 0.24)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      persian ? 'اهرم این سناریو' : 'Leverage for this setup',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      persian
                          ? 'اصل حرفه‌ای ساده است: اهرم، مارجین را آزاد می‌کند؛ سقف زیان را بالا نمی‌برد.'
                          : 'Professional rule: leverage frees margin; it does not raise the planned loss cap.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    _LeverageControl(
                      selected: selectedLeverage,
                      recommended: idea.recommendedLeverage!,
                      safeCap: idea.maximumSafeLeverage!,
                      onChanged: (leverage) =>
                          controller.setSignalLeverage(idea.setupId, leverage),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      persian
                          ? 'با ${selectedLeverage}x حدود ${QuantaraNumberFormat.marketValue(selectedMargin ?? idea.requiredMargin!, unit: 'USDT')} مارجین درگیر می‌شود؛ ارزش پوزیشن ${QuantaraNumberFormat.marketValue(idea.notionalValue!, unit: 'USDT')} و زیان برنامه‌ریزی‌شده حداکثر ${QuantaraNumberFormat.marketValue(idea.maximumLoss, unit: 'USDT')} می‌ماند.'
                          : 'At ${selectedLeverage}x, about ${QuantaraNumberFormat.marketValue(selectedMargin ?? idea.requiredMargin!, unit: 'USDT')} margin is used. Position notional stays ${QuantaraNumberFormat.marketValue(idea.notionalValue!, unit: 'USDT')} and planned loss stays capped at ${QuantaraNumberFormat.marketValue(idea.maximumLoss, unit: 'USDT')}.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
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
          Text(
            strings.invalidation(idea.invalidation),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.error,
              fontWeight: FontWeight.w700,
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  strings.priceZones,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              _InfoButton(
                title: strings.priceZones,
                paragraphs: [strings.strategyDescription],
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (analysis.strongestZones.isEmpty)
            Text(strings.noZones)
          else
            for (
              var index = 0;
              index < analysis.strongestZones.length;
              index++
            ) ...[
              _AlphaZoneRow(zone: analysis.strongestZones[index]),
              if (index != analysis.strongestZones.length - 1)
                const Divider(height: 20),
            ],
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
      ChartZoneRole.resistance => QuantaraColors.warning,
      ChartZoneRole.pivot => QuantaraColors.violet,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 5,
              height: 44,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(color: color, fontWeight: FontWeight.w900),
                  ),
                  Text(
                    '${QuantaraNumberFormat.marketValue(zone.lower)} – ${QuantaraNumberFormat.marketValue(zone.upper)}',
                    textDirection: TextDirection.ltr,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(strings.strength((zone.strength * 100).round())),
      ],
    );
  }
}
