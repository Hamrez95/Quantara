part of 'owner_alpha_page.dart';

class _RadarDashboard extends StatelessWidget {
  const _RadarDashboard({
    required this.controller,
    required this.snapshot,
    required this.realtimeMonitor,
    required this.onOpenAnalysis,
  });

  final OwnerAlphaController controller;
  final OwnerAlphaSnapshot snapshot;
  final ValueListenable<RealtimeMarketMonitorSnapshot>? realtimeMonitor;
  final _OpenAnalysis onOpenAnalysis;

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
        _ScanDiagnosticsCard(snapshot: snapshot),
        const SizedBox(height: 16),
        _RealtimeRadarPanel(
          realtimeMonitor: realtimeMonitor,
          journal: controller.signalJournal,
          onOpenAnalysis: onOpenAnalysis,
          fallback: opportunities.isEmpty
              ? _NoTradeCard(snapshot: snapshot)
              : Column(
                  children: [
                    for (
                      var index = 0;
                      index < opportunities.length;
                      index++
                    ) ...[
                      _OpportunityCard(
                        idea: opportunities[index],
                        taken: controller.isTaken(opportunities[index].setupId),
                        onTakenChanged: (value) => controller.setTaken(
                          opportunities[index].setupId,
                          value,
                        ),
                        onTap: () => onOpenAnalysis(
                          opportunities[index].symbol,
                          opportunities[index].timeframe,
                          opportunities[index].setupId,
                        ),
                      ),
                      if (index != opportunities.length - 1)
                        const SizedBox(height: 12),
                    ],
                  ],
                ),
        ),
        const SizedBox(height: 16),
        _RadarCoverage(snapshot: snapshot),
        const SizedBox(height: 16),
        const _AlphaSafetyCard(),
      ],
    );
  }
}

class _RealtimeRadarPanel extends StatefulWidget {
  const _RealtimeRadarPanel({
    required this.realtimeMonitor,
    required this.journal,
    required this.onOpenAnalysis,
    required this.fallback,
  });

  final ValueListenable<RealtimeMarketMonitorSnapshot>? realtimeMonitor;
  final List<SignalJournalEntry> journal;
  final _OpenAnalysis onOpenAnalysis;
  final Widget fallback;

  @override
  State<_RealtimeRadarPanel> createState() => _RealtimeRadarPanelState();
}

class _RealtimeRadarPanelState extends State<_RealtimeRadarPanel> {
  RealtimeMarketMonitorSnapshot _snapshot =
      const RealtimeMarketMonitorSnapshot.initial();

  @override
  void initState() {
    super.initState();
    _attach(widget.realtimeMonitor);
  }

  @override
  void didUpdateWidget(covariant _RealtimeRadarPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.realtimeMonitor != widget.realtimeMonitor) {
      oldWidget.realtimeMonitor?.removeListener(_handleUpdate);
      _attach(widget.realtimeMonitor);
    }
  }

  void _attach(ValueListenable<RealtimeMarketMonitorSnapshot>? monitor) {
    _snapshot = monitor?.value ?? const RealtimeMarketMonitorSnapshot.initial();
    monitor?.addListener(_handleUpdate);
  }

  void _handleUpdate() {
    final next = widget.realtimeMonitor?.value;
    if (next == null ||
        (next.candidateRevision == _snapshot.candidateRevision &&
            next.operational == _snapshot.operational)) {
      return;
    }
    setState(() => _snapshot = next);
  }

  @override
  void dispose() {
    widget.realtimeMonitor?.removeListener(_handleUpdate);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_snapshot.candidates.isEmpty) return widget.fallback;
    final items = RealtimeRadarProjection.build(
      candidates: _snapshot.candidates,
      journal: widget.journal,
      nowUtc: DateTime.now().toUtc(),
      realtimeOperational: _snapshot.operational,
    );
    final persian = Localizations.localeOf(context).languageCode != 'en';
    const laneOrder = [
      RealtimeRadarLane.managing,
      RealtimeRadarLane.triggered,
      RealtimeRadarLane.armed,
      RealtimeRadarLane.forming,
      RealtimeRadarLane.missed,
    ];
    final grouped = <RealtimeRadarLane, List<RealtimeRadarItemPresentation>>{
      for (final lane in laneOrder)
        lane: items.where((item) => item.lane == lane).toList(growable: false),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionCard(
          semanticLabel: persian
              ? 'مراحل رادار بلادرنگ'
              : 'Realtime Radar lifecycle',
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final lane in laneOrder)
                StatusPill(
                  label:
                      '${_radarLaneLabel(lane, persian: persian)} · ${grouped[lane]!.length}',
                  color: _radarLaneColor(lane),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        for (final lane in laneOrder)
          if (grouped[lane]!.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 4, bottom: 8),
              child: Text(
                _radarLaneLabel(lane, persian: persian),
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
              ),
            ),
            for (final item in grouped[lane]!.take(4)) ...[
              _RealtimeOpportunityCard(
                item: item,
                onOpenAnalysis: () => widget.onOpenAnalysis(
                  item.candidate.symbol,
                  item.candidate.timeframe,
                  item.candidate.setupId,
                ),
              ),
              const SizedBox(height: 10),
            ],
          ],
      ],
    );
  }
}

