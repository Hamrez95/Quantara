part of 'owner_alpha_page.dart';

enum _SignalFilter { all, live, taken, expired }

class _SignalInboxView extends StatefulWidget {
  const _SignalInboxView({
    required this.controller,
    required this.onOpenAnalysis,
  });

  final OwnerAlphaController controller;
  final ValueChanged<String> onOpenAnalysis;

  @override
  State<_SignalInboxView> createState() => _SignalInboxViewState();
}

class _SignalInboxViewState extends State<_SignalInboxView> {
  _SignalFilter _filter = _SignalFilter.all;

  bool get _fa => Directionality.of(context) == TextDirection.rtl;
  String _t(String fa, String en) => _fa ? fa : en;

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final now = DateTime.now().toUtc();
    final all = controller.signalJournal;
    final priorityBySetupId = SignalTimeframePriorityResolver.resolve(
      all,
      now: now,
    );
    final filtered = all
        .where((entry) {
          final lifecycle = entry.lifecycle(
            now,
            taken: controller.isTaken(entry.setupId),
          );
          return switch (_filter) {
            _SignalFilter.all => true,
            _SignalFilter.live =>
              lifecycle == SignalLifecycle.fresh ||
                  lifecycle == SignalLifecycle.expiring,
            _SignalFilter.taken => lifecycle == SignalLifecycle.taken,
            _SignalFilter.expired =>
              lifecycle == SignalLifecycle.expired ||
                  lifecycle == SignalLifecycle.closed,
          };
        })
        .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SignalPolicyCard(controller: controller),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _t('صندوق پیشنهادها', 'Signal inbox'),
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _t(
                      'هر پیشنهاد با زمان اعتبار، دلیل و سابقه‌اش اینجا می‌ماند.',
                      'Every idea keeps its validity, rationale and history here.',
                    ),
                  ),
                ],
              ),
            ),
            StatusPill(
              label: _t('${all.length} مورد', '${all.length} items'),
              color: Theme.of(context).colorScheme.primary,
            ),
          ],
        ),
        const SizedBox(height: 14),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SegmentedButton<_SignalFilter>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                value: _SignalFilter.all,
                label: Text(_t('همه', 'All')),
              ),
              ButtonSegment(
                value: _SignalFilter.live,
                icon: const Icon(Icons.bolt_rounded),
                label: Text(_t('معتبر', 'Live')),
              ),
              ButtonSegment(
                value: _SignalFilter.taken,
                icon: const Icon(Icons.bookmark_rounded),
                label: Text(_t('گرفته‌شده', 'Taken')),
              ),
              ButtonSegment(
                value: _SignalFilter.expired,
                label: Text(_t('بایگانی', 'Archive')),
              ),
            ],
            selected: {_filter},
            onSelectionChanged: (value) =>
                setState(() => _filter = value.single),
          ),
        ),
        const SizedBox(height: 16),
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
              priority: priorityBySetupId[filtered[index].setupId],
              taken: controller.isTaken(filtered[index].setupId),
              onOpen: () => widget.onOpenAnalysis(filtered[index].symbol),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: QuantaraColors.violet.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const SizedBox.square(
                  dimension: 46,
                  child: Icon(Icons.tune_rounded, color: QuantaraColors.violet),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _t(context, 'روش پیدا کردن پیشنهاد', 'Signal policy'),
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<AnalysisStrategy>(
            initialValue: controller.strategy,
            decoration: InputDecoration(
              labelText: _t(context, 'استراتژی', 'Strategy'),
              helperText: _t(
                context,
                'انتخابت روی اسکن بعدی و پیشنهادهای فعلی اعمال می‌شود.',
                'Your choice applies to current ideas and the next scan.',
              ),
            ),
            items: [
              for (final strategy in AnalysisStrategy.values)
                DropdownMenuItem(
                  value: strategy,
                  child: Text(_strategyLabel(context, strategy)),
                ),
            ],
            onChanged: (strategy) {
              if (strategy != null) {
                controller.updateSignalPolicy(
                  strategy: strategy,
                  cadence: controller.cadence,
                );
              }
            },
          ),
          const SizedBox(height: 14),
          Text(
            _t(context, 'تعداد فرصت‌ها', 'Opportunity cadence'),
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 8),
          SegmentedButton<SignalCadence>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                value: SignalCadence.conservative,
                label: Text(_t(context, 'دقیق', 'Selective')),
              ),
              ButtonSegment(
                value: SignalCadence.balanced,
                label: Text(_t(context, 'متعادل', 'Balanced')),
              ),
              ButtonSegment(
                value: SignalCadence.active,
                label: Text(_t(context, 'فعال', 'Active')),
              ),
            ],
            selected: {controller.cadence},
            onSelectionChanged: (value) => controller.updateSignalPolicy(
              strategy: controller.strategy,
              cadence: value.single,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _t(
              context,
              'حالت فعال فقط حساسیت روند را بیشتر می‌کند؛ حداقل نسبت سود به زیان و کنترل ریسک حذف نمی‌شوند.',
              'Active mode increases trend sensitivity; reward/risk and safety gates remain enforced.',
            ),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  String _strategyLabel(BuildContext context, AnalysisStrategy strategy) =>
      switch (strategy) {
        AnalysisStrategy.structureZones => _t(
          context,
          'ناحیه و ساختار',
          'Structure & zones',
        ),
        AnalysisStrategy.trendPullback => _t(
          context,
          'پولبک در روند',
          'Trend pullback',
        ),
        AnalysisStrategy.momentumContinuation => _t(
          context,
          'ادامه مومنتوم',
          'Momentum continuation',
        ),
      };
}

