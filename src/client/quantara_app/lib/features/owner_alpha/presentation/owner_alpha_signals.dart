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
    final filtered = all.where((entry) {
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
    }).toList(growable: false);

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
                        : _t('در این دسته چیزی نیست', 'Nothing in this category'),
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
              onOpen: () => widget.onOpenAnalysis(filtered[index].symbol),
              onTakenChanged: (value) =>
                  controller.setTaken(filtered[index].setupId, value),
              onNote: () => _editNote(filtered[index]),
              onClose: (value) =>
                  controller.closeSignal(filtered[index].setupId, value),
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
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
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
        AnalysisStrategy.structureZones =>
          _t(context, 'ناحیه و ساختار', 'Structure & zones'),
        AnalysisStrategy.trendPullback =>
          _t(context, 'پولبک در روند', 'Trend pullback'),
        AnalysisStrategy.momentumContinuation =>
          _t(context, 'ادامه مومنتوم', 'Momentum continuation'),
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
  });

  final SignalJournalEntry entry;
  final bool taken;
  final VoidCallback onOpen;
  final ValueChanged<bool> onTakenChanged;
  final VoidCallback onNote;
  final ValueChanged<bool> onClose;

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
              ],
            ),
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

  String _strategy(BuildContext context) => switch (entry.strategy) {
    AnalysisStrategy.structureZones =>
      _t(context, 'ناحیه و ساختار', 'Structure & zones'),
    AnalysisStrategy.trendPullback =>
      _t(context, 'پولبک روند', 'Trend pullback'),
    AnalysisStrategy.momentumContinuation =>
      _t(context, 'ادامه مومنتوم', 'Momentum continuation'),
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