class _RealtimeOpportunityCard extends StatelessWidget {
  const _RealtimeOpportunityCard({
    required this.item,
    required this.onOpenAnalysis,
  });

  final RealtimeRadarItemPresentation item;
  final VoidCallback onOpenAnalysis;

  @override
  Widget build(BuildContext context) {
    final persian = Localizations.localeOf(context).languageCode != 'en';
    final candidate = item.candidate;
    final color = item.dataUncertain
        ? QuantaraColors.danger
        : _radarLaneColor(item.lane);
    final direction = candidate.direction == TradeDirection.long
        ? (persian ? 'خرید' : 'Long')
        : (persian ? 'فروش' : 'Short');
    final semantics = [
      candidate.symbol,
      item.laneLabel(persian: persian),
      item.conciseReason(persian: persian),
      item.safeNextAction(persian: persian),
    ].join('. ');
    return SectionCard(
      semanticLabel: semantics,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final identity = Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    candidate.direction == TradeDirection.long
                        ? Icons.trending_up_rounded
                        : Icons.trending_down_rounded,
                    color: color,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          candidate.symbol,
                          textDirection: TextDirection.ltr,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        Text(
                          '$direction · ${candidate.timeframe} · ${candidate.playbookId}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              );
              final stage = StatusPill(
                label: item.dataUncertain
                    ? (persian ? 'داده نامطمئن' : 'Data uncertain')
                    : item.laneLabel(persian: persian),
                color: color,
              );
              if (constraints.maxWidth < 440) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [identity, const SizedBox(height: 8), stage],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: identity),
                  const SizedBox(width: 8),
                  stage,
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          Text(item.conciseReason(persian: persian)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 18,
            runSpacing: 10,
            children: [
              MetricTile(
                label: persian ? 'کیفیت ستاپ' : 'Setup quality',
                value: '${candidate.qualityScore}/100',
              ),
              MetricTile(
                label: persian ? 'فاصله تا ورود' : 'Distance to entry',
                value: item.distanceLabel(persian: persian),
              ),
              MetricTile(
                label: persian ? 'تازگی' : 'Freshness',
                value: item.ageLabel(persian: persian),
              ),
              MetricTile(
                label: persian ? 'فوریت' : 'Urgency',
                value: item.urgencyLabel(persian: persian),
              ),
              if (item.regime != null)
                MetricTile(
                  label: persian ? 'رژیم بازار' : 'Market regime',
                  value: _marketRegimeLabel(item.regime!, persian: persian),
                ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final action = Text(
                item.safeNextAction(persian: persian),
                style: TextStyle(color: color, fontWeight: FontWeight.w800),
              );
              final button = FilledButton.tonalIcon(
                onPressed: onOpenAnalysis,
                icon: const Icon(Icons.candlestick_chart_rounded),
                label: Text(persian ? 'دیدن تحلیل' : 'View analysis'),
              );
              if (constraints.maxWidth < 440) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [action, const SizedBox(height: 10), button],
                );
              }
              return Row(
                children: [
                  Expanded(child: action),
                  const SizedBox(width: 12),
                  button,
                ],
              );
            },
          ),
          const Divider(height: 24),
          Text(
            '${persian ? 'کد علت' : 'Reason code'}: ${item.rawReasonCode}',
            textDirection: TextDirection.ltr,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

String _radarLaneLabel(RealtimeRadarLane lane, {required bool persian}) =>
    switch (lane) {
      RealtimeRadarLane.forming => persian ? 'در حال شکل‌گیری' : 'Forming',
      RealtimeRadarLane.armed => persian ? 'آماده' : 'Armed',
      RealtimeRadarLane.triggered => persian ? 'تریگر شده' : 'Triggered',
      RealtimeRadarLane.managing => persian ? 'در حال مدیریت' : 'Managing',
      RealtimeRadarLane.missed => persian ? 'از دست‌رفته' : 'Missed',
    };

Color _radarLaneColor(RealtimeRadarLane lane) => switch (lane) {
  RealtimeRadarLane.forming => QuantaraColors.cyan,
  RealtimeRadarLane.armed => QuantaraColors.warning,
  RealtimeRadarLane.triggered => QuantaraColors.success,
  RealtimeRadarLane.managing => QuantaraColors.electricBlue,
  RealtimeRadarLane.missed => QuantaraColors.danger,
};

String _marketRegimeLabel(MarketRegime regime, {required bool persian}) =>
    switch (regime) {
      MarketRegime.directionalTrend => persian ? 'روند جهت‌دار' : 'Trend',
      MarketRegime.range => persian ? 'رنج' : 'Range',
      MarketRegime.breakoutExpansion =>
        persian ? 'گسترش شکست' : 'Breakout expansion',
      MarketRegime.transition => persian ? 'گذار' : 'Transition',
      MarketRegime.disorder => persian ? 'بی‌نظمی' : 'Disorder',
    };

class _ScanDiagnosticsCard extends StatelessWidget {
  const _ScanDiagnosticsCard({required this.snapshot});

  final OwnerAlphaSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final diagnostics = snapshot.diagnostics;
    final rejectionEntries = diagnostics.rejections.entries
        .where((entry) => entry.value > 0)
        .toList(growable: false);
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            strings.scanReport,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          Text(
            strings.scanCoverage(
              diagnostics.completedAnalyses,
              diagnostics.requestedAnalyses,
            ),
          ),
          Text(strings.scanElapsed(diagnostics.elapsed.inMilliseconds)),
          Text(
            strings.scanEfficiency(
              diagnostics.cacheHits,
              diagnostics.networkRequests,
            ),
          ),
          if (rejectionEntries.isNotEmpty) ...[
            const Divider(height: 24),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final entry in rejectionEntries)
                  StatusPill(
                    label: strings.rejectionReason(entry.key.name, entry.value),
                    color: entry.key == SetupRejectionReason.dataUnavailable
                        ? QuantaraColors.danger
                        : QuantaraColors.warning,
                  ),
              ],
            ),
          ],
        ],
      ),
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
                  value: QuantaraNumberFormat.marketValue(idea.targets[index]),
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
          LayoutBuilder(
            builder: (context, constraints) {
              final takenControl = InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => onTakenChanged(!taken),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Checkbox(
                        value: taken,
                        onChanged: (value) => onTakenChanged(value ?? false),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(strings.taken),
                            Text(
                              strings.markTaken,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
              final chartButton = FilledButton.tonalIcon(
                onPressed: onTap,
                icon: const Icon(Icons.candlestick_chart_rounded),
                label: Text(strings.inspectChart),
              );
              if (constraints.maxWidth < 520) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    takenControl,
                    const SizedBox(height: 8),
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: chartButton,
                    ),
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: takenControl),
                  const SizedBox(width: 8),
                  chartButton,
                ],
              );
            },
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
