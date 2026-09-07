import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../trading_journal/domain/trading_journal_projection.dart';
import '../domain/owner_alpha_models.dart';
import '../domain/setup_performance_reporting.dart';

class SetupPerformanceReportSheet extends StatefulWidget {
  const SetupPerformanceReportSheet({
    required this.signals,
    required this.projections,
    required this.isJournalLoading,
    required this.journalError,
    required this.onOpenSetup,
    this.now,
    super.key,
  });

  final List<SignalJournalEntry> signals;
  final List<TradingJournalProjection> projections;
  final bool isJournalLoading;
  final String? journalError;
  final ValueChanged<SignalJournalEntry> onOpenSetup;
  final DateTime? now;

  @override
  State<SetupPerformanceReportSheet> createState() =>
      _SetupPerformanceReportSheetState();
}

class _SetupPerformanceReportSheetState
    extends State<SetupPerformanceReportSheet> {
  SetupPerformanceFilter _filter = const SetupPerformanceFilter();

  bool get _fa => Directionality.of(context) == TextDirection.rtl;
  String _t(String fa, String en) => _fa ? fa : en;

  @override
  Widget build(BuildContext context) {
    final now = widget.now ?? DateTime.now();
    final report = SetupPerformanceReport.build(
      signals: widget.signals,
      projections: widget.projections,
      filter: _filter,
      now: now,
    );
    final strategies = widget.signals.map((e) => e.strategy).toSet().toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    final symbols =
        widget.signals
            .map((e) => e.symbol.trim().toUpperCase())
            .where((e) => e.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    final timeframes =
        widget.signals
            .map((e) => e.timeframe.trim())
            .where((e) => e.isNotEmpty)
            .toSet()
            .toList()
          ..sort();

    return SafeArea(
      child: ListView(
        key: const Key('setup-performance-report'),
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 32),
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _t('گزارش عملکرد ستاپ‌ها', 'Setup performance'),
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _t(
                        'نتیجهٔ تحلیلی با سود و زیان واقعی صرافی مخلوط نمی‌شود.',
                        'Analytical outcomes are kept separate from real exchange PnL.',
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: _t('بستن', 'Close'),
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _InfoBanner(
            icon: Icons.science_outlined,
            text: _t(
              'تحلیلی / شبیه‌سازی‌شده: بازپخش قیمت نسبت به Entry، SL و TPها پس از هزینهٔ تعریف‌شده. این سود واقعی نیست.',
              'Analytical / simulated: candle replay against Entry, SL and TPs after defined costs. This is not real profit.',
            ),
          ),
          const SizedBox(height: 8),
          _InfoBanner(
            icon: Icons.verified_user_outlined,
            text: _t(
              'واقعی: فقط PnL بسته‌شده‌ای که از reconciliation صرافی و evidence تأییدشده آمده است.',
              'Real: only closed PnL backed by reconciled, confirmed exchange evidence.',
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _t('بازه', 'Range'),
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final value in SetupPerformanceRange.values)
                FilterChip(
                  key: Key('performance-range-${value.name}'),
                  selected: _filter.range == value,
                  showCheckmark: false,
                  label: Text(_rangeLabel(value)),
                  onSelected: (_) => _selectRange(value),
                ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth >= 720
                  ? (constraints.maxWidth - 16) / 3
                  : constraints.maxWidth;
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  SizedBox(
                    width: width,
                    child: _StringFilter(
                      key: const Key('performance-strategy-filter'),
                      label: _t('استراتژی', 'Strategy'),
                      value: _filter.strategy?.name ?? '',
                      allLabel: _t('همه', 'All'),
                      values: strategies.map((e) => e.name).toList(),
                      onChanged: (value) {
                        setState(() {
                          _filter = value.isEmpty
                              ? _filter.copyWith(clearStrategy: true)
                              : _filter.copyWith(
                                  strategy: AnalysisStrategy.values.firstWhere(
                                    (item) => item.name == value,
                                  ),
                                );
                        });
                      },
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: _StringFilter(
                      key: const Key('performance-symbol-filter'),
                      label: _t('نماد', 'Symbol'),
                      value: _filter.symbol ?? '',
                      allLabel: _t('همه', 'All'),
                      values: symbols,
                      onChanged: (value) {
                        setState(() {
                          _filter = value.isEmpty
                              ? _filter.copyWith(clearSymbol: true)
                              : _filter.copyWith(symbol: value);
                        });
                      },
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: _StringFilter(
                      key: const Key('performance-timeframe-filter'),
                      label: _t('تایم‌فریم', 'Timeframe'),
                      value: _filter.timeframe ?? '',
                      allLabel: _t('همه', 'All'),
                      values: timeframes,
                      onChanged: (value) {
                        setState(() {
                          _filter = value.isEmpty
                              ? _filter.copyWith(clearTimeframe: true)
                              : _filter.copyWith(timeframe: value);
                        });
                      },
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 18),
          if (widget.isJournalLoading && widget.projections.isEmpty)
            const Center(
              key: Key('setup-performance-loading'),
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ),
            )
          else if (widget.journalError != null && widget.projections.isEmpty)
            _StateCard(
              key: const Key('setup-performance-error'),
              icon: Icons.warning_amber_rounded,
              title: _t(
                'دادهٔ واقعی قابل تأیید نیست',
                'Real data is unavailable',
              ),
              body: _t(
                'ژورنال یا reconciliation خطا دارد. نتیجهٔ تحلیلی همچنان جداگانه نمایش داده می‌شود؛ PnL واقعی حدس زده نمی‌شود.',
                'Journal or reconciliation has an error. Analytical results remain separate; real PnL is not estimated.',
              ),
            ),
          _SummaryCard(
            key: const Key('analytical-performance-summary'),
            title: _t(
              'عملکرد تحلیلی / شبیه‌سازی‌شده',
              'Analytical / simulated',
            ),
            verified: false,
            metrics: [
              _Metric(
                _t('نتیجه', 'Resolved'),
                '${report.summary.resolvedCount}',
              ),
              _Metric(_t('برد', 'Wins'), '${report.summary.analyticalWins}'),
              _Metric(
                _t('باخت', 'Losses'),
                '${report.summary.analyticalLosses}',
              ),
              _Metric(
                _t('خنثی', 'Breakeven'),
                '${report.summary.analyticalBreakeven}',
              ),
              _Metric(
                _t('Win rate', 'Win rate'),
                _percent(report.summary.analyticalWinRatePercent),
              ),
              _Metric(
                _t('مجموع R', 'Total R'),
                _number(report.summary.totalAnalyticalR, suffix: 'R'),
              ),
              _Metric(
                _t('میانگین R', 'Average R'),
                _number(report.summary.averageAnalyticalR, suffix: 'R'),
              ),
              _Metric(
                _t('PnL شبیه‌سازی', 'Simulated PnL'),
                _money(report.summary.totalSimulatedNetPnl),
              ),
            ],
            footnote: report.summary.analyticalUnavailable == 0
                ? null
                : _t(
                    '${report.summary.analyticalUnavailable} نتیجه دادهٔ اقتصادی کامل ندارد و در Win rate/PnL وارد نشده است.',
                    '${report.summary.analyticalUnavailable} results lack complete economics and are excluded from Win rate/PnL.',
                  ),
          ),
          const SizedBox(height: 12),
          _SummaryCard(
            key: const Key('actual-performance-summary'),
            title: _t('عملکرد واقعی صرافی', 'Real exchange performance'),
            verified: report.summary.hasConfirmedActualEconomics,
            metrics: report.summary.hasConfirmedActualEconomics
                ? [
                    _Metric(
                      _t('معاملهٔ بستهٔ تأییدشده', 'Confirmed closed'),
                      '${report.summary.actualConfirmedClosedCount}',
                    ),
                    _Metric(
                      _t('PnL خالص', 'Net realized PnL'),
                      _money(report.summary.actualNetRealizedPnl),
                    ),
                    _Metric(
                      _t('Win rate واقعی', 'Real win rate'),
                      _percent(report.summary.actualWinRatePercent),
                    ),
                    _Metric(
                      _t('Fee', 'Fees'),
                      _money(report.summary.actualFees),
                    ),
                    _Metric(
                      _t('Funding', 'Funding'),
                      _money(report.summary.actualFunding),
                    ),
                  ]
                : [
                    _Metric(
                      _t('معاملهٔ بستهٔ تأییدشده', 'Confirmed closed'),
                      _t('داده کافی نیست', 'Insufficient data'),
                    ),
                  ],
            footnote: report.summary.hasConfirmedActualEconomics
                ? _t(
                    'فقط ${report.summary.actualConfirmedClosedCount} معاملهٔ بستهٔ دارای evidence صرافی در جمع واقعی لحاظ شده است. باز: ${report.summary.actualConfirmedOpenCount}، در انتظار reconcile: ${report.summary.actualPendingCount}، mismatch: ${report.summary.actualMismatchCount}.',
                    'Only ${report.summary.actualConfirmedClosedCount} closed trades with exchange evidence are included. Open: ${report.summary.actualConfirmedOpenCount}, pending reconciliation: ${report.summary.actualPendingCount}, mismatch: ${report.summary.actualMismatchCount}.',
                  )
                : _t(
                    'عملکرد واقعی صرافی برای این ستاپ‌ها موجود نیست؛ صفر نمایش داده نمی‌شود و از نتیجهٔ قیمت تخمین نمی‌زنیم.',
                    'Real exchange performance is unavailable for these setups; it is not shown as zero or inferred from price outcomes.',
                  ),
          ),
          const SizedBox(height: 14),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: OutlinedButton.icon(
              key: const Key('setup-performance-export'),
              onPressed: report.rows.isEmpty
                  ? null
                  : () async {
                      await Clipboard.setData(
                        ClipboardData(text: report.toCsv()),
                      );
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            _t(
                              'CSV گزارش با ستون‌های تحلیلی و واقعیِ جداگانه کپی شد.',
                              'CSV copied with separate analytical and real columns.',
                            ),
                          ),
                        ),
                      );
                    },
              icon: const Icon(Icons.file_copy_outlined),
              label: Text(_t('کپی CSV', 'Copy CSV')),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            _t('جزئیات ستاپ‌ها', 'Setup details'),
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          if (report.rows.isEmpty)
            _StateCard(
              key: const Key('setup-performance-empty'),
              icon: Icons.query_stats_rounded,
              title: _t('دادهٔ کافی نیست', 'Insufficient data'),
              body: _t(
                'در این بازه و فیلتر، ستاپ نتیجه‌دار با timestamp معتبر وجود ندارد.',
                'No resolved setup with a valid timestamp matches this range and filter.',
              ),
            )
          else
            for (final row in report.rows) ...[
              _PerformanceRow(
                row: row,
                fa: _fa,
                onOpen: () => widget.onOpenSetup(row.entry),
              ),
              const SizedBox(height: 8),
            ],
          Text(
            _t(
              'این گزارش دربارهٔ نتایج گذشته است و ادعایی دربارهٔ سودآوری آینده یا آمادگی Live Trading ندارد.',
              'This report describes past evidence and makes no claim about future profitability or Live Trading readiness.',
            ),
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Future<void> _selectRange(SetupPerformanceRange value) async {
    if (value != SetupPerformanceRange.custom) {
      setState(() => _filter = _filter.copyWith(range: value));
      return;
    }
    final now = widget.now ?? DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1),
      initialDateRange: DateTimeRange(
        start: now.subtract(const Duration(days: 7)),
        end: now,
      ),
    );
    if (picked == null || !mounted) return;
    final start = DateTime(
      picked.start.year,
      picked.start.month,
      picked.start.day,
    );
    final endExclusive = DateTime(
      picked.end.year,
      picked.end.month,
      picked.end.day,
    ).add(const Duration(days: 1));
    setState(() {
      _filter = _filter.copyWith(
        range: SetupPerformanceRange.custom,
        customStartUtc: start.toUtc(),
        customEndUtcExclusive: endExclusive.toUtc(),
      );
    });
  }

  String _rangeLabel(SetupPerformanceRange value) => switch (value) {
    SetupPerformanceRange.today => _t('امروز', 'Today'),
    SetupPerformanceRange.sevenDays => _t('۷ روز', '7 days'),
    SetupPerformanceRange.thirtyDays => _t('۳۰ روز', '30 days'),
    SetupPerformanceRange.all => _t('همه', 'All'),
    SetupPerformanceRange.custom => _t('دلخواه', 'Custom'),
  };

  String _percent(double? value) => value == null
      ? _t('داده کافی نیست', 'Insufficient data')
      : '${value.toStringAsFixed(1)}%';

  String _number(double? value, {String suffix = ''}) => value == null
      ? _t('داده کافی نیست', 'Insufficient data')
      : '${value >= 0 ? '+' : ''}${value.toStringAsFixed(2)}$suffix';

  String _money(double? value) => value == null
      ? _t('داده کافی نیست', 'Insufficient data')
      : '${value >= 0 ? '+' : ''}${value.toStringAsFixed(2)} USDT';
}

class _StringFilter extends StatelessWidget {
  const _StringFilter({
    required this.label,
    required this.value,
    required this.allLabel,
    required this.values,
    required this.onChanged,
    super.key,
  });

  final String label;
  final String value;
  final String allLabel;
  final List<String> values;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
    initialValue: value,
    isExpanded: true,
    decoration: InputDecoration(labelText: label),
    items: [
      DropdownMenuItem(value: '', child: Text(allLabel)),
      for (final value in values)
        DropdownMenuItem(value: value, child: Text(value)),
    ],
    onChanged: (value) => onChanged(value ?? ''),
  );
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Text(text)),
      ],
    ),
  );
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.title,
    required this.verified,
    required this.metrics,
    this.footnote,
    super.key,
  });

  final String title;
  final bool verified;
  final List<_Metric> metrics;
  final String? footnote;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (verified)
                const Chip(
                  avatar: Icon(Icons.verified_rounded, size: 17),
                  label: Text('Exchange verified'),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final metric in metrics) _MetricTile(metric: metric),
            ],
          ),
          if (footnote != null) ...[
            const SizedBox(height: 10),
            Text(footnote!, style: Theme.of(context).textTheme.bodySmall),
          ],
        ],
      ),
    ),
  );
}

