part of 'owner_alpha_page.dart';

class _TradingLabView extends StatefulWidget {
  const _TradingLabView({
    required this.controller,
    required this.marketController,
  });

  final TradingLabController controller;
  final OwnerAlphaController marketController;

  @override
  State<_TradingLabView> createState() => _TradingLabViewState();
}

class _TradingLabViewState extends State<_TradingLabView> {
  final _equity = TextEditingController(text: '500');
  final _risk = TextEditingController(text: '1');
  final _leverage = TextEditingController(text: '5');
  final _fee = TextEditingController(text: '6');
  final _slippage = TextEditingController(text: '2');
  final _notes = TextEditingController();
  int _slots = 3;
  bool _busy = false;
  String? _formError;

  bool get _fa => Directionality.of(context) == TextDirection.rtl;

  @override
  void dispose() {
    _equity.dispose();
    _risk.dispose();
    _leverage.dispose();
    _fee.dispose();
    _slippage.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final equity = double.tryParse(_equity.text.trim());
    final risk = double.tryParse(_risk.text.trim());
    final leverage = int.tryParse(_leverage.text.trim());
    final fee = double.tryParse(_fee.text.trim());
    final slippage = double.tryParse(_slippage.text.trim());
    if (equity == null ||
        risk == null ||
        leverage == null ||
        fee == null ||
        slippage == null) {
      setState(
        () => _formError = _fa
            ? 'مقادیر عددی معتبر وارد کن.'
            : 'Enter valid numeric values.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _formError = null;
    });
    try {
      await widget.controller.startExperiment(
        startingEquity: equity,
        riskPercent: risk,
        maximumConcurrentPositions: _slots,
        leverage: leverage,
        feeRateBps: fee,
        slippageBps: slippage,
        notes: _notes.text.trim(),
      );
    } on Object catch (error) {
      if (mounted) setState(() => _formError = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stop() async {
    setState(() => _busy = true);
    try {
      await widget.controller.stopExperiment();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _shareReview() async {
    try {
      final json = widget.controller.exportAiReviewJson();
      final bytes = Uint8List.fromList(utf8.encode(json));
      await SharePlus.instance.share(
        ShareParams(
          title: 'Quantara Bot Trading Lab',
          text: _fa
              ? 'بسته بررسی آزمایش بات Quantara — بدون کلید API و اطلاعات محرمانه.'
              : 'Quantara Bot Trading Lab AI review bundle — no API credentials included.',
          files: [XFile.fromData(bytes, mimeType: 'application/json')],
          fileNameOverrides: [widget.controller.suggestedExportFileName()],
        ),
      );
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _fa ? 'خروجی ساخته نشد: $error' : 'Export failed: $error',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final run = widget.controller.run;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _TradingLabHero(
              run: run,
              processing: widget.controller.isProcessing,
            ),
            if (widget.controller.error != null) ...[
              const SizedBox(height: 12),
              SectionCard(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      color: QuantaraColors.warning,
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Text(widget.controller.error!)),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            if (run == null || !run.isRunning) _buildNewExperiment(run),
            if (run != null) ...[
              if (!run.isRunning) const SizedBox(height: 16),
              _TradingLabSummary(run: run),
              const SizedBox(height: 16),
              _TradingLabWhyNoTrade(run: run),
              const SizedBox(height: 16),
              _TradingLabPositions(run: run),
              const SizedBox(height: 16),
              _TradingLabDecisionStream(run: run),
              const SizedBox(height: 16),
              _buildActions(run),
            ],
            if (widget.controller.history.isNotEmpty) ...[
              const SizedBox(height: 16),
              _TradingLabHistory(runs: widget.controller.history),
            ],
          ],
        );
      },
    );
  }

  Widget _buildNewExperiment(TradingLabRun? previous) {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _fa ? 'آزمایش جدید' : 'New experiment',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text(
            _fa
                ? 'سرمایه مجازی را مشخص کن. بازار و Strategy واقعی Quantara خوانده می‌شود، اما این بخش هیچ مسیر ارسال سفارش واقعی ندارد.'
                : 'Choose virtual capital. Quantara reads the real market/strategy pipeline, but this surface has no real-order execution path.',
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final itemWidth = width < 680 ? width : (width - 24) / 3;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  SizedBox(
                    width: itemWidth,
                    child: _labNumberField(
                      _equity,
                      _fa ? 'سرمایه مجازی (USDT)' : 'Virtual equity (USDT)',
                    ),
                  ),
                  SizedBox(
                    width: itemWidth,
                    child: _labNumberField(
                      _risk,
                      _fa ? 'ریسک هر معامله (%)' : 'Risk per trade (%)',
                    ),
                  ),
                  SizedBox(
                    width: itemWidth,
                    child: _labNumberField(
                      _leverage,
                      _fa ? 'اهرم حداکثر' : 'Maximum leverage',
                    ),
                  ),
                  SizedBox(
                    width: itemWidth,
                    child: _labNumberField(
                      _fee,
                      _fa ? 'کارمزد (bps)' : 'Fee (bps)',
                    ),
                  ),
                  SizedBox(
                    width: itemWidth,
                    child: _labNumberField(
                      _slippage,
                      _fa ? 'اسلیپیج (bps)' : 'Slippage (bps)',
                    ),
                  ),
                  SizedBox(
                    width: itemWidth,
                    child: DropdownButtonFormField<int>(
                      initialValue: _slots,
                      decoration: InputDecoration(
                        labelText: _fa
                            ? 'پوزیشن همزمان'
                            : 'Concurrent positions',
                      ),
                      items: const [1, 2, 3]
                          .map(
                            (value) => DropdownMenuItem(
                              value: value,
                              child: Text('$value'),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: _busy
                          ? null
                          : (value) => setState(() => _slots = value ?? _slots),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notes,
            minLines: 1,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: _fa
                  ? 'یادداشت آزمایش (اختیاری)'
                  : 'Experiment notes (optional)',
            ),
          ),
          if (_formError != null) ...[
            const SizedBox(height: 10),
            Text(
              _formError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy ? null : _start,
            icon: const Icon(Icons.science_rounded),
            label: Text(
              _fa
                  ? 'شروع آزمایش با بازار واقعی'
                  : 'Start real-market experiment',
            ),
          ),
        ],
      ),
    );
  }

  TextField _labNumberField(TextEditingController controller, String label) =>
      TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textDirection: TextDirection.ltr,
        decoration: InputDecoration(labelText: label),
      );

  Widget _buildActions(TradingLabRun run) {
    return SectionCard(
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        alignment: WrapAlignment.end,
        children: [
          OutlinedButton.icon(
            onPressed: _busy ? null : () => widget.marketController.refresh(),
            icon: const Icon(Icons.refresh_rounded),
            label: Text(_fa ? 'اسکن بازار' : 'Scan market'),
          ),
          FilledButton.tonalIcon(
            onPressed: _shareReview,
            icon: const Icon(Icons.ios_share_rounded),
            label: Text(_fa ? 'خروجی برای بررسی AI' : 'Export AI review'),
          ),
          if (run.isRunning)
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: QuantaraColors.danger,
              ),
              onPressed: _busy ? null : _stop,
              icon: const Icon(Icons.stop_circle_outlined),
              label: Text(_fa ? 'توقف آزمایش' : 'Stop experiment'),
            ),
        ],
      ),
    );
  }
}

