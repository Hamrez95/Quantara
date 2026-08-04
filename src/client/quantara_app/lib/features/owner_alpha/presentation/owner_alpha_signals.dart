part of 'owner_alpha_page.dart';

class _SignalInboxView extends StatefulWidget {
  const _SignalInboxView({
    required this.controller,
    required this.onOpenAnalysis,
  });

  final OwnerAlphaController controller;
  final _OpenAnalysis onOpenAnalysis;

  @override
  State<_SignalInboxView> createState() => _SignalInboxViewState();
}

class _SignalInboxViewState extends State<_SignalInboxView> {
  SignalInboxFilter _filter = SignalInboxFilter.all;
  SignalInboxSort _sort = SignalInboxSort.recommended;

  bool get _fa => Directionality.of(context) == TextDirection.rtl;
  String _t(String fa, String en) => _fa ? fa : en;

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final now = DateTime.now().toUtc();
    final all = controller.signalJournal;
    final filtered = SignalInboxQuery.apply(
      entries: all,
      filter: _filter,
      sort: _sort,
      now: now,
      isTaken: controller.isTaken,
    );

    int count(SignalInboxFilter filter) => SignalInboxQuery.count(
      entries: all,
      filter: filter,
      now: now,
      isTaken: controller.isTaken,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SignalPolicyCard(controller: controller),
        const SizedBox(height: 16),
        SectionCard(
          semanticLabel: _t('صندوق پیشنهادها', 'Signal inbox'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.inbox_rounded),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _t('صندوق پیشنهادها', 'Signal inbox'),
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _t(
                            'پیشنهادها و سرنوشت آن‌ها؛ بدون صفحه آزمایشگاه جداگانه.',
                            'Setups and their outcomes, without a separate lab screen.',
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final filter in SignalInboxFilter.values)
                    FilterChip(
                      selected: _filter == filter,
                      showCheckmark: false,
                      avatar: Icon(_filterIcon(filter), size: 18),
                      label: Text(
                        '${_filterLabel(filter)} ${count(filter)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onSelected: (_) => setState(() => _filter = filter),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 4),
                leading: const Icon(Icons.sort_rounded),
                title: Text(_t('مرتب‌سازی', 'Sort')),
                subtitle: Text(_sortLabel(_sort)),
                children: [
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final sort in SignalInboxSort.values)
                          ChoiceChip(
                            selected: _sort == sort,
                            showCheckmark: false,
                            label: Text(_sortLabel(sort)),
                            onSelected: (_) => setState(() => _sort = sort),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (filtered.isEmpty)
          SectionCard(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 28),
              child: Column(
                children: [
                  const Icon(Icons.inbox_outlined, size: 44),
                  const SizedBox(height: 12),
                  Text(
                    all.isEmpty
                        ? _t(
                            'هنوز پیشنهاد قابل‌اقدامی ثبت نشده',
                            'No actionable idea has been recorded yet',
                          )
                        : _t(
                            'در این دسته چیزی نیست',
                            'Nothing in this category',
                          ),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _t(
                      'اسکن ادامه دارد؛ کیفیت فدای تعداد پیشنهاد نمی‌شود.',
                      'Scanning continues without trading quality for quantity.',
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          )
        else
          for (var index = 0; index < filtered.length; index++) ...[
            _SignalJournalCard(
              entry: filtered[index],
              taken: controller.isTaken(filtered[index].setupId),
              onOpen: () => widget.onOpenAnalysis(
                filtered[index].symbol,
                filtered[index].timeframe,
                filtered[index].setupId,
              ),
              onTakenChanged: (value) =>
                  controller.setTaken(filtered[index].setupId, value),
              onNote: () => _editNote(filtered[index]),
              onClose: (value) =>
                  controller.closeSignal(filtered[index].setupId, value),
              onLeverageChanged: (value) =>
                  controller.setSignalLeverage(filtered[index].setupId, value),
            ),
            if (index != filtered.length - 1) const SizedBox(height: 12),
          ],
      ],
    );
  }

  String _filterLabel(SignalInboxFilter filter) => switch (filter) {
    SignalInboxFilter.all => _t('همه', 'All'),
    SignalInboxFilter.opportunities => _t('فرصت', 'Open'),
    SignalInboxFilter.active => _t('فعال', 'Active'),
    SignalInboxFilter.results => _t('نتیجه', 'Results'),
    SignalInboxFilter.expired => _t('منقضی', 'Expired'),
    SignalInboxFilter.taken => _t('گرفتم', 'Taken'),
  };

  IconData _filterIcon(SignalInboxFilter filter) => switch (filter) {
    SignalInboxFilter.all => Icons.apps_rounded,
    SignalInboxFilter.opportunities => Icons.bolt_rounded,
    SignalInboxFilter.active => Icons.play_circle_outline_rounded,
    SignalInboxFilter.results => Icons.query_stats_rounded,
    SignalInboxFilter.expired => Icons.timer_off_outlined,
    SignalInboxFilter.taken => Icons.bookmark_rounded,
  };

  String _sortLabel(SignalInboxSort value) => switch (value) {
    SignalInboxSort.recommended => _t('پیشنهادی', 'Recommended'),
    SignalInboxSort.score => _t('امتیاز', 'Score'),
    SignalInboxSort.expiringSoon => _t('انقضا', 'Expiry'),
    SignalInboxSort.newest => _t('جدیدترین', 'Newest'),
    SignalInboxSort.latestResult => _t('آخرین نتیجه', 'Latest result'),
  };

  Future<void> _editNote(SignalJournalEntry entry) async {
    final textController = TextEditingController(text: entry.note);
    final note = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_t('یادداشت معامله', 'Trade note')),
        content: TextField(
          controller: textController,
          autofocus: true,
          minLines: 3,
          maxLines: 7,
          maxLength: 2000,
          decoration: InputDecoration(
            hintText: _t(
              'چرا وارد شدی؟ چه چیزی دیدی؟ نتیجه چه شد؟',
              'Why did you enter? What did you observe? What happened?',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(_t('انصراف', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, textController.text),
            child: Text(_t('ذخیره', 'Save')),
          ),
        ],
      ),
    );
    textController.dispose();
    if (note != null) {
      await widget.controller.updateSignalNote(entry.setupId, note);
    }
  }
}

class _SignalPolicyCard extends StatelessWidget {
  const _SignalPolicyCard({required this.controller});

  final OwnerAlphaController controller;

  bool _fa(BuildContext context) =>
      Directionality.of(context) == TextDirection.rtl;
  String _t(BuildContext context, String fa, String en) =>
      _fa(context) ? fa : en;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      semanticLabel: _t(context, 'تنظیمات پیشنهادها', 'Setup preferences'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: QuantaraColors.violet.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.tune_rounded,
                  color: QuantaraColors.violet,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _t(context, 'روش پیدا کردن پیشنهاد', 'Setup preferences'),
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      _t(
                        context,
                        'انتخاب‌ها روی اسکن بعدی اعمال می‌شوند.',
                        'Choices apply to the next scan.',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            _t(context, 'استراتژی', 'Strategy'),
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final strategy in AnalysisStrategy.values)
                ChoiceChip(
                  selected: controller.strategy == strategy,
                  showCheckmark: false,
                  label: Text(_strategyLabel(context, strategy)),
                  onSelected: (_) => controller.updateSignalPolicy(
                    strategy: strategy,
                    cadence: controller.cadence,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            _t(context, 'تعداد فرصت‌ها', 'Opportunity cadence'),
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final cadence in SignalCadence.values)
                ChoiceChip(
                  selected: controller.cadence == cadence,
                  showCheckmark: false,
                  label: Text(_cadenceLabel(context, cadence)),
                  onSelected: (_) => controller.updateSignalPolicy(
                    strategy: controller.strategy,
                    cadence: cadence,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            _t(
              context,
              'حالت فعال فقط حساسیت را بیشتر می‌کند؛ حداقل نسبت سود به زیان و کنترل ریسک حذف نمی‌شوند.',
              'Active mode increases sensitivity; reward/risk and safety gates remain enforced.',
            ),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  String _strategyLabel(BuildContext context, AnalysisStrategy value) =>
      switch (value) {
        AnalysisStrategy.structureZones => _t(context, 'ساختار', 'Structure'),
        AnalysisStrategy.trendPullback => _t(context, 'پولبک', 'Pullback'),
        AnalysisStrategy.momentumContinuation => _t(
          context,
          'مومنتوم',
          'Momentum',
        ),
      };

  String _cadenceLabel(BuildContext context, SignalCadence value) =>
      switch (value) {
        SignalCadence.conservative => _t(context, 'دقیق', 'Selective'),
        SignalCadence.balanced => _t(context, 'متعادل', 'Balanced'),
        SignalCadence.active => _t(context, 'فعال', 'Active'),
      };
}

class _SignalJournalCard extends StatelessWidget {
  const _SignalJournalCard({
    required this.entry,
    required this.taken,
    required this.onOpen,
    required this.onTakenChanged,
    required this.onNote,
    required this.onClose,
    required this.onLeverageChanged,
  });

  final SignalJournalEntry entry;
  final bool taken;
  final VoidCallback onOpen;
  final ValueChanged<bool> onTakenChanged;
  final VoidCallback onNote;
  final ValueChanged<bool> onClose;
  final ValueChanged<int> onLeverageChanged;

  bool _fa(BuildContext context) =>
      Directionality.of(context) == TextDirection.rtl;
  String _t(BuildContext context, String fa, String en) =>
      _fa(context) ? fa : en;

  @override
  Widget build(BuildContext context) {
    final lifecycle = entry.lifecycle(DateTime.now().toUtc(), taken: taken);
    final color = _lifecycleColor(context, lifecycle);
    return SectionCard(
      accentColor: color,
      semanticLabel: '${entry.symbol} ${entry.timeframe}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SymbolAvatar(symbol: entry.symbol, size: 48),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${entry.symbol} · ${entry.timeframe}',
                      textDirection: TextDirection.ltr,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text('${_direction(context)} · ${_strategy(context)}'),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              StatusPill(
                label: _lifecycleLabel(context, lifecycle),
                color: color,
              ),
              StatusPill(
                label: _outcomeLabel(context),
                color: _outcomeColor(context),
                icon: _outcomeIcon,
              ),
              if (entry.confidencePercent > 0)
                StatusPill(
                  label: _t(
                    context,
                    'امتیاز ${entry.confidencePercent}',
                    'Score ${entry.confidencePercent}',
                  ),
                  color: QuantaraColors.cyan,
                ),
              if (entry.riskReward != null)
                StatusPill(
                  label: 'R:R ${entry.riskReward!.toStringAsFixed(2)}',
                  color: QuantaraColors.success,
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(entry.summary),
          const SizedBox(height: 12),
          Wrap(
            spacing: 18,
            runSpacing: 10,
            children: [
              if (entry.entryLower != null && entry.entryUpper != null)
                MetricTile(
                  label: _t(context, 'ورود', 'Entry'),
                  value:
                      '${QuantaraNumberFormat.marketValue(entry.entryLower!)} – ${QuantaraNumberFormat.marketValue(entry.entryUpper!)}',
                ),
              if (entry.stopLoss != null)
                MetricTile(
                  label: _t(context, 'حد ضرر', 'Stop'),
                  value: QuantaraNumberFormat.marketValue(entry.stopLoss!),
                  valueColor: QuantaraColors.danger,
                ),
              for (var index = 0; index < entry.targets.length; index++)
                MetricTile(
                  label: 'TP${index + 1}',
                  value: QuantaraNumberFormat.marketValue(entry.targets[index]),
                  valueColor: QuantaraColors.success,
                ),
              MetricTile(
                label: _t(context, 'ریسک', 'Risk'),
                value: QuantaraNumberFormat.marketValue(
                  entry.maximumLoss,
                  unit: 'USDT',
                ),
                valueColor: QuantaraColors.warning,
              ),
              MetricTile(
                label: _t(context, 'مارجین', 'Margin'),
                value: QuantaraNumberFormat.marketValue(
                  entry.selectedMargin,
                  unit: 'USDT',
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _t(
              context,
              'سرمایه مبنای محاسبه و بودجه ریسک با هر تغییر اهرم دوباره محاسبه می‌شوند.',
              'Calculation capital and risk budget are recalculated after every leverage change.',
            ),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 14),
          _LeverageControl(
            key: ValueKey('leverage-${entry.setupId}'),
            selected: entry.selectedLeverage,
            recommended: entry.recommendedLeverage,
            safeCap: entry.maximumSafeLeverage,
            onChanged: onLeverageChanged,
          ),
          const SizedBox(height: 14),
          _SignalPerformancePanel(entry: entry),
          const SizedBox(height: 12),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: 8),
            title: Text(
              _t(context, 'چرا این پیشنهاد ساخته شد؟', 'Why this setup?'),
            ),
            children: [
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(entry.invalidation),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  '${_t(context, 'نسخه استراتژی', 'Strategy version')}: ${entry.strategyVersion}',
                  textDirection: TextDirection.ltr,
                ),
              ),
            ],
          ),
          if (entry.note.isNotEmpty) ...[
            const Divider(height: 24),
            Text(
              _t(context, 'یادداشت من', 'My note'),
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 4),
            Text(entry.note),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: onOpen,
                icon: const Icon(Icons.candlestick_chart_rounded),
                label: Text(_t(context, 'دیدن چارت', 'Open chart')),
              ),
              OutlinedButton.icon(
                onPressed: onNote,
                icon: const Icon(Icons.edit_note_rounded),
                label: Text(_t(context, 'یادداشت', 'Note')),
              ),
              FilterChip(
                selected: taken,
                onSelected: onTakenChanged,
                avatar: const Icon(Icons.bookmark_outline_rounded),
                label: Text(_t(context, 'گرفتم', 'Taken')),
              ),
              FilterChip(
                selected: entry.closed,
                onSelected: onClose,
                avatar: const Icon(Icons.archive_outlined),
                label: Text(_t(context, 'بسته شد', 'Closed')),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Color _lifecycleColor(BuildContext context, SignalLifecycle value) =>
      switch (value) {
        SignalLifecycle.fresh => QuantaraColors.success,
        SignalLifecycle.expiring => QuantaraColors.warning,
        SignalLifecycle.expired => Theme.of(context).colorScheme.outline,
        SignalLifecycle.taken => QuantaraColors.cyan,
        SignalLifecycle.closed => Theme.of(context).colorScheme.secondary,
      };

  String _lifecycleLabel(BuildContext context, SignalLifecycle value) =>
      switch (value) {
        SignalLifecycle.fresh => _t(context, 'تازه', 'Fresh'),
        SignalLifecycle.expiring => _t(context, 'رو به انقضا', 'Expiring'),
        SignalLifecycle.expired => _t(context, 'منقضی', 'Expired'),
        SignalLifecycle.taken => _t(context, 'گرفته‌شده', 'Taken'),
        SignalLifecycle.closed => _t(context, 'بسته‌شده', 'Closed'),
      };

  String _direction(BuildContext context) =>
      entry.direction == TradeDirection.long
      ? _t(context, 'خرید', 'Long')
      : _t(context, 'فروش', 'Short');

  String _strategy(BuildContext context) => switch (entry.strategy) {
    AnalysisStrategy.structureZones => _t(context, 'ساختار', 'Structure'),
    AnalysisStrategy.trendPullback => _t(context, 'پولبک', 'Pullback'),
    AnalysisStrategy.momentumContinuation => _t(context, 'مومنتوم', 'Momentum'),
  };

  String _outcomeLabel(BuildContext context) => switch (entry.outcome) {
    SignalOutcome.pendingEntry => _t(context, 'منتظر ورود', 'Waiting'),
    SignalOutcome.active => _t(context, 'فعال', 'Active'),
    SignalOutcome.expiredUntriggered => _t(
      context,
      'فعال نشد',
      'Not triggered',
    ),
    SignalOutcome.stopped =>
      entry.highestTargetHit > 0 ? 'TP${entry.highestTargetHit} → SL' : 'SL',
    SignalOutcome.tp1 => 'TP1',
    SignalOutcome.tp2 => 'TP2',
    SignalOutcome.tp3 => 'TP3',
  };

  Color _outcomeColor(BuildContext context) => switch (entry.outcome) {
    SignalOutcome.pendingEntry => Theme.of(
      context,
    ).colorScheme.onSurfaceVariant,
    SignalOutcome.active => QuantaraColors.cyan,
    SignalOutcome.expiredUntriggered => Theme.of(context).colorScheme.outline,
    SignalOutcome.stopped => QuantaraColors.danger,
    SignalOutcome.tp1 ||
    SignalOutcome.tp2 ||
    SignalOutcome.tp3 => QuantaraColors.success,
  };

  IconData get _outcomeIcon => switch (entry.outcome) {
    SignalOutcome.pendingEntry => Icons.hourglass_top_rounded,
    SignalOutcome.active => Icons.play_circle_outline_rounded,
    SignalOutcome.expiredUntriggered => Icons.timer_off_outlined,
    SignalOutcome.stopped => Icons.cancel_outlined,
    SignalOutcome.tp1 ||
    SignalOutcome.tp2 ||
    SignalOutcome.tp3 => Icons.check_circle_outline_rounded,
  };
}

class _SignalPerformancePanel extends StatelessWidget {
  const _SignalPerformancePanel({required this.entry});

  final SignalJournalEntry entry;

  bool _fa(BuildContext context) =>
      Directionality.of(context) == TextDirection.rtl;
  String _t(BuildContext context, String fa, String en) =>
      _fa(context) ? fa : en;

  @override
  Widget build(BuildContext context) {
    final pnl = entry.simulatedPnl;
    final positive = (pnl ?? 0) >= 0;
    final color = pnl == null
        ? Theme.of(context).colorScheme.onSurfaceVariant
        : positive
        ? QuantaraColors.success
        : QuantaraColors.danger;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _t(context, 'نتیجه پیشنهاد', 'Setup outcome'),
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          if (pnl == null)
            Text(
              _t(
                context,
                'هنوز نتیجه قطعی نشده؛ اسکن‌های بعدی آن را ادامه می‌دهند.',
                'No final outcome yet; later scans keep tracking it.',
              ),
            )
          else
            Wrap(
              spacing: 18,
              runSpacing: 10,
              children: [
                MetricTile(
                  label: _t(context, 'سود/زیان', 'P/L'),
                  value:
                      '${pnl >= 0 ? '+' : ''}${QuantaraNumberFormat.marketValue(pnl, unit: 'USDT')}',
                  valueColor: color,
                ),
                MetricTile(
                  label: _t(context, 'حرکت قیمت', 'Price move'),
                  value:
                      '${(entry.priceChangePercent ?? 0) >= 0 ? '+' : ''}${(entry.priceChangePercent ?? 0).toStringAsFixed(2)}%',
                  valueColor: color,
                ),
                MetricTile(
                  label: _t(context, 'بازده مارجین', 'Margin return'),
                  value:
                      '${(entry.marginReturnPercent ?? 0) >= 0 ? '+' : ''}${(entry.marginReturnPercent ?? 0).toStringAsFixed(2)}%',
                  valueColor: color,
                ),
              ],
            ),
          const SizedBox(height: 8),
          Text(
            _t(
              context,
              'این نتیجه مستقل از دکمه «گرفتم» و با ورود محافظه‌کارانه، کارمزد و لغزش محاسبه می‌شود.',
              'This result is tracked even when “Taken” is off and includes conservative entry, fees and slippage.',
            ),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _LeverageControl extends StatefulWidget {
  const _LeverageControl({
    super.key,
    required this.selected,
    required this.recommended,
    required this.safeCap,
    required this.onChanged,
  });

  final int selected;
  final int recommended;
  final int safeCap;
  final ValueChanged<int> onChanged;

  @override
  State<_LeverageControl> createState() => _LeverageControlState();
}

class _LeverageControlState extends State<_LeverageControl> {
  late double _draft = widget.selected.toDouble();

  @override
  void didUpdateWidget(covariant _LeverageControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selected != widget.selected) {
      _draft = widget.selected.toDouble();
    }
  }

  bool get _persian => Directionality.of(context) == TextDirection.rtl;

  void _commit(int value) {
    final normalized = value.clamp(1, TradeIdea.maximumManualLeverage).toInt();
    setState(() => _draft = normalized.toDouble());
    widget.onChanged(normalized);
  }

  @override
  Widget build(BuildContext context) {
    final selected = _draft.round().clamp(1, TradeIdea.maximumManualLeverage);
    final presets = <int>{
      1,
      2,
      3,
      5,
      10,
      widget.recommended,
      widget.safeCap,
      selected,
    }.where((value) => value >= 1).toList(growable: false)..sort();
    final aboveSafe = selected > widget.safeCap;
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.38),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: aboveSafe
              ? QuantaraColors.warning.withValues(alpha: 0.65)
              : scheme.outlineVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _persian ? 'اهرم انتخابی' : 'Selected leverage',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
              StatusPill(
                label: '${selected}x',
                color: aboveSafe ? QuantaraColors.warning : QuantaraColors.cyan,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final leverage in presets)
                ChoiceChip(
                  selected: leverage == selected,
                  showCheckmark: false,
                  label: Text('${leverage}x'),
                  onSelected: (_) => _commit(leverage),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              IconButton.filledTonal(
                key: ValueKey('leverage-decrease-$selected'),
                tooltip: _persian ? 'یک واحد کمتر' : 'Decrease by one',
                onPressed: selected > 1 ? () => _commit(selected - 1) : null,
                icon: const Icon(Icons.remove_rounded),
              ),
              Expanded(
                child: Text(
                  _persian
                      ? 'پیشنهاد ${widget.recommended}x · مرز امن ${widget.safeCap}x'
                      : 'Suggested ${widget.recommended}x · safe boundary ${widget.safeCap}x',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              IconButton.filledTonal(
                key: ValueKey('leverage-increase-$selected'),
                tooltip: _persian ? 'یک واحد بیشتر' : 'Increase by one',
                onPressed: selected < TradeIdea.maximumManualLeverage
                    ? () => _commit(selected + 1)
                    : null,
                icon: const Icon(Icons.add_rounded),
              ),
            ],
          ),
          if (aboveSafe) ...[
            const SizedBox(height: 6),
            Text(
              _persian
                  ? 'اهرم از مرز محافظه‌کارانه بالاتر است؛ فاصله لیکویید کمتر می‌شود.'
                  : 'Leverage is above the conservative boundary; liquidation distance becomes tighter.',
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