class _SignalJournalCard extends StatelessWidget {
  const _SignalJournalCard({
    required this.entry,
    required this.priority,
    required this.taken,
    required this.onOpen,
    required this.onTakenChanged,
    required this.onNote,
    required this.onClose,
    required this.onLeverageChanged,
  });

  final SignalJournalEntry entry;
  final SignalTimeframePriorityKind? priority;
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
    final now = DateTime.now().toUtc();
    final lifecycle = entry.lifecycle(now, taken: taken);
    final color = switch (lifecycle) {
      SignalLifecycle.fresh => QuantaraColors.success,
      SignalLifecycle.expiring => QuantaraColors.warning,
      SignalLifecycle.expired => Theme.of(context).colorScheme.outline,
      SignalLifecycle.taken => QuantaraColors.cyan,
      SignalLifecycle.closed => Theme.of(context).colorScheme.secondary,
    };
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 180),
      opacity: lifecycle == SignalLifecycle.expired ? 0.72 : 1,
      child: SectionCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: SizedBox.square(
                    dimension: 48,
                    child: Icon(
                      entry.direction == TradeDirection.long
                          ? Icons.north_east_rounded
                          : Icons.south_east_rounded,
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
                        '${entry.symbol} · ${entry.timeframe}',
                        textDirection: TextDirection.ltr,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text('${_direction(context)} · ${_strategy(context)}'),
                    ],
                  ),
                ),
                StatusPill(label: _lifecycle(context, lifecycle), color: color),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                StatusPill(
                  label: _outcomeLabel(context),
                  color: _outcomeColor(context),
                  icon: _outcomeIcon,
                ),
                StatusPill(
                  label: _t(
                    context,
                    '${entry.selectedLeverage}x انتخابی',
                    '${entry.selectedLeverage}x selected',
                  ),
                  color: QuantaraColors.violet,
                ),
                if (priority == SignalTimeframePriorityKind.primary)
                  StatusPill(
                    label: _t(context, 'گزینه اصلی', 'Primary setup'),
                    color: QuantaraColors.cyan,
                    icon: Icons.stars_rounded,
                  ),
                if (priority == SignalTimeframePriorityKind.conflict)
                  StatusPill(
                    label: _t(context, 'تعارض تایم‌فریم', 'Timeframe conflict'),
                    color: QuantaraColors.danger,
                    icon: Icons.sync_problem_rounded,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            _TimeLine(
              icon: Icons.schedule_rounded,
              label: _t(context, 'ساخته شد', 'Created'),
              value: _formatTime(context, entry.createdAt),
            ),
            const SizedBox(height: 6),
            _TimeLine(
              icon: Icons.timer_outlined,
              label: _t(context, 'معتبر تا', 'Valid until'),
              value: _formatTime(context, entry.validUntil),
              color: color,
            ),
            const SizedBox(height: 14),
            Text(entry.summary),
            if (priority == SignalTimeframePriorityKind.primary) ...[
              const SizedBox(height: 8),
              Text(
                _t(
                  context,
                  'برای این نماد، این تایم‌فریم گزینه اجرای اصلی است؛ تایم بالاتر جهت و تایم پایین‌تر فقط ماشه ورود است.',
                  'This is the primary execution timeframe for the symbol; higher timeframes define bias and lower timeframes only refine the trigger.',
                ),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: QuantaraColors.cyan,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            if (priority == SignalTimeframePriorityKind.conflict) ...[
              const SizedBox(height: 8),
              Text(
                _t(
                  context,
                  'جهت ستاپ‌های این نماد بین تایم‌فریم‌ها متناقض است؛ هم‌زمان هر دو جهت را نگیر و تا هم‌جهتی صبر کن.',
                  'This symbol has conflicting setup directions across timeframes. Do not take both directions; wait for alignment.',
                ),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: QuantaraColors.danger,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 18,
              runSpacing: 10,
              children: [
                if (entry.entryLower != null && entry.entryUpper != null)
                  MetricTile(
                    label: _t(context, 'محدوده ورود', 'Entry'),
                    value:
                        '${QuantaraNumberFormat.marketValue(entry.entryLower!)} – ${QuantaraNumberFormat.marketValue(entry.entryUpper!)}',
                  ),
                if (entry.stopLoss != null)
                  MetricTile(
                    label: _t(context, 'خروج اضطراری', 'Stop'),
                    value: QuantaraNumberFormat.marketValue(entry.stopLoss!),
                    valueColor: QuantaraColors.danger,
                  ),
                for (var index = 0; index < entry.targets.length; index++)
                  MetricTile(
                    label: 'TP${index + 1}',
                    value: QuantaraNumberFormat.marketValue(
                      entry.targets[index],
                    ),
                    valueColor: QuantaraColors.success,
                  ),
                MetricTile(
                  label: _t(context, 'ارزش پوزیشن', 'Position notional'),
                  value: QuantaraNumberFormat.marketValue(
                    entry.notionalValue,
                    unit: 'USDT',
                  ),
                ),
                MetricTile(
                  label: _t(context, 'مارجین لازم', 'Required margin'),
                  value: QuantaraNumberFormat.marketValue(
                    entry.selectedMargin,
                    unit: 'USDT',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _LeverageControl(
              selected: entry.selectedLeverage,
              recommended: entry.recommendedLeverage,
              safeCap: entry.maximumSafeLeverage,
              onChanged: onLeverageChanged,
            ),
            if (entry.outcome != SignalOutcome.pendingEntry ||
                !DateTime.now().toUtc().isBefore(entry.validUntil)) ...[
              const SizedBox(height: 14),
              _SignalPerformancePanel(entry: entry),
            ],
            const SizedBox(height: 12),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 8),
              title: Text(
                _t(context, 'چرا این پیشنهاد ساخته شد؟', 'Why this idea?'),
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
      ),
    );
  }

  String _direction(BuildContext context) =>
      entry.direction == TradeDirection.long
      ? _t(context, 'خرید', 'Long')
      : _t(context, 'فروش', 'Short');

  String _outcomeLabel(BuildContext context) => switch (entry.outcome) {
    SignalOutcome.pendingEntry => _t(
      context,
      'منتظر فعال‌شدن ورود',
      'Waiting for entry',
    ),
    SignalOutcome.active => _t(context, 'ورود فعال شد', 'Entry activated'),
    SignalOutcome.expiredUntriggered => _t(
      context,
      'ورود فعال نشد',
      'Entry not triggered',
    ),
    SignalOutcome.stopped =>
      entry.highestTargetHit > 0
          ? _t(
              context,
              'TP${entry.highestTargetHit} سپس SL',
              'TP${entry.highestTargetHit}, then SL',
            )
          : 'SL',
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

  String _strategy(BuildContext context) => switch (entry.strategy) {
    AnalysisStrategy.structureZones => _t(
      context,
      'ناحیه و ساختار',
      'Structure & zones',
    ),
    AnalysisStrategy.trendPullback => _t(
      context,
      'پولبک روند',
      'Trend pullback',
    ),
    AnalysisStrategy.momentumContinuation => _t(
      context,
      'ادامه مومنتوم',
      'Momentum continuation',
    ),
  };

  String _lifecycle(BuildContext context, SignalLifecycle value) =>
      switch (value) {
        SignalLifecycle.fresh => _t(context, 'تازه', 'Fresh'),
        SignalLifecycle.expiring => _t(context, 'رو به انقضا', 'Expiring'),
        SignalLifecycle.expired => _t(context, 'منقضی', 'Expired'),
        SignalLifecycle.taken => _t(context, 'گرفته‌شده', 'Taken'),
        SignalLifecycle.closed => _t(context, 'بسته‌شده', 'Closed'),
      };

  String _formatTime(BuildContext context, DateTime time) {
    final local = time.toLocal();
    final minute = local.minute.toString().padLeft(2, '0');
    return _fa(context)
        ? '${local.year}/${local.month}/${local.day}، ${local.hour}:$minute'
        : '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} ${local.hour}:$minute';
  }
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
    return DecoratedBox(
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
              _t(context, 'نتیجه شبیه‌سازی', 'Simulated outcome'),
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            if (pnl == null)
              Text(
                _t(
                  context,
                  'هنوز نتیجه قیمتی قطعی نشده؛ اسکن‌های بعدی خودکار ادامه می‌دهند.',
                  'No price outcome yet; future scans keep tracking it automatically.',
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
                'این گزارش مستقل از دکمه «گرفتم» و با ورود محافظه‌کارانه محاسبه می‌شود. اگر بعد از TP حد ضرر بخورد، خروج پله‌ای مساوی لحاظ می‌شود؛ کارمزد و لغزش فرضی هم کسر شده‌اند.',
                'This report runs even when “Taken” is off and uses a conservative fill. If price stops after a TP, equal scale-outs are modeled; estimated fees and slippage are deducted.',
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _TimeLine extends StatelessWidget {
  const _TimeLine({
    required this.icon,
    required this.label,
    required this.value,
    this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final effective = color ?? Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      children: [
        Icon(icon, size: 18, color: effective),
        const SizedBox(width: 7),
        Text('$label: ', style: Theme.of(context).textTheme.bodySmall),
        Expanded(
          child: Text(
            value,
            textDirection: TextDirection.ltr,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: effective,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}

class _LeverageControl extends StatefulWidget {
  const _LeverageControl({
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

  @override
  Widget build(BuildContext context) {
    final selected = _draft.round().clamp(1, TradeIdea.maximumManualLeverage);
    final presets =
        <int>{
              1,
              2,
              3,
              5,
              10,
              20,
              50,
              100,
              widget.recommended,
              widget.safeCap,
              selected,
            }
            .where(
              (value) => value >= 1 && value <= TradeIdea.maximumManualLeverage,
            )
            .toList(growable: false)
          ..sort();
    final aboveSafe = selected > widget.safeCap;
    final scheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.38),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: aboveSafe
              ? QuantaraColors.warning.withValues(alpha: 0.65)
              : scheme.outlineVariant,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _persian ? 'اهرم انتخابی' : 'Selected leverage',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                StatusPill(
                  label: '${selected}x',
                  color: aboveSafe
                      ? QuantaraColors.warning
                      : QuantaraColors.cyan,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              _persian
                  ? 'پیشنهاد ${widget.recommended}x · مرز محافظه‌کارانه ${widget.safeCap}x · انتخاب دستی تا ${TradeIdea.maximumManualLeverage}x'
                  : 'Suggested ${widget.recommended}x · conservative boundary ${widget.safeCap}x · manual selection up to ${TradeIdea.maximumManualLeverage}x',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final leverage in presets) ...[
                    ChoiceChip(
                      showCheckmark: false,
                      selected: leverage == selected,
                      label: Text('${leverage}x'),
                      onSelected: (_) {
                        setState(() => _draft = leverage.toDouble());
                        widget.onChanged(leverage);
                      },
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Text('1x', textDirection: TextDirection.ltr),
                Expanded(
                  child: Slider(
                    value: selected.toDouble(),
                    min: 1,
                    max: TradeIdea.maximumManualLeverage.toDouble(),
                    divisions: TradeIdea.maximumManualLeverage - 1,
                    label: '${selected}x',
                    onChanged: (value) => setState(() => _draft = value),
                    onChangeEnd: (value) => widget.onChanged(value.round()),
                  ),
                ),
                Text(
                  '${TradeIdea.maximumManualLeverage}x',
                  textDirection: TextDirection.ltr,
                ),
              ],
            ),
            if (aboveSafe) ...[
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    size: 20,
                    color: QuantaraColors.warning,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _persian
                          ? 'بالاتر از مرز امن مدل انتخاب شده است. اندازه پوزیشن و زیان برنامه‌ریزی‌شده ثابت می‌ماند، اما مارجین کمتر و فاصله تا لیکویید کوتاه‌تر می‌شود.'
                          : 'This is above the model safe boundary. Position notional and planned stop loss stay fixed, but margin is lower and liquidation distance becomes tighter.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: QuantaraColors.warning,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