class _TradingLabHero extends StatelessWidget {
  const _TradingLabHero({required this.run, required this.processing});

  final TradingLabRun? run;
  final bool processing;

  @override
  Widget build(BuildContext context) {
    final fa = Directionality.of(context) == TextDirection.rtl;
    final status = run == null
        ? (fa ? 'آماده آزمایش' : 'Ready')
        : run!.isRunning
        ? (processing
              ? (fa ? 'در حال پردازش بازار' : 'Processing market')
              : (fa ? 'آزمایش فعال' : 'Experiment live'))
        : (fa ? 'آزمایش متوقف' : 'Experiment stopped');
    final color = run?.isRunning == true
        ? QuantaraColors.success
        : QuantaraColors.cyan;
    return SectionCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(Icons.science_rounded, color: color, size: 30),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Bot Trading Lab',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  fa
                      ? 'فوروارد تست با دیتای واقعی بازار؛ سرمایه و سفارش‌ها کاملاً مجازی هستند.'
                      : 'Forward testing on real market data; capital and orders are fully virtual.',
                ),
                const SizedBox(height: 10),
                StatusPill(
                  label: status,
                  color: color,
                  icon: run?.isRunning == true
                      ? Icons.sensors_rounded
                      : Icons.shield_outlined,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TradingLabSummary extends StatelessWidget {
  const _TradingLabSummary({required this.run});
  final TradingLabRun run;

  @override
  Widget build(BuildContext context) {
    final fa = Directionality.of(context) == TextDirection.rtl;
    final pf = run.profitFactor;
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            fa ? 'نتیجه لحظه‌ای' : 'Live results',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 28,
            runSpacing: 18,
            children: [
              MetricTile(
                label: fa ? 'سرمایه شروع' : 'Starting equity',
                value: '${run.manifest.startingEquity.toStringAsFixed(2)} USDT',
              ),
              MetricTile(
                label: fa ? 'اکوییتی' : 'Equity',
                value: '${run.currentEquity.toStringAsFixed(2)} USDT',
                valueColor: run.returnPercent >= 0
                    ? QuantaraColors.success
                    : QuantaraColors.danger,
              ),
              MetricTile(
                label: fa ? 'بازده' : 'Return',
                value:
                    '${run.returnPercent >= 0 ? '+' : ''}${run.returnPercent.toStringAsFixed(2)}%',
                valueColor: run.returnPercent >= 0
                    ? QuantaraColors.success
                    : QuantaraColors.danger,
              ),
              MetricTile(
                label: fa ? 'بیشترین افت' : 'Max drawdown',
                value: '${run.maximumDrawdownPercent.toStringAsFixed(2)}%',
                valueColor: QuantaraColors.warning,
              ),
              MetricTile(
                label: fa ? 'معاملات بسته' : 'Closed trades',
                value: '${run.tradeCount}',
              ),
              MetricTile(
                label: fa ? 'برد' : 'Win rate',
                value: '${run.winRatePercent.toStringAsFixed(1)}%',
              ),
              MetricTile(
                label: fa ? 'میانگین R' : 'Average R',
                value: run.averageR.toStringAsFixed(2),
              ),
              MetricTile(
                label: 'Profit Factor',
                value: pf == null
                    ? '—'
                    : (pf.isFinite ? pf.toStringAsFixed(2) : '∞'),
              ),
              MetricTile(
                label: fa ? 'پوزیشن باز' : 'Open positions',
                value:
                    '${run.openPositions.length}/${run.manifest.maximumConcurrentPositions}',
              ),
              MetricTile(
                label: fa ? 'کاندید منتظر' : 'Pending candidates',
                value: '${run.pendingCandidates.length}',
              ),
              MetricTile(
                label: fa ? 'تصمیم‌های ثبت‌شده' : 'Recorded decisions',
                value: '${run.processedDecisionKeys.length}',
              ),
            ],
          ),
          if (run.tradeCount < 30) ...[
            const SizedBox(height: 14),
            Text(
              fa
                  ? 'نمونه هنوز کوچک است؛ این نتیجه برای برنده اعلام کردن Strategy کافی نیست.'
                  : 'Sample is still small; do not promote a strategy from this run alone.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: QuantaraColors.warning,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TradingLabWhyNoTrade extends StatelessWidget {
  const _TradingLabWhyNoTrade({required this.run});
  final TradingLabRun run;

  @override
  Widget build(BuildContext context) {
    final fa = Directionality.of(context) == TextDirection.rtl;
    return SectionCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.psychology_alt_rounded,
            color: QuantaraColors.violet,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fa ? 'چرا معامله جدید نداریم؟' : 'Why no new trade?',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(run.lastWhyNoTrade),
                const SizedBox(height: 6),
                Text(
                  fa
                      ? 'Scanner حتی با پوزیشن باز متوقف نمی‌شود؛ هر چرخه در Decision Stream ثبت می‌شود.'
                      : 'The scanner keeps recording while positions are open; every cycle is written to the Decision Stream.',
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

class _TradingLabPositions extends StatelessWidget {
  const _TradingLabPositions({required this.run});
  final TradingLabRun run;

  @override
  Widget build(BuildContext context) {
    final fa = Directionality.of(context) == TextDirection.rtl;
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            fa ? 'پوزیشن‌های Paper' : 'Paper positions',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 12),
          if (run.openPositions.isEmpty)
            Text(
              fa
                  ? 'فعلاً پوزیشن Paper بازی وجود ندارد.'
                  : 'No paper position is currently open.',
            )
          else
            for (final position in run.openPositions) ...[
              _TradingLabPositionTile(position: position),
              const SizedBox(height: 10),
            ],
          if (run.closedPositions.isNotEmpty) ...[
            const Divider(height: 26),
            Text(
              fa ? 'آخرین معاملات بسته' : 'Recent closed trades',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            for (final position in run.closedPositions.reversed.take(5))
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(
                  '${position.symbol} · ${position.timeframe}',
                  textDirection: TextDirection.ltr,
                ),
                subtitle: Text(position.closeReason ?? 'closed'),
                trailing: Text(
                  '${position.netRealizedPnl >= 0 ? '+' : ''}${position.netRealizedPnl.toStringAsFixed(2)} USDT · ${position.realizedR.toStringAsFixed(2)}R',
                  textDirection: TextDirection.ltr,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: position.netRealizedPnl >= 0
                        ? QuantaraColors.success
                        : QuantaraColors.danger,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _TradingLabPositionTile extends StatelessWidget {
  const _TradingLabPositionTile({required this.position});
  final TradingLabPosition position;

  @override
  Widget build(BuildContext context) {
    final fa = Directionality.of(context) == TextDirection.rtl;
    final long = position.direction == TradeDirection.long;
    final color = long ? QuantaraColors.success : QuantaraColors.danger;
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${position.symbol} · ${position.timeframe}',
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              StatusPill(label: long ? 'LONG' : 'SHORT', color: color),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 20,
            runSpacing: 10,
            children: [
              MetricTile(
                label: fa ? 'ورود' : 'Entry',
                value: QuantaraNumberFormat.marketValue(position.entryPrice),
              ),
              MetricTile(
                label: 'SL',
                value: QuantaraNumberFormat.marketValue(
                  position.currentStopLoss,
                ),
                valueColor: QuantaraColors.danger,
              ),
              MetricTile(
                label: fa ? 'حجم باقی' : 'Remaining qty',
                value: position.remainingQuantity.toStringAsFixed(6),
              ),
              MetricTile(
                label: fa ? 'ریسک اولیه' : 'Initial risk',
                value: '${position.initialRisk.toStringAsFixed(2)} USDT',
              ),
              MetricTile(
                label: fa ? 'اهرم' : 'Leverage',
                value: '${position.leverage}x',
              ),
              MetricTile(
                label: fa ? 'Strategy' : 'Strategy',
                value: '${position.strategy}@${position.strategyVersion}',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TradingLabDecisionStream extends StatelessWidget {
  const _TradingLabDecisionStream({required this.run});
  final TradingLabRun run;

  @override
  Widget build(BuildContext context) {
    final fa = Directionality.of(context) == TextDirection.rtl;
    final events = run.events.reversed.take(14).toList(growable: false);
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Decision Stream',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text(
            fa
                ? 'Black Box آزمایش؛ آخرین تصمیم‌های Scanner، Risk و Paper Broker.'
                : 'Experiment black box: latest scanner, risk and paper-broker decisions.',
          ),
          const SizedBox(height: 12),
          if (events.isEmpty)
            Text(fa ? 'هنوز رویدادی ثبت نشده.' : 'No event recorded yet.')
          else
            for (final event in events)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: Icon(
                  _labEventIcon(event.kind),
                  size: 20,
                  color: _labEventColor(event.kind),
                ),
                title: Text(
                  event.reason,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  [
                    event.symbol,
                    event.timeframe,
                    event.strategyVersion,
                  ].whereType<String>().join(' · '),
                  textDirection: TextDirection.ltr,
                ),
                trailing: Text(
                  '#${event.cycleId}',
                  textDirection: TextDirection.ltr,
                ),
              ),
        ],
      ),
    );
  }
}

class _TradingLabHistory extends StatelessWidget {
  const _TradingLabHistory({required this.runs});
  final List<TradingLabRun> runs;

  @override
  Widget build(BuildContext context) {
    final fa = Directionality.of(context) == TextDirection.rtl;
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            fa ? 'تاریخچه آزمایش‌ها' : 'Experiment history',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          for (final run in runs.take(6))
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(
                '${run.manifest.startingEquity.toStringAsFixed(0)} USDT · ${run.tradeCount} ${fa ? 'معامله' : 'trades'}',
              ),
              subtitle: Text(
                run.manifest.runId,
                textDirection: TextDirection.ltr,
              ),
              trailing: Text(
                '${run.returnPercent >= 0 ? '+' : ''}${run.returnPercent.toStringAsFixed(2)}%',
                textDirection: TextDirection.ltr,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: run.returnPercent >= 0
                      ? QuantaraColors.success
                      : QuantaraColors.danger,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

IconData _labEventIcon(TradingLabEventKind kind) => switch (kind) {
  TradingLabEventKind.positionOpened => Icons.play_circle_outline_rounded,
  TradingLabEventKind.positionClosed => Icons.check_circle_outline_rounded,
  TradingLabEventKind.targetFilled => Icons.flag_outlined,
  TradingLabEventKind.stopFilled => Icons.gpp_bad_outlined,
  TradingLabEventKind.stopPromoted => Icons.lock_outline_rounded,
  TradingLabEventKind.candidateRejected => Icons.block_rounded,
  TradingLabEventKind.candidatePending => Icons.hourglass_top_rounded,
  TradingLabEventKind.anomaly => Icons.warning_amber_rounded,
  _ => Icons.radar_rounded,
};

Color _labEventColor(TradingLabEventKind kind) => switch (kind) {
  TradingLabEventKind.positionOpened ||
  TradingLabEventKind.targetFilled ||
  TradingLabEventKind.positionClosed => QuantaraColors.success,
  TradingLabEventKind.stopFilled ||
  TradingLabEventKind.anomaly => QuantaraColors.danger,
  TradingLabEventKind.candidateRejected => QuantaraColors.warning,
  _ => QuantaraColors.cyan,
};
