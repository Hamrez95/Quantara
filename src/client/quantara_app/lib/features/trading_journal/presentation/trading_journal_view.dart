import 'package:flutter/material.dart';

import '../domain/trading_journal_models.dart';
import '../domain/trading_journal_projection.dart';
import '../domain/trading_journal_statistics.dart';

enum _JournalFilter { all, open, closed, missed, simulated }

final class TradingJournalView extends StatefulWidget {
  const TradingJournalView({
    required this.locale,
    required this.projections,
    this.statistics,
    this.isLoading = false,
    this.error,
    super.key,
  });

  final Locale locale;
  final List<TradingJournalProjection> projections;
  final TradingJournalStatistics? statistics;
  final bool isLoading;
  final String? error;

  @override
  State<TradingJournalView> createState() => _TradingJournalViewState();
}

final class _TradingJournalViewState extends State<TradingJournalView> {
  _JournalFilter _filter = _JournalFilter.all;
  TradingJournalProjection? _selected;

  bool get _persian => widget.locale.languageCode != 'en';

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: _persian ? TextDirection.rtl : TextDirection.ltr,
      child: _selected == null ? _buildList(context) : _buildDetail(context),
    );
  }

  Widget _buildList(BuildContext context) {
    if (widget.isLoading && widget.projections.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: CircularProgressIndicator(),
        ),
      );
    }
    final error = widget.error;
    if (error != null && widget.projections.isEmpty) {
      return _StateCard(
        icon: Icons.gpp_bad_outlined,
        title: _persian ? 'خطای یکپارچگی ژورنال' : 'Journal integrity error',
        message: error,
      );
    }
    if (widget.projections.isEmpty) {
      return _StateCard(
        icon: Icons.menu_book_outlined,
        title: _persian ? 'هنوز رکوردی ثبت نشده' : 'No journal records yet.',
        message: _persian
            ? 'سیگنال‌ها، ورودها و نتیجه پوزیشن‌ها پس از ثبت در این بخش نمایش داده می‌شوند.'
            : 'Signals, executions and position outcomes will appear here.',
      );
    }

    final filtered = widget.projections.where(_matches).toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _persian ? 'ژورنال معاملات' : 'Trading Journal',
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 6),
        Text(
          _persian
              ? 'واقعیت صرافی، محاسبات Quantara و یادداشت‌های کاربر جدا و قابل‌ردیابی نگه داشته می‌شوند.'
              : 'Exchange facts, Quantara calculations and user notes remain separately attributable.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        if (widget.statistics != null) ...[
          const SizedBox(height: 14),
          _StatisticsStrip(statistics: widget.statistics!, persian: _persian),
        ],
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _JournalFilter.values
              .map(
                (filter) => FilterChip(
                  label: Text(_filterLabel(filter)),
                  selected: _filter == filter,
                  onSelected: (_) => setState(() => _filter = filter),
                ),
              )
              .toList(growable: false),
        ),
        const SizedBox(height: 14),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _StateCard(
              icon: Icons.warning_amber_rounded,
              title: _persian ? 'هشدار ژورنال' : 'Journal warning',
              message: error,
              compact: true,
            ),
          ),
        if (filtered.isEmpty)
          _StateCard(
            icon: Icons.filter_alt_off_outlined,
            title: _persian
                ? 'نتیجه‌ای در این فیلتر نیست'
                : 'No matching records',
            message: _persian
                ? 'فیلتر دیگری انتخاب کن.'
                : 'Choose another filter.',
          )
        else
          ...filtered.map(
            (projection) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _JournalTradeCard(
                projection: projection,
                persian: _persian,
                onTap: () => setState(() => _selected = projection),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildDetail(BuildContext context) {
    final projection = _selected!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            onPressed: () => setState(() => _selected = null),
            icon: const Icon(Icons.arrow_back_rounded),
            label: Text(_persian ? 'بازگشت به ژورنال' : 'Back to journal'),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _persian ? 'تایم‌لاین پوزیشن' : 'Position Timeline',
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 8),
        Text(
          '${projection.symbol} · ${projection.timeframe} · ${projection.direction.name.toUpperCase()}',
          textDirection: TextDirection.ltr,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 14),
        _ProjectionSummary(projection: projection, persian: _persian),
        const SizedBox(height: 16),
        if (projection.timeline.isEmpty)
          _StateCard(
            icon: Icons.timeline_outlined,
            title: _persian ? 'رویدادی ثبت نشده' : 'No events recorded',
            message: _persian
                ? 'پلن معامله ذخیره شده اما رویداد اجرایی هنوز موجود نیست.'
                : 'The trade plan exists, but no execution event is available.',
          )
        else
          ...projection.timeline.indexed.map(
            (entry) => _TimelineEventTile(
              event: entry.$2,
              last: entry.$1 == projection.timeline.length - 1,
              persian: _persian,
            ),
          ),
      ],
    );
  }

  bool _matches(TradingJournalProjection projection) => switch (_filter) {
    _JournalFilter.all => true,
    _JournalFilter.open => projection.state == TradingJournalTradeState.open,
    _JournalFilter.closed =>
      projection.state == TradingJournalTradeState.closed,
    _JournalFilter.missed =>
      projection.state == TradingJournalTradeState.missed,
    _JournalFilter.simulated =>
      projection.state == TradingJournalTradeState.simulated,
  };

  String _filterLabel(_JournalFilter filter) => switch (filter) {
    _JournalFilter.all => _persian ? 'همه' : 'All',
    _JournalFilter.open => _persian ? 'باز' : 'Open',
    _JournalFilter.closed => _persian ? 'بسته' : 'Closed',
    _JournalFilter.missed => _persian ? 'از دست‌رفته' : 'Missed',
    _JournalFilter.simulated => _persian ? 'شبیه‌سازی' : 'Simulated',
  };
}