final class _Metric {
  const _Metric(this.label, this.value);
  final String label;
  final String value;
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.metric});
  final _Metric metric;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minWidth: 126),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      border: Border.all(color: Theme.of(context).dividerColor),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(metric.label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 2),
        Text(
          metric.value,
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
        ),
      ],
    ),
  );
}

class _PerformanceRow extends StatelessWidget {
  const _PerformanceRow({
    required this.row,
    required this.fa,
    required this.onOpen,
  });

  final SetupPerformanceRow row;
  final bool fa;
  final VoidCallback onOpen;
  String _t(String faText, String en) => fa ? faText : en;

  @override
  Widget build(BuildContext context) {
    final entry = row.entry;
    final actual = row.actual;
    return Card(
      key: Key('setup-performance-row-${entry.setupId}'),
      child: ExpansionTile(
        title: Text(
          '${entry.symbol} • ${entry.timeframe}',
          textDirection: TextDirection.ltr,
        ),
        subtitle: Text(
          '${_direction(entry.direction)} • ${_analytical(row.analyticalClassification)} • ${_formatDate(entry.resolvedAt)}',
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        children: [
          _DetailLine(
            label: _t('Entry', 'Entry'),
            value: '${_price(entry.entryLower)} – ${_price(entry.entryUpper)}',
          ),
          _DetailLine(label: 'SL', value: _price(entry.stopLoss)),
          _DetailLine(
            label: 'TP',
            value: entry.targets.map(_price).join(' / '),
          ),
          _DetailLine(
            label: _t('نتیجه تحلیلی', 'Analytical result'),
            value:
                '${entry.outcome.name} • ${row.analyticalNetPnl == null ? _t('داده کافی نیست', 'Insufficient data') : '${row.analyticalNetPnl! >= 0 ? '+' : ''}${row.analyticalNetPnl!.toStringAsFixed(2)} USDT'}${row.analyticalR == null ? '' : ' • ${row.analyticalR!.toStringAsFixed(2)}R'}',
          ),
          _DetailLine(
            label: _t('منبع تحلیلی', 'Analytical provenance'),
            value: _t(
              'بازپخش کندل بسته‌شده؛ شبیه‌سازی پس از هزینه',
              'Closed-candle replay; simulated after costs',
            ),
          ),
          _DetailLine(
            label: _t('وضعیت واقعی', 'Real status'),
            value: _actualStatus(actual.status),
          ),
          if (actual.journalTradeId != null)
            _DetailLine(
              label: _t('شناسه ژورنال', 'Journal trade'),
              value: actual.journalTradeId!,
            ),
          if (actual.positionId != null)
            _DetailLine(label: 'Position ID', value: actual.positionId!),
          if (actual.netRealizedPnl != null)
            _DetailLine(
              label: _t('PnL واقعی خالص', 'Real net realized PnL'),
              value:
                  '${actual.netRealizedPnl! >= 0 ? '+' : ''}${actual.netRealizedPnl!.toStringAsFixed(2)} USDT',
            ),
          if (actual.unrealizedPnl != null)
            _DetailLine(
              label: _t('PnL باز (جدا)', 'Open unrealized PnL (separate)'),
              value:
                  '${actual.unrealizedPnl! >= 0 ? '+' : ''}${actual.unrealizedPnl!.toStringAsFixed(2)} USDT',
            ),
          if (actual.asOfUtc != null)
            _DetailLine(
              label: _t('Exchange as-of', 'Exchange as-of'),
              value: actual.asOfUtc!.toUtc().toIso8601String(),
            ),
          if (actual.provenance != null)
            _DetailLine(
              label: _t('Provenance', 'Provenance'),
              value: actual.provenance!,
            ),
          if (actual.warning != null)
            _DetailLine(
              label: _t('Diagnostics', 'Diagnostics'),
              value: actual.warning!,
            ),
          const SizedBox(height: 8),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton.icon(
              onPressed: onOpen,
              icon: const Icon(Icons.open_in_new_rounded),
              label: Text(_t('باز کردن ستاپ', 'Open setup')),
            ),
          ),
        ],
      ),
    );
  }

