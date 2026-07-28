part of 'owner_alpha_page.dart';

class _StrategyLabView extends StatefulWidget {
  const _StrategyLabView({required this.controller, required this.snapshot});

  final OwnerAlphaController controller;
  final OwnerAlphaSnapshot snapshot;

  @override
  State<_StrategyLabView> createState() => _StrategyLabViewState();
}

class _StrategyLabViewState extends State<_StrategyLabView> {
  final StrategyLabSessionStore _sessionStore =
      const PlatformStrategyLabSessionStore();
  StrategyKind _strategy = StrategyKind.structureZones;
  static const _fullHistoryDays = 3650;
  int _forwardDays = 3;
  late String _symbol = widget.snapshot.selectedSymbol;
  late String _timeframe = widget.snapshot.selectedTimeframe;
  StrategyLabReport? _report;
  StrategyLabSession? _session;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_loadSession());
  }

  Future<void> _loadSession() async {
    final session = await _sessionStore.load();
    if (mounted) {
      setState(() => _session = session);
    }
  }

  List<String> get _availableTimeframes {
    final radar = widget.snapshot.radar.firstWhere(
      (item) => item.quote.symbol == _symbol,
    );
    final allowed = StrategyDefinition.forKind(_strategy).allowedTimeframes;
    return radar.analysesByTimeframe.keys
        .where(allowed.contains)
        .toList(growable: false);
  }

  void _run({StrategyLabSession? session}) {
    try {
      final strategy = session?.config.strategy ?? _strategy;
      final symbol = session?.config.symbol ?? _symbol;
      final timeframe = session?.config.timeframe ?? _timeframe;
      final definition = StrategyDefinition.forKind(strategy);
      final radar = widget.snapshot.radar.firstWhere(
        (item) => item.quote.symbol == symbol,
      );
      final analysis = radar.analysesByTimeframe[timeframe];
      if (analysis == null ||
          !definition.allowedTimeframes.contains(timeframe)) {
        throw StateError('Selected history is unavailable.');
      }
      final candles = session == null
          ? analysis.candles
          : analysis.candles
                .where((candle) => candle.openTime.isBefore(session.endsAt))
                .toList(growable: false);
      final report = StrategyLabRunner.run(
        config:
            session?.config ??
            StrategyLabConfig(
              strategy: strategy,
              symbol: analysis.symbol,
              timeframe: analysis.timeframe,
              window: const Duration(days: _fullHistoryDays),
              initialCapital: widget.controller.capital,
              riskPercent: math.min(widget.controller.riskPercent, 1),
            ),
        candles: candles,
      );
      setState(() {
        _report = report;
        _error = null;
      });
    } on Object {
      setState(() {
        _report = null;
        _error = AppStrings.of(context).strategyLabDataError;
      });
    }
  }

  Future<void> _startForwardTest() async {
    final maximumDays = switch (_timeframe) {
      '15m' => 1,
      '1h' => 3,
      _ => 7,
    };
    if (_forwardDays > maximumDays) {
      setState(() => _error = AppStrings.of(context).forwardWindowTooLong);
      return;
    }
    final startedAt = DateTime.now().toUtc();
    final session = StrategyLabSession(
      config: StrategyLabConfig(
        strategy: _strategy,
        symbol: _symbol,
        timeframe: _timeframe,
        window: Duration(days: _forwardDays),
        initialCapital: widget.controller.capital,
        riskPercent: math.min(widget.controller.riskPercent, 1),
      ),
      startedAt: startedAt,
      endsAt: startedAt.add(Duration(days: _forwardDays)),
    );
    await _sessionStore.save(session);
    if (mounted) {
      setState(() {
        _session = session;
        _report = null;
        _error = null;
      });
    }
  }

  Future<void> _clearForwardTest() async {
    await _sessionStore.save(null);
    if (mounted) {
      setState(() {
        _session = null;
        _report = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final definition = StrategyDefinition.forKind(_strategy);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.science_rounded,
                    color: QuantaraColors.violet,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      strings.strategyLab,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  StatusPill(
                    label: strings.paperResearch,
                    color: QuantaraColors.violet,
                    icon: Icons.shield_outlined,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(strings.strategyLabDescription),
              const SizedBox(height: 18),
              DropdownButtonFormField<StrategyKind>(
                initialValue: _strategy,
                isExpanded: true,
                decoration: InputDecoration(labelText: strings.strategy),
                items: [
                  for (final item in StrategyDefinition.all)
                    DropdownMenuItem(
                      value: item.kind,
                      child: Text(strings.strategyName(item.kind.name)),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _strategy = value;
                      final available = _availableTimeframes;
                      if (!available.contains(_timeframe) &&
                          available.isNotEmpty) {
                        _timeframe = available.first;
                      }
                      _report = null;
                    });
                  }
                },
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) {
                  final symbolField = DropdownButtonFormField<String>(
                    initialValue: _symbol,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: strings.symbol),
                    items: [
                      for (final radar in widget.snapshot.radar)
                        DropdownMenuItem(
                          value: radar.quote.symbol,
                          child: Text(radar.quote.symbol),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          _symbol = value;
                          final available = _availableTimeframes;
                          if (!available.contains(_timeframe) &&
                              available.isNotEmpty) {
                            _timeframe = available.first;
                          }
                          _report = null;
                        });
                      }
                    },
                  );
                  final timeframeField = DropdownButtonFormField<String>(
                    key: ValueKey('lab-timeframe-$_symbol-$_strategy'),
                    initialValue: _availableTimeframes.contains(_timeframe)
                        ? _timeframe
                        : null,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: strings.timeframe),
                    items: [
                      for (final timeframe in _availableTimeframes)
                        DropdownMenuItem(
                          value: timeframe,
                          child: Text(timeframe),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          _timeframe = value;
                          _report = null;
                        });
                      }
                    },
                  );
                  if (constraints.maxWidth < 620) {
                    return Column(
                      children: [
                        symbolField,
                        const SizedBox(height: 12),
                        timeframeField,
                      ],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: symbolField),
                      const SizedBox(width: 12),
                      Expanded(child: timeframeField),
                    ],
                  );
                },
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  StatusPill(
                    label: '${definition.id} v${definition.version}',
                    color: QuantaraColors.violet,
                    icon: Icons.tag_rounded,
                  ),
                  StatusPill(
                    label: strings.strategyMaturity(definition.maturity.name),
                    color:
                        definition.maturity ==
                            StrategyMaturity.validatedCandidate
                        ? QuantaraColors.success
                        : QuantaraColors.warning,
                    icon: Icons.biotech_outlined,
                  ),
                  StatusPill(
                    label: '$_symbol · $_timeframe',
                    color: Theme.of(context).colorScheme.primary,
                    icon: Icons.candlestick_chart_rounded,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                Directionality.of(context) == TextDirection.rtl
                    ? 'بک‌تست فوری با بیشترین تاریخچه'
                    : 'Instant backtest with maximum history',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 6),
              Text(
                Directionality.of(context) == TextDirection.rtl
                    ? 'همین حالا روی همه کندل‌های بسته موجود اجرا می‌شود؛ منتظر چند روز نمی‌مانی.'
                    : 'Runs now on every available closed candle; no multi-day wait.',
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _run,
                icon: const Icon(Icons.assessment_rounded),
                label: Text(
                  Directionality.of(context) == TextDirection.rtl
                      ? 'ساخت گزارش تاریخی'
                      : 'Build historical report',
                ),
              ),
              const Divider(height: 32),
              Text(
                Directionality.of(context) == TextDirection.rtl
                    ? 'فوروارد تست زنده'
                    : 'Live forward test',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 6),
              Text(
                Directionality.of(context) == TextDirection.rtl
                    ? 'از الان به بعد و بدون نگاه به آینده، عملکرد واقعی سیگنال‌ها را ثبت می‌کند.'
                    : 'Tracks real signals from now on without looking ahead.',
              ),
              const SizedBox(height: 10),
              SegmentedButton<int>(
                segments: [
                  ButtonSegment(value: 1, label: Text(strings.oneDay)),
                  ButtonSegment(value: 3, label: Text(strings.threeDays)),
                  ButtonSegment(value: 7, label: Text(strings.sevenDays)),
                ],
                selected: {_forwardDays},
                onSelectionChanged: (value) {
                  setState(() {
                    _forwardDays = value.first;
                    _report = null;
                  });
                },
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _session == null ? _startForwardTest : null,
                icon: const Icon(Icons.schedule_rounded),
                label: Text(strings.startForwardTest),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
        if (_session != null) ...[
          const SizedBox(height: 14),
          _ForwardSessionCard(
            session: _session!,
            onBuildReport: _session!.isCompleteAt(DateTime.now().toUtc())
                ? () => _run(session: _session)
                : null,
            onClear: _clearForwardTest,
          ),
        ],
        if (_report != null) ...[
          const SizedBox(height: 14),
          _StrategyLabReportCard(report: _report!),
        ],
      ],
    );
  }
}

