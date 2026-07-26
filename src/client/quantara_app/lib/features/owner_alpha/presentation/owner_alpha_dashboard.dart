part of 'owner_alpha_page.dart';

class _RadarDashboard extends StatelessWidget {
  const _RadarDashboard({
    required this.controller,
    required this.snapshot,
    required this.onOpenAnalysis,
  });

  final OwnerAlphaController controller;
  final OwnerAlphaSnapshot snapshot;
  final ValueChanged<String> onOpenAnalysis;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final opportunities = snapshot.opportunities;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                strings.opportunitiesRadar,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: StatusPill(
                  label: opportunities.isEmpty
                      ? strings.noOpportunity
                      : strings.opportunityCount(opportunities.length),
                  color: opportunities.isEmpty
                      ? QuantaraColors.warning
                      : QuantaraColors.success,
                  icon: Icons.radar_rounded,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                opportunities.isEmpty
                    ? strings.emptyRadarDescription
                    : strings.radarDescription,
              ),
              const SizedBox(height: 10),
              Text(
                strings.lastScan(
                  DateTime.now().toUtc().difference(snapshot.generatedAt),
                ),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (snapshot.scanFailures.isNotEmpty) ...[
          SectionCard(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  color: QuantaraColors.warning,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    strings.partialScanDescription(
                      snapshot.scanFailures.length,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (opportunities.isEmpty)
          _NoTradeCard(snapshot: snapshot)
        else
          for (var index = 0; index < opportunities.length; index++) ...[
            _OpportunityCard(
              idea: opportunities[index],
              taken: controller.isTaken(opportunities[index].setupId),
              onTakenChanged: (value) => controller.setTaken(
                opportunities[index].setupId,
                value,
              ),
              onTap: () => onOpenAnalysis(opportunities[index].symbol),
            ),
            if (index != opportunities.length - 1) const SizedBox(height: 12),
          ],
        const SizedBox(height: 16),
        _RadarCoverage(snapshot: snapshot),
        const SizedBox(height: 16),
        const _AlphaSafetyCard(),
      ],
    );
  }
}

class _NoTradeCard extends StatelessWidget {
  const _NoTradeCard({required this.snapshot});

  final OwnerAlphaSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return SectionCard(
      semanticLabel: strings.noSetupSemantic,
      child: Column(
        children: [
          const Icon(
            Icons.hourglass_top_rounded,
            size: 46,
            color: QuantaraColors.warning,
          ),
          const SizedBox(height: 12),
          Text(
            strings.wait,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: QuantaraColors.warning,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            strings.checkedSymbols(snapshot.radar.length),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _OpportunityCard extends StatelessWidget {
  const _OpportunityCard({
    required this.idea,
    required this.taken,
    required this.onTakenChanged,
    required this.onTap,
  });

  final TradeIdea idea;
  final bool taken;
  final ValueChanged<bool> onTakenChanged;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final color = _ideaColor(context, idea.direction);
    return SectionCard(
      semanticLabel: AppStrings.of(
        context,
      ).setupSemantic(_ideaLabel(context, idea.direction), idea.symbol),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: SizedBox.square(
                  dimension: 48,
                  child: Icon(
                    idea.direction == TradeDirection.long
                        ? Icons.trending_up_rounded
                        : Icons.trending_down_rounded,
                    color: color,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      idea.symbol,
                      textDirection: TextDirection.ltr,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      '${_ideaLabel(context, idea.direction)} · ${idea.timeframe}',
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: StatusPill(
              label:
                  '${strings.score} ${strings.integer(idea.confidencePercent)}',
              color: color,
            ),
          ),
          const SizedBox(height: 14),
          Text(idea.summary),
          const SizedBox(height: 14),
          Wrap(
            spacing: 20,
            runSpacing: 12,
            children: [
              MetricTile(
                label: strings.entry,
                value:
                    '${QuantaraNumberFormat.marketValue(idea.entryLower!)} – ${QuantaraNumberFormat.marketValue(idea.entryUpper!)}',
              ),
              MetricTile(
                label: strings.stopLoss,
                value: QuantaraNumberFormat.marketValue(idea.stopLoss!),
                valueColor: QuantaraColors.danger,
              ),
              MetricTile(
                label: strings.riskReward,
                value: '1:${idea.riskReward!.toStringAsFixed(2)}',
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
                label: strings.recommendedLeverage,
                value: '${idea.recommendedLeverage}x',
                caption: strings.leverageCaption,
              ),
              MetricTile(
                label: strings.requiredMargin,
                value: QuantaraNumberFormat.marketValue(
                  idea.requiredMargin!,
                  unit: 'USDT',
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: taken,
                  onChanged: (value) => onTakenChanged(value ?? false),
                  title: Text(strings.taken),
                  subtitle: Text(strings.markTaken),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonalIcon(
                onPressed: onTap,
                icon: const Icon(Icons.candlestick_chart_rounded),
                label: Text(strings.inspectChart),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RadarCoverage extends StatelessWidget {
  const _RadarCoverage({required this.snapshot});

  final OwnerAlphaSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            strings.hourlyCoverage,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 12),
          for (var index = 0; index < snapshot.radar.length; index++) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    snapshot.radar[index].quote.symbol,
                    textDirection: TextDirection.ltr,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                Text(
                  QuantaraNumberFormat.marketValue(
                    snapshot.radar[index].quote.lastPrice,
                  ),
                  textDirection: TextDirection.ltr,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final entry
                      in snapshot.radar[index].ideasByTimeframe.entries)
                    StatusPill(
                      label:
                          '${entry.key} · ${_ideaLabel(context, entry.value.direction)}',
                      color: _ideaColor(context, entry.value.direction),
                    ),
                ],
              ),
            ),
            if (index != snapshot.radar.length - 1) const Divider(height: 24),
          ],
        ],
      ),
    );
  }
}

class _AlphaSafetyCard extends StatelessWidget {
  const _AlphaSafetyCard();

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return SectionCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.lock_rounded, color: QuantaraColors.cyan),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  strings.safetyBoundary,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(strings.safetyDescription),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