  String _direction(TradeDirection value) => switch (value) {
    TradeDirection.long => 'LONG',
    TradeDirection.short => 'SHORT',
    TradeDirection.wait => 'WAIT',
  };

  String _analytical(SetupAnalyticalClassification value) => switch (value) {
    SetupAnalyticalClassification.win => _t('برد تحلیلی', 'Analytical win'),
    SetupAnalyticalClassification.loss => _t('باخت تحلیلی', 'Analytical loss'),
    SetupAnalyticalClassification.breakeven => _t('خنثی', 'Breakeven'),
    SetupAnalyticalClassification.unavailable => _t(
      'داده کافی نیست',
      'Insufficient data',
    ),
  };

  String _actualStatus(SetupActualEvidenceStatus value) => switch (value) {
    SetupActualEvidenceStatus.confirmedClosed => _t(
      'واقعی و تأییدشده توسط صرافی',
      'Real and exchange-confirmed',
    ),
    SetupActualEvidenceStatus.confirmedOpen => _t(
      'پوزیشن باز؛ PnL بسته‌شده ندارد',
      'Open position; no closed PnL',
    ),
    SetupActualEvidenceStatus.pendingReconciliation => _t(
      'در انتظار reconciliation',
      'Pending reconciliation',
    ),
    SetupActualEvidenceStatus.mismatch => _t(
      'عدم تطابق لینک ستاپ و معامله',
      'Setup/trade link mismatch',
    ),
    SetupActualEvidenceStatus.unavailable => _t(
      'عملکرد واقعی موجود نیست',
      'Real performance unavailable',
    ),
  };

  String _price(double? value) =>
      value == null || !value.isFinite ? '—' : value.toStringAsFixed(6);

  String _formatDate(DateTime? value) =>
      value == null ? '—' : value.toLocal().toString().split('.').first;
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 132,
          child: Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(child: SelectableText(value)),
      ],
    ),
  );
}

class _StateCard extends StatelessWidget {
  const _StateCard({
    required this.icon,
    required this.title,
    required this.body,
    super.key,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        children: [
          Icon(icon, size: 36),
          const SizedBox(height: 8),
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(body, textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}