final class _JournalTradeCard extends StatelessWidget {
  const _JournalTradeCard({
    required this.projection,
    required this.persian,
    required this.onTap,
  });

  final TradingJournalProjection projection;
  final bool persian;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final net = projection.netPnl;
    final netText = net == null
        ? (persian ? 'ناموجود' : 'Unavailable')
        : '${net >= 0 ? '+' : ''}${net.toStringAsFixed(4)} USDT';
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                child: Icon(
                  projection.state == TradingJournalTradeState.closed
                      ? Icons.check_rounded
                      : Icons.timeline_rounded,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      projection.symbol,
                      textDirection: TextDirection.ltr,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${projection.timeframe} · ${projection.strategy} · ${projection.state.name}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    netText,
                    textDirection: TextDirection.ltr,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: net == null
                          ? scheme.onSurfaceVariant
                          : net >= 0
                          ? Colors.green
                          : scheme.error,
                    ),
                  ),
                  Text(
                    projection.integrity.name,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final class _ProjectionSummary extends StatelessWidget {
  const _ProjectionSummary({required this.projection, required this.persian});

  final TradingJournalProjection projection;
  final bool persian;

  @override
  Widget build(BuildContext context) {
    final items = <(String, String)>[
      (
        persian ? 'سود/زیان خالص' : 'Net PnL',
        projection.netPnl == null
            ? (persian ? 'ناموجود' : 'Unavailable')
            : '${projection.netPnl!.toStringAsFixed(4)} USDT',
      ),
      (
        persian ? 'کارمزد' : 'Fees',
        projection.fees == null
            ? (persian ? 'ناموجود' : 'Unavailable')
            : '${projection.fees!.toStringAsFixed(4)} USDT',
      ),
      (
        persian ? 'فاندینگ' : 'Funding',
        projection.funding == null
            ? (persian ? 'ناموجود' : 'Unavailable')
            : '${projection.funding!.toStringAsFixed(4)} USDT',
      ),
      (
        'R',
        projection.realizedR?.toStringAsFixed(2) ??
            (persian ? 'ناموجود' : 'Unavailable'),
      ),
      (
        persian ? 'بالاترین تارگت' : 'Highest target',
        'TP${projection.highestTargetReached}',
      ),
      (
        persian ? 'دلیل خروج' : 'Close reason',
        projection.closeReason?.name ?? (persian ? 'باز' : 'Open'),
      ),
    ];
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: items
          .map(
            (item) => SizedBox(
              width: 170,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.$1,
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                      const SizedBox(height: 5),
                      Text(
                        item.$2,
                        textDirection: TextDirection.ltr,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          )
          .toList(growable: false),
    );
  }
}

final class _TimelineEventTile extends StatelessWidget {
  const _TimelineEventTile({
    required this.event,
    required this.last,
    required this.persian,
  });

  final TradingJournalEvent event;
  final bool last;
  final bool persian;

  @override
  Widget build(BuildContext context) {
    final title = _eventTitle(event.type, persian);
    final details = <String>[
      if (event.quantity != null) 'qty ${event.quantity}',
      if (event.price != null) '@ ${event.price}',
      if (event.grossPnl != null) 'PnL ${event.grossPnl}',
      if (event.fee != null) 'fee ${event.fee}',
      if (event.remainingQuantity != null)
        'remaining ${event.remainingQuantity}',
      event.source.name,
      event.quality.name,
    ];
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 30,
            child: Column(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: event.quality == TradingJournalFactQuality.confirmed
                        ? Colors.green
                        : Theme.of(context).colorScheme.tertiary,
                    shape: BoxShape.circle,
                  ),
                ),
                if (!last)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: Theme.of(context).dividerColor,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        details.join(' · '),
                        textDirection: TextDirection.ltr,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 5),
                      Text(
                        event.occurredAt.toLocal().toIso8601String(),
                        textDirection: TextDirection.ltr,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _eventTitle(TradingJournalEventType type, bool persian) =>
      switch (type) {
        TradingJournalEventType.entrySubmitted =>
          persian ? 'Entry · ارسال ورود' : 'Entry submitted',
        TradingJournalEventType.entryPartiallyFilled =>
          persian ? 'Entry · پرشدن جزئی' : 'Entry partial fill',
        TradingJournalEventType.entryFilled =>
          persian ? 'Entry · ورود تأییدشده' : 'Entry filled',
        TradingJournalEventType.takeProfitFilled =>
          persian ? 'TP · برداشت سود' : 'Take profit fill',
        TradingJournalEventType.stopMoveRequested =>
          persian ? 'SL · درخواست جابه‌جایی' : 'Stop move requested',
        TradingJournalEventType.stopMoveConfirmed =>
          persian ? 'SL · جابه‌جایی تأییدشده' : 'Stop move confirmed',
        TradingJournalEventType.positionClosed =>
          persian ? 'Close · بسته‌شدن پوزیشن' : 'Close · Position closed',
        TradingJournalEventType.liquidation =>
          persian ? 'Close · لیکویید' : 'Close · Liquidation',
        _ => type.name,
      };
}

final class _StatisticsStrip extends StatelessWidget {
  const _StatisticsStrip({required this.statistics, required this.persian});

  final TradingJournalStatistics statistics;
  final bool persian;

  @override
  Widget build(BuildContext context) {
    final values = [
      (
        persian ? 'برد' : 'Win rate',
        '${statistics.winRatePercent.toStringAsFixed(1)}%',
      ),
      (
        persian ? 'انتظار' : 'Expectancy',
        statistics.expectancy.toStringAsFixed(3),
      ),
      (
        persian ? 'Profit factor' : 'Profit factor',
        statistics.profitFactor.isInfinite
            ? '∞'
            : statistics.profitFactor.toStringAsFixed(2),
      ),
      (
        persian ? 'میانگین R' : 'Average R',
        statistics.averageR.toStringAsFixed(2),
      ),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: values
          .map(
            (item) => Chip(
              label: Text('${item.$1}: ${item.$2}'),
              avatar: const Icon(Icons.analytics_outlined, size: 18),
            ),
          )
          .toList(growable: false),
    );
  }
}

final class _StateCard extends StatelessWidget {
  const _StateCard({
    required this.icon,
    required this.title,
    required this.message,
    this.compact = false,
  });

  final IconData icon;
  final String title;
  final String message;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(compact ? 14 : 24),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(message),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