class _ForwardSessionCard extends StatelessWidget {
  const _ForwardSessionCard({
    required this.session,
    required this.onBuildReport,
    required this.onClear,
  });

  final StrategyLabSession session;
  final VoidCallback? onBuildReport;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final remaining = session.endsAt.difference(DateTime.now().toUtc());
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.schedule_rounded, color: QuantaraColors.cyan),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  onBuildReport == null
                      ? strings.forwardTestRunning
                      : strings.forwardTestComplete,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${session.config.symbol} · ${session.config.timeframe} · '
            '${strings.strategyName(session.config.strategy.name)}',
          ),
          const SizedBox(height: 4),
          Text(
            onBuildReport == null
                ? strings.forwardRemaining(remaining)
                : strings.forwardReady,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (onBuildReport != null)
                FilledButton.icon(
                  onPressed: onBuildReport,
                  icon: const Icon(Icons.assessment_outlined),
                  label: Text(strings.buildForwardReport),
                ),
              TextButton(
                onPressed: onClear,
                child: Text(strings.clearForwardTest),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StrategyLabReportCard extends StatelessWidget {
  const _StrategyLabReportCard({required this.report});

  final StrategyLabReport report;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final positive = report.netPnl >= 0;
    final pnlColor = positive
        ? QuantaraColors.success
        : Theme.of(context).colorScheme.error;
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            strings.strategyLabReport,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          Text(
            strings.regimeName(report.regime.name),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 10),
          StatusPill(
            label: report.trades.length >= 20
                ? (Directionality.of(context) == TextDirection.rtl
                      ? 'نمونه قابل بررسی'
                      : 'Reviewable sample')
                : (Directionality.of(context) == TextDirection.rtl
                      ? 'نمونه کم؛ هنوز قابل اتکا نیست'
                      : 'Small sample; not reliable yet'),
            color: report.trades.length >= 20
                ? QuantaraColors.success
                : QuantaraColors.warning,
            icon: report.trades.length >= 20
                ? Icons.verified_outlined
                : Icons.warning_amber_rounded,
          ),
          const SizedBox(height: 8),
          Text(
            '${report.startedAt.toLocal()} → ${report.endedAt.toLocal()}',
            textDirection: TextDirection.ltr,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _LabMetric(
                label: strings.netPnl,
                value:
                    '${positive ? '+' : ''}${QuantaraNumberFormat.marketValue(report.netPnl, unit: 'USDT')} (${strings.decimal(report.netReturnPercent, decimals: 2)}%)',
                color: pnlColor,
              ),
              _LabMetric(
                label: strings.totalTrades,
                value: strings.integer(report.trades.length),
              ),
              _LabMetric(
                label: strings.winRate,
                value: '${strings.decimal(report.winRate, decimals: 1)}%',
              ),
              _LabMetric(
                label: strings.expectancy,
                value: QuantaraNumberFormat.marketValue(
                  report.expectancy,
                  unit: 'USDT',
                ),
              ),
              _LabMetric(
                label: strings.profitFactor,
                value: report.profitFactor == null
                    ? '∞'
                    : strings.decimal(report.profitFactor!, decimals: 2),
              ),
              _LabMetric(
                label: strings.maxDrawdown,
                value:
                    '${strings.decimal(report.maxDrawdownPercent, decimals: 2)}%',
              ),
              _LabMetric(label: 'SL', value: strings.integer(report.stopCount)),
              _LabMetric(
                label: 'TP1 / TP2 / TP3',
                value:
                    '${strings.integer(report.targetCount(1))} / ${strings.integer(report.targetCount(2))} / ${strings.integer(report.targetCount(3))}',
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            strings.validationWarnings,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          for (final warning in report.warnings)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.info_outline_rounded,
                    size: 17,
                    color: QuantaraColors.warning,
                  ),
                  const SizedBox(width: 7),
                  Expanded(child: Text(strings.labWarning(warning))),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _LabMetric extends StatelessWidget {
  const _LabMetric({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 170,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 5),
          Text(
            value,
            textDirection: TextDirection.ltr,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
