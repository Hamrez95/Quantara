import 'package:flutter/material.dart';

import '../../../core/formatting/number_formatters.dart';
import '../../../core/theme/quantara_theme.dart';
import '../../../core/widgets/quantara_ui.dart';
import '../../market_analysis/domain/market_chart_models.dart';
import '../../market_analysis/presentation/quantara_candlestick_chart.dart';
import '../../market_analysis/presentation/tradingview_lightweight_chart.dart';
import '../../owner_alpha/domain/owner_alpha_models.dart';
import '../domain/trading_journal_models.dart';
import '../domain/trading_journal_projection.dart';
import '../domain/trading_journal_statistics.dart';

enum _JournalFilter { all, open, closed, missed, simulated }

final class TradingJournalView extends StatefulWidget {
  const TradingJournalView({
    required this.locale,
    required this.projections,
    this.statistics,
    this.liveAnalyses = const {},
    this.liveIdeas = const {},
    this.isLoading = false,
    this.error,
    super.key,
  });

  final Locale locale;
  final List<TradingJournalProjection> projections;
  final TradingJournalStatistics? statistics;
  final Map<String, TimeframeChartAnalysis> liveAnalyses;
  final Map<String, TradeIdea> liveIdeas;
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
  void didUpdateWidget(covariant TradingJournalView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final selected = _selected;
    if (selected == null) return;
    for (final projection in widget.projections) {
      if (projection.journalTradeId == selected.journalTradeId) {
        _selected = projection;
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: _persian ? TextDirection.rtl : TextDirection.ltr,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final content = AnimatedSwitcher(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : QuantaraMotion.standard,
            child: _selected == null
                ? KeyedSubtree(
                    key: const ValueKey('journal-list'),
                    child: _buildList(context),
                  )
                : KeyedSubtree(
                    key: ValueKey(
                      'journal-detail-${_selected!.journalTradeId}',
                    ),
                    child: _buildDetail(context),
                  ),
          );
          if (!constraints.hasBoundedHeight) return content;
          return SingleChildScrollView(child: content);
        },
      ),
    );
  }

  Widget _buildList(BuildContext context) {
    if (widget.isLoading && widget.projections.isEmpty) {
      return _StateCard(
        icon: Icons.hourglass_top_rounded,
        title: _persian ? 'در حال بازیابی ژورنال' : 'Loading journal',
        message: _persian
            ? 'رویدادها و واقعیت صرافی در حال بررسی یکپارچگی هستند.'
            : 'Events and exchange facts are being checked for integrity.',
        loading: true,
      );
    }
    final error = widget.error;
    if (error != null && widget.projections.isEmpty) {
      return _StateCard(
        icon: Icons.gpp_bad_outlined,
        title: _persian ? 'خطای یکپارچگی ژورنال' : 'Journal integrity error',
        message: error,
        color: Theme.of(context).colorScheme.error,
      );
    }
    if (widget.projections.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _JournalHero(persian: _persian, records: 0, open: 0, verified: true),
          const SizedBox(height: 16),
          _StateCard(
            icon: Icons.menu_book_outlined,
            title: _persian
                ? 'هنوز رکوردی ثبت نشده'
                : 'No journal records yet.',
            message: _persian
                ? 'سیگنال‌ها، ورودها و نتیجه پوزیشن‌ها پس از ثبت در این بخش نمایش داده می‌شوند.'
                : 'Signals, executions and position outcomes will appear here.',
          ),
        ],
      );
    }

    final filtered = widget.projections.where(_matches).toList(growable: false);
    final openCount = widget.projections
        .where((item) => item.state == TradingJournalTradeState.open)
        .length;
    final verified = widget.projections.every(
      (item) => item.integrity != TradingJournalIntegrity.unverified,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _JournalHero(
          persian: _persian,
          records: widget.projections.length,
          open: openCount,
          verified: verified,
        ),
        if (widget.statistics != null) ...[
          const SizedBox(height: 16),
          _StatisticsPanel(statistics: widget.statistics!, persian: _persian),
        ],
        const SizedBox(height: 16),
        SectionCard(
          accentColor: QuantaraColors.violet,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionHeading(
                title: _persian ? 'فیلتر وضعیت‌ها' : 'Journal filters',
                subtitle: _persian
                    ? 'رکوردها را براساس چرخه واقعی معامله جدا کن.'
                    : 'Separate records by their real trade lifecycle.',
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _JournalFilter.values
                    .map(
                      (filter) => FilterChip(
                        avatar: Icon(_filterIcon(filter), size: 17),
                        label: Text(_filterLabel(filter)),
                        selected: _filter == filter,
                        onSelected: (_) => setState(() => _filter = filter),
                      ),
                    )
                    .toList(growable: false),
              ),
            ],
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: 12),
          _StateCard(
            icon: Icons.warning_amber_rounded,
            title: _persian ? 'هشدار ژورنال' : 'Journal warning',
            message: error,
            compact: true,
            color: QuantaraColors.warning,
          ),
        ],
        const SizedBox(height: 16),
        SectionHeading(
          title: _persian ? 'تاریخچه معاملات' : 'Trade history',
          subtitle: _persian
              ? '${filtered.length} رکورد مطابق فیلتر انتخاب‌شده'
              : '${filtered.length} records match the selected filter',
        ),
        const SizedBox(height: 12),
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
          for (var index = 0; index < filtered.length; index++) ...[
            _JournalTradeCard(
              projection: filtered[index],
              persian: _persian,
              onTap: () => setState(() => _selected = filtered[index]),
            ),
            if (index != filtered.length - 1) const SizedBox(height: 12),
          ],
      ],
    );
  }

  Widget _buildDetail(BuildContext context) {
    final projection = _selected!;
    final symbolKey = projection.symbol.trim().toUpperCase();
    final requestedTimeframe = projection.timeframe.trim();
    final requestedKey = '$symbolKey|$requestedTimeframe';
    var liveAnalysis = widget.liveAnalyses[requestedKey];
    var liveIdea = widget.liveIdeas[requestedKey];
    if (liveAnalysis == null) {
      for (final fallbackTimeframe in const ['1h', '15m', '5m', '4h']) {
        final fallbackKey = '$symbolKey|$fallbackTimeframe';
        final fallbackAnalysis = widget.liveAnalyses[fallbackKey];
        if (fallbackAnalysis == null) continue;
        liveAnalysis = fallbackAnalysis;
        liveIdea = widget.liveIdeas[fallbackKey];
        break;
      }
    }
    if (liveAnalysis == null) {
      for (final entry in widget.liveAnalyses.entries) {
        if (!entry.key.startsWith('$symbolKey|')) continue;
        liveAnalysis = entry.value;
        liveIdea = widget.liveIdeas[entry.key];
        break;
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            onPressed: () => setState(() => _selected = null),
            icon: Icon(
              _persian ? Icons.arrow_forward_rounded : Icons.arrow_back_rounded,
            ),
            label: Text(_persian ? 'بازگشت به ژورنال' : 'Back to journal'),
          ),
        ),
        const SizedBox(height: 6),
        _JournalDetailHero(projection: projection, persian: _persian),
        const SizedBox(height: 16),
        _ProjectionSummary(projection: projection, persian: _persian),
        const SizedBox(height: 16),
        _JournalLivePositionChart(
          projection: projection,
          analysis: liveAnalysis,
          currentIdea: liveIdea,
          persian: _persian,
        ),
        const SizedBox(height: 16),
        _TradeEvidencePanel(projection: projection, persian: _persian),
        const SizedBox(height: 16),
        SectionHeading(
          title: _persian ? 'تایم‌لاین پوزیشن' : 'Position Timeline',
          subtitle: _persian
              ? 'ترتیب زمانی واقعیت صرافی، محاسبات Quantara و ورودی کاربر'
              : 'Ordered exchange facts, Quantara calculations and user input',
        ),
        const SizedBox(height: 12),
        if (projection.timeline.isEmpty)
          _StateCard(
            icon: Icons.timeline_outlined,
            title: _persian ? 'رویدادی ثبت نشده' : 'No events recorded',
            message: _persian
                ? 'پلن معامله ذخیره شده اما رویداد اجرایی هنوز موجود نیست.'
                : 'The trade plan exists, but no execution event is available.',
          )
        else
          for (var index = 0; index < projection.timeline.length; index++)
            _TimelineEventTile(
              event: projection.timeline[index],
              last: index == projection.timeline.length - 1,
              persian: _persian,
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

  IconData _filterIcon(_JournalFilter filter) => switch (filter) {
    _JournalFilter.all => Icons.apps_rounded,
    _JournalFilter.open => Icons.play_circle_outline_rounded,
    _JournalFilter.closed => Icons.check_circle_outline_rounded,
    _JournalFilter.missed => Icons.timer_off_outlined,
    _JournalFilter.simulated => Icons.science_outlined,
  };
}

final class _JournalHero extends StatelessWidget {
  const _JournalHero({
    required this.persian,
    required this.records,
    required this.open,
    required this.verified,
  });

  final bool persian;
  final int records;
  final int open;
  final bool verified;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final statusColor = verified
        ? QuantaraColors.success
        : QuantaraColors.warning;
    return Semantics(
      container: true,
      label: persian ? 'ژورنال معاملات' : 'Trading Journal',
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(QuantaraRadius.large),
          border: Border.all(
            color: QuantaraColors.violet.withValues(alpha: 0.3),
          ),
          gradient: LinearGradient(
            begin: AlignmentDirectional.topStart,
            end: AlignmentDirectional.bottomEnd,
            colors: [
              Color.alphaBlend(
                QuantaraColors.violet.withValues(alpha: 0.18),
                scheme.surface,
              ),
              Color.alphaBlend(
                QuantaraColors.electricBlue.withValues(alpha: 0.11),
                scheme.surface,
              ),
              scheme.surface,
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: QuantaraColors.violet.withValues(alpha: 0.11),
              blurRadius: 34,
              spreadRadius: -18,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: Stack(
          children: [
            PositionedDirectional(
              top: -78,
              end: -65,
              child: IgnorePointer(
                child: Container(
                  width: 210,
                  height: 210,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        QuantaraColors.cyan.withValues(alpha: 0.18),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final compact = constraints.maxWidth < 580;
                      final identity = Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: QuantaraColors.premiumGradient,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: QuantaraColors.violet.withValues(
                                    alpha: 0.2,
                                  ),
                                  blurRadius: 18,
                                  spreadRadius: -8,
                                ),
                              ],
                            ),
                            child: const SizedBox.square(
                              dimension: 52,
                              child: Icon(
                                Icons.menu_book_rounded,
                                color: QuantaraColors.ink,
                              ),
                            ),
                          ),
                          const SizedBox(width: 13),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  persian
                                      ? 'ژورنال معاملات'
                                      : 'Trading Journal',
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall
                                      ?.copyWith(fontWeight: FontWeight.w900),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  persian
                                      ? 'ثبت دقیق تصمیم، اجرا، نتیجه و کیفیت داده در یک مسیر قابل‌ردیابی'
                                      : 'An attributable trail of decisions, execution, outcome and data quality',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: scheme.onSurfaceVariant,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                      final status = StatusPill(
                        label: verified
                            ? (persian
                                  ? 'یکپارچگی تأییدشده'
                                  : 'Integrity verified')
                            : (persian ? 'نیازمند بررسی' : 'Review required'),
                        color: statusColor,
                        icon: verified
                            ? Icons.verified_user_outlined
                            : Icons.warning_amber_rounded,
                      );
                      if (compact) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            identity,
                            const SizedBox(height: 14),
                            Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: status,
                            ),
                          ],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: identity),
                          const SizedBox(width: 16),
                          status,
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 18),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final columns = constraints.maxWidth >= 680 ? 3 : 1;
                      const gap = 10.0;
                      final width =
                          (constraints.maxWidth - gap * (columns - 1)) /
                          columns;
                      final metrics = [
                        (
                          persian ? 'کل رکوردها' : 'Total records',
                          '$records',
                          Icons.library_books_outlined,
                          QuantaraColors.violet,
                        ),
                        (
                          persian ? 'پوزیشن باز' : 'Open positions',
                          '$open',
                          Icons.timeline_rounded,
                          open > 0
                              ? QuantaraColors.cyan
                              : QuantaraColors.success,
                        ),
                        (
                          persian ? 'ردیابی زمانی' : 'Temporal audit',
                          persian ? 'فعال' : 'Active',
                          Icons.schedule_rounded,
                          statusColor,
                        ),
                      ];
                      return Wrap(
                        spacing: gap,
                        runSpacing: gap,
                        children: [
                          for (final metric in metrics)
                            SizedBox(
                              width: width,
                              child: FinanceMetricPanel(
                                label: metric.$1,
                                value: metric.$2,
                                icon: metric.$3,
                                color: metric.$4,
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _StatisticsPanel extends StatelessWidget {
  const _StatisticsPanel({required this.statistics, required this.persian});

  final TradingJournalStatistics statistics;
  final bool persian;

  @override
  Widget build(BuildContext context) {
    final factor = statistics.profitFactor.isInfinite
        ? '∞'
        : statistics.profitFactor.toStringAsFixed(2);
    final metrics = <(String, String, IconData, Color)>[
      (
        persian ? 'معاملات بسته' : 'Closed trades',
        '${statistics.closedCount}',
        Icons.check_circle_outline_rounded,
        QuantaraColors.cyan,
      ),
      (
        persian ? 'نرخ برد' : 'Win rate',
        '${statistics.winRatePercent.toStringAsFixed(1)}%',
        Icons.emoji_events_outlined,
        statistics.winRatePercent >= 50
            ? QuantaraColors.success
            : QuantaraColors.warning,
      ),
      (
        persian ? 'میانگین R' : 'Average R',
        statistics.averageR.toStringAsFixed(2),
        Icons.balance_rounded,
        statistics.averageR >= 0
            ? QuantaraColors.success
            : QuantaraColors.danger,
      ),
      (
        persian ? 'Profit factor' : 'Profit factor',
        factor,
        Icons.query_stats_rounded,
        statistics.profitFactor >= 1
            ? QuantaraColors.violet
            : QuantaraColors.warning,
      ),
      (
        persian ? 'امید ریاضی' : 'Expectancy',
        statistics.expectancy.toStringAsFixed(3),
        Icons.insights_rounded,
        statistics.expectancy >= 0
            ? QuantaraColors.success
            : QuantaraColors.danger,
      ),
      (
        persian ? 'بیشترین افت' : 'Max drawdown',
        QuantaraNumberFormat.marketValue(
          statistics.maximumDrawdown,
          unit: 'USDT',
        ),
        Icons.trending_down_rounded,
        statistics.maximumDrawdown > 0
            ? QuantaraColors.warning
            : QuantaraColors.success,
      ),
    ];
    return SectionCard(
      accentColor: QuantaraColors.success,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeading(
            title: persian ? 'خلاصه عملکرد' : 'Performance summary',
            subtitle: persian
                ? 'آمار فقط از معاملات بسته و داده‌های قابل‌انتساب محاسبه می‌شود.'
                : 'Statistics use only closed trades and attributable facts.',
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 900
                  ? 3
                  : constraints.maxWidth >= 520
                  ? 2
                  : 1;
              const gap = 10.0;
              final width =
                  (constraints.maxWidth - gap * (columns - 1)) / columns;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final metric in metrics)
                    SizedBox(
                      width: width,
                      child: FinanceMetricPanel(
                        label: metric.$1,
                        value: metric.$2,
                        icon: metric.$3,
                        color: metric.$4,
                      ),
                    ),
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
                label: persian
                    ? '${statistics.takeProfitCount} خروج با تارگت'
                    : '${statistics.takeProfitCount} target exits',
                color: QuantaraColors.success,
                icon: Icons.flag_outlined,
              ),
              StatusPill(
                label: persian
                    ? '${statistics.stopCount} خروج با استاپ'
                    : '${statistics.stopCount} stop exits',
                color: QuantaraColors.danger,
                icon: Icons.shield_outlined,
              ),
            ],
          ),
        ],
      ),
    );
  }
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
    final stateColor = _tradeStateColor(context, projection.state);
    final net = projection.netPnl;
    final netColor = net == null
        ? scheme.onSurfaceVariant
        : net >= 0
        ? QuantaraColors.success
        : QuantaraColors.danger;
    final netText = net == null
        ? projection.economicsPending
              ? (persian ? 'تطبیق PnL در انتظار' : 'PnL reconciliation pending')
              : (persian ? 'ناموجود' : 'Unavailable')
        : '${net >= 0 ? '+' : ''}${QuantaraNumberFormat.marketValue(net, unit: 'USDT')}';
    final directionColor = projection.direction == TradingJournalDirection.long
        ? QuantaraColors.electricBlue
        : projection.direction == TradingJournalDirection.short
        ? QuantaraColors.violet
        : scheme.onSurfaceVariant;

    return SectionCard(
      accentColor: stateColor,
      semanticLabel: '${projection.symbol} $netText',
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 560;
              final identity = Row(
                children: [
                  SymbolAvatar(symbol: projection.symbol, size: 48),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          projection.symbol,
                          textDirection: TextDirection.ltr,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        Text(
                          '${projection.strategy} · ${projection.timeframe}',
                          textDirection: TextDirection.ltr,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              );
              final result = Column(
                crossAxisAlignment: compact
                    ? CrossAxisAlignment.start
                    : CrossAxisAlignment.end,
                children: [
                  Text(
                    netText,
                    textDirection: TextDirection.ltr,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: netColor,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _formatDate(projection.closedAt ?? projection.decidedAt),
                    textDirection: TextDirection.ltr,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              );
              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [identity, const SizedBox(height: 12), result],
                );
              }
              return Row(
                children: [
                  Expanded(child: identity),
                  const SizedBox(width: 16),
                  result,
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
                label: _tradeStateLabel(persian, projection.state),
                color: stateColor,
                icon: _tradeStateIcon(projection.state),
              ),
              StatusPill(
                label: projection.direction == TradingJournalDirection.long
                    ? (persian ? 'خرید' : 'Long')
                    : projection.direction == TradingJournalDirection.short
                    ? (persian ? 'فروش' : 'Short')
                    : (persian ? 'انتظار' : 'Wait'),
                color: directionColor,
                icon: projection.direction == TradingJournalDirection.long
                    ? Icons.north_east_rounded
                    : projection.direction == TradingJournalDirection.short
                    ? Icons.south_east_rounded
                    : Icons.pause_rounded,
              ),
              StatusPill(
                label: projection.integrity == TradingJournalIntegrity.verified
                    ? (persian ? 'تأییدشده' : 'Verified')
                    : projection.integrity == TradingJournalIntegrity.recovered
                    ? (persian ? 'بازیابی‌شده' : 'Recovered')
                    : (persian ? 'تأییدنشده' : 'Unverified'),
                color:
                    projection.integrity == TradingJournalIntegrity.unverified
                    ? QuantaraColors.warning
                    : QuantaraColors.cyan,
                icon: Icons.verified_user_outlined,
              ),
              if (projection.state == TradingJournalTradeState.closed)
                StatusPill(
                  label: _closeReasonLabel(persian, projection.closeReason),
                  color: _closeReasonColor(context, projection.closeReason),
                  icon: Icons.logout_rounded,
                ),
              if (projection.holdingDuration != null)
                StatusPill(
                  label: _formatHoldingDuration(projection.holdingDuration!),
                  color: QuantaraColors.violet,
                  icon: Icons.timer_outlined,
                ),
              if (projection.realizedR != null)
                StatusPill(
                  label: 'R ${projection.realizedR!.toStringAsFixed(2)}',
                  color: projection.realizedR! >= 0
                      ? QuantaraColors.success
                      : QuantaraColors.danger,
                  icon: Icons.balance_rounded,
                ),
            ],
          ),
          const SizedBox(height: 11),
          Row(
            children: [
              Expanded(
                child: Text(
                  persian
                      ? 'مشاهده جزئیات و تایم‌لاین'
                      : 'View details and timeline',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Icon(
                persian
                    ? Icons.arrow_back_rounded
                    : Icons.arrow_forward_rounded,
                color: stateColor,
                size: 20,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

final class _JournalDetailHero extends StatelessWidget {
  const _JournalDetailHero({required this.projection, required this.persian});

  final TradingJournalProjection projection;
  final bool persian;

  @override
  Widget build(BuildContext context) {
    final stateColor = _tradeStateColor(context, projection.state);
    final net = projection.netPnl;
    final scheme = Theme.of(context).colorScheme;
    return SectionCard(
      accentColor: stateColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SymbolAvatar(symbol: projection.symbol, size: 58),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      projection.symbol,
                      textDirection: TextDirection.ltr,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${projection.strategy} · ${projection.timeframe} · ${projection.direction.name.toUpperCase()}',
                      textDirection: TextDirection.ltr,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              StatusPill(
                label: _tradeStateLabel(persian, projection.state),
                color: stateColor,
                icon: _tradeStateIcon(projection.state),
              ),
            ],
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 620 ? 3 : 1;
              const gap = 10.0;
              final width =
                  (constraints.maxWidth - gap * (columns - 1)) / columns;
              final metrics = [
                (
                  persian ? 'سود/زیان خالص' : 'Net PnL',
                  net == null
                      ? projection.economicsPending
                            ? (persian
                                  ? 'تطبیق PnL در انتظار'
                                  : 'PnL reconciliation pending')
                            : (persian ? 'ناموجود' : 'Unavailable')
                      : '${net >= 0 ? '+' : ''}${QuantaraNumberFormat.marketValue(net, unit: 'USDT')}',
                  Icons.account_balance_wallet_outlined,
                  net == null
                      ? scheme.onSurfaceVariant
                      : net >= 0
                      ? QuantaraColors.success
                      : QuantaraColors.danger,
                ),
                (
                  'R',
                  projection.realizedR?.toStringAsFixed(2) ??
                      (persian ? 'ناموجود' : 'Unavailable'),
                  Icons.balance_rounded,
                  projection.realizedR == null
                      ? scheme.onSurfaceVariant
                      : projection.realizedR! >= 0
                      ? QuantaraColors.success
                      : QuantaraColors.danger,
                ),
                (
                  persian ? 'بالاترین تارگت' : 'Highest target',
                  projection.highestTargetReached > 0
                      ? 'TP${projection.highestTargetReached}'
                      : '—',
                  Icons.flag_outlined,
                  projection.highestTargetReached > 0
                      ? QuantaraColors.success
                      : scheme.onSurfaceVariant,
                ),
              ];
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final metric in metrics)
                    SizedBox(
                      width: width,
                      child: FinanceMetricPanel(
                        label: metric.$1,
                        value: metric.$2,
                        icon: metric.$3,
                        color: metric.$4,
                      ),
                    ),
                ],
              );
            },
          ),
        ],
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
    final items = <(String, String, IconData, Color)>[
      (
        persian ? 'قیمت ورود' : 'Entry price',
        projection.entryPrice == null
            ? (persian ? 'ناموجود' : 'Unavailable')
            : QuantaraNumberFormat.marketValue(projection.entryPrice!),
        Icons.login_rounded,
        QuantaraColors.cyan,
      ),
      (
        persian ? 'کارمزد' : 'Fees',
        projection.fees == null
            ? (persian ? 'ناموجود' : 'Unavailable')
            : QuantaraNumberFormat.marketValue(projection.fees!, unit: 'USDT'),
        Icons.receipt_long_outlined,
        QuantaraColors.warning,
      ),
      (
        persian ? 'فاندینگ' : 'Funding',
        projection.funding == null
            ? (persian ? 'ناموجود' : 'Unavailable')
            : QuantaraNumberFormat.marketValue(
                projection.funding!,
                unit: 'USDT',
              ),
        Icons.currency_exchange_rounded,
        QuantaraColors.violet,
      ),
      (
        persian ? 'بازده مارجین' : 'Margin return',
        projection.returnOnMarginPercent == null
            ? (persian ? 'ناموجود' : 'Unavailable')
            : '${projection.returnOnMarginPercent!.toStringAsFixed(2)}%',
        Icons.percent_rounded,
        projection.returnOnMarginPercent == null
            ? Theme.of(context).colorScheme.onSurfaceVariant
            : projection.returnOnMarginPercent! >= 0
            ? QuantaraColors.success
            : QuantaraColors.danger,
      ),
      (
        persian ? 'حرکت قیمت' : 'Price move',
        projection.priceMovePercent == null
            ? (persian ? 'ناموجود' : 'Unavailable')
            : '${projection.priceMovePercent!.toStringAsFixed(2)}%',
        Icons.show_chart_rounded,
        projection.priceMovePercent == null
            ? Theme.of(context).colorScheme.onSurfaceVariant
            : projection.priceMovePercent! >= 0
            ? QuantaraColors.success
            : QuantaraColors.danger,
      ),
      (
        persian ? 'دلیل خروج' : 'Close reason',
        _closeReasonLabel(persian, projection.closeReason),
        Icons.logout_rounded,
        _closeReasonColor(context, projection.closeReason),
      ),
    ];
    return SectionCard(
      accentColor: QuantaraColors.cyan,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeading(
            title: persian ? 'جزئیات نتیجه' : 'Result details',
            subtitle: persian
                ? 'اعداد تأییدشده و محاسبات قابل‌ردیابی این پوزیشن'
                : 'Confirmed values and attributable calculations for this position',
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 780
                  ? 3
                  : constraints.maxWidth >= 480
                  ? 2
                  : 1;
              const gap = 10.0;
              final width =
                  (constraints.maxWidth - gap * (columns - 1)) / columns;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final item in items)
                    SizedBox(
                      width: width,
                      child: FinanceMetricPanel(
                        label: item.$1,
                        value: item.$2,
                        icon: item.$3,
                        color: item.$4,
                      ),
                    ),
                ],
              );
            },
          ),
          if (projection.warning != null) ...[
            const SizedBox(height: 12),
            _StateCard(
              icon: Icons.warning_amber_rounded,
              title: persian ? 'هشدار این رکورد' : 'Record warning',
              message: projection.warning!,
              compact: true,
              color: QuantaraColors.warning,
            ),
          ],
        ],
      ),
    );
  }
}

final class _TradeEvidencePanel extends StatelessWidget {
  const _TradeEvidencePanel({required this.projection, required this.persian});

  final TradingJournalProjection projection;
  final bool persian;

  @override
  Widget build(BuildContext context) {
    final plan = projection.plan;
    if (plan == null) return const SizedBox.shrink();
    final stopDistance = plan.plannedEntry <= 0
        ? null
        : (plan.plannedEntry - plan.originalStopLoss).abs() /
              plan.plannedEntry *
              100;
    final whyEntered = <String>[
      if (plan.rationale.trim().isNotEmpty) plan.rationale,
      ...plan.confluence.where((item) => item.trim().isNotEmpty),
    ];
    final whyExited = projection.economicsPending
        ? (persian
              ? 'صرافی بسته‌شدن پوزیشن را تأیید کرده است؛ جزئیات مالی هنوز در حال تطبیق هستند.'
              : 'The exchange confirmed the position is closed; economics are still reconciling.')
        : projection.state == TradingJournalTradeState.closed
        ? (persian
              ? 'خروج ثبت‌شده: ${_closeReasonLabel(true, projection.closeReason)}.'
              : 'Recorded exit: ${_closeReasonLabel(false, projection.closeReason)}.')
        : (persian
              ? 'هنوز خروج نهایی ثبت نشده است.'
              : 'No final exit is recorded yet.');
    final review = stopDistance == null
        ? (persian
              ? 'فاصله استاپ اولیه قابل محاسبه نیست.'
              : 'Initial stop distance cannot be calculated.')
        : (persian
              ? 'استاپ اولیه ${stopDistance.toStringAsFixed(3)}٪ از ورود برنامه‌ریزی‌شده فاصله داشته است. برای قضاوت درباره مناسب‌بودن آن به نمونه کافی و داده ATR نیاز است.'
              : 'The initial stop was ${stopDistance.toStringAsFixed(3)}% from planned entry. Judging whether it was appropriate requires enough samples and captured ATR data.');

    Widget facts(String title, List<String> lines, Color color) => SectionCard(
      accentColor: color,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          for (final line in lines) ...[
            Text('• $line'),
            const SizedBox(height: 4),
          ],
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeading(
          title: persian ? 'شواهد معامله' : 'Trade evidence',
          subtitle: persian
              ? 'واقعیت‌های تصمیم، اجرا و نتیجه؛ بدون نتیجه‌گیری بدون داده'
              : 'Decision, execution and outcome facts without unsupported claims',
        ),
        const SizedBox(height: 12),
        facts(persian ? 'پلن و اجرا' : 'Plan & execution', [
          'setup ${plan.setupId}',
          '${plan.strategy} · v${plan.strategyRulesVersion} · ${plan.timeframe}',
          'regime ${plan.regime} · confidence ${plan.confidencePercent.toStringAsFixed(0)}%',
          'entry ${plan.plannedEntry} · SL ${plan.originalStopLoss} · targets ${plan.targets.join(', ')}',
          'risk ${plan.riskBudget.toStringAsFixed(4)} USDT · ${plan.leverage}x · margin ${plan.expectedMargin.toStringAsFixed(4)} USDT',
        ], QuantaraColors.cyan),
        const SizedBox(height: 10),
        facts(
          persian ? 'چرا وارد شد؟' : 'Why entered?',
          whyEntered.isEmpty
              ? [
                  persian
                      ? 'دلیل ثبت‌شده‌ای موجود نیست.'
                      : 'No persisted entry reason is available.',
                ]
              : whyEntered,
          QuantaraColors.violet,
        ),
        const SizedBox(height: 10),
        facts(
          persian ? 'چرا خارج شد؟' : 'Why exited?',
          [whyExited],
          _closeReasonColor(context, projection.closeReason),
        ),
        const SizedBox(height: 10),
        facts(
          persian ? 'چه چیزی باید بررسی شود؟' : 'What to review?',
          [
            review,
            persian
                ? 'ATR/EMA/ADX/DMI در این نسخه داخل مرز ژورنال ذخیره نشده‌اند؛ برای این معامله عددی جعل نمی‌شود.'
                : 'ATR/EMA/ADX/DMI were not persisted at this journal boundary; no values are fabricated for this trade.',
          ],
          QuantaraColors.warning,
        ),
        const SizedBox(height: 10),
        facts(
          persian ? 'کیفیت داده' : 'Data quality',
          [
            'integrity ${projection.integrity.name}',
            'passed gates ${plan.passedGates.join(', ')}',
            if (plan.blockedGates.isNotEmpty)
              'blocked gates ${plan.blockedGates.join(', ')}',
            if (projection.warning != null) projection.warning!,
          ],
          projection.integrity == TradingJournalIntegrity.unverified
              ? QuantaraColors.warning
              : QuantaraColors.success,
        ),
      ],
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
    final color = _factQualityColor(context, event.quality);
    final details = <String>[
      if (event.quantity != null) 'qty ${event.quantity}',
      if (event.price != null) '@ ${event.price}',
      if (event.grossPnl != null) 'PnL ${event.grossPnl}',
      if (event.fee != null) 'fee ${event.fee}',
      if (event.funding != null) 'funding ${event.funding}',
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
            width: 32,
            child: Column(
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Theme.of(context).colorScheme.surface,
                      width: 3,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: color.withValues(alpha: 0.26),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                  child: const SizedBox.square(dimension: 16),
                ),
                if (!last)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            color.withValues(alpha: 0.65),
                            Theme.of(context).colorScheme.outline,
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: SectionCard(
                accentColor: color,
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.13),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: SizedBox.square(
                            dimension: 34,
                            child: Icon(
                              _eventIcon(event.type),
                              color: color,
                              size: 19,
                            ),
                          ),
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: Theme.of(context).textTheme.titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w900),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                _formatDate(event.occurredAt),
                                textDirection: TextDirection.ltr,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                              ),
                            ],
                          ),
                        ),
                        StatusPill(
                          label: _factQualityLabel(persian, event.quality),
                          color: color,
                        ),
                      ],
                    ),
                    if (details.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        details.join(' · '),
                        textDirection: TextDirection.ltr,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

final class _StateCard extends StatelessWidget {
  const _StateCard({
    required this.icon,
    required this.title,
    required this.message,
    this.compact = false,
    this.loading = false,
    this.color,
  });

  final IconData icon;
  final String title;
  final String message;
  final bool compact;
  final bool loading;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final accent = color ?? Theme.of(context).colorScheme.primary;
    return SectionCard(
      accentColor: accent,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: compact ? 0 : 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.13),
                borderRadius: BorderRadius.circular(13),
              ),
              child: SizedBox.square(
                dimension: compact ? 40 : 48,
                child: loading
                    ? Padding(
                        padding: const EdgeInsets.all(11),
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: accent,
                        ),
                      )
                    : Icon(icon, color: accent),
              ),
            ),
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

Color _tradeStateColor(BuildContext context, TradingJournalTradeState state) =>
    switch (state) {
      TradingJournalTradeState.planned => QuantaraColors.violet,
      TradingJournalTradeState.open => QuantaraColors.cyan,
      TradingJournalTradeState.closed => QuantaraColors.electricBlue,
      TradingJournalTradeState.missed => QuantaraColors.warning,
      TradingJournalTradeState.simulated => QuantaraColors.electricBlue,
      TradingJournalTradeState.unverified => Theme.of(
        context,
      ).colorScheme.error,
    };

String _tradeStateLabel(
  bool persian,
  TradingJournalTradeState state,
) => switch (state) {
  TradingJournalTradeState.planned => persian ? 'برنامه‌ریزی‌شده' : 'Planned',
  TradingJournalTradeState.open => persian ? 'باز' : 'Active',
  TradingJournalTradeState.closed => persian ? 'بسته‌شده' : 'Closed',
  TradingJournalTradeState.missed => persian ? 'از دست‌رفته' : 'Missed',
  TradingJournalTradeState.simulated => persian ? 'شبیه‌سازی' : 'Simulated',
  TradingJournalTradeState.unverified => persian ? 'تأییدنشده' : 'Unverified',
};

IconData _tradeStateIcon(TradingJournalTradeState state) => switch (state) {
  TradingJournalTradeState.planned => Icons.event_note_outlined,
  TradingJournalTradeState.open => Icons.play_circle_outline_rounded,
  TradingJournalTradeState.closed => Icons.check_circle_outline_rounded,
  TradingJournalTradeState.missed => Icons.timer_off_outlined,
  TradingJournalTradeState.simulated => Icons.science_outlined,
  TradingJournalTradeState.unverified => Icons.gpp_bad_outlined,
};

Color _factQualityColor(
  BuildContext context,
  TradingJournalFactQuality quality,
) => switch (quality) {
  TradingJournalFactQuality.confirmed => QuantaraColors.cyan,
  TradingJournalFactQuality.calculated => QuantaraColors.violet,
  TradingJournalFactQuality.userEntered => QuantaraColors.electricBlue,
  TradingJournalFactQuality.stale => QuantaraColors.warning,
  TradingJournalFactQuality.unverified => Theme.of(context).colorScheme.error,
};

String _factQualityLabel(bool persian, TradingJournalFactQuality quality) =>
    switch (quality) {
      TradingJournalFactQuality.confirmed => persian ? 'تأیید' : 'Confirmed',
      TradingJournalFactQuality.calculated => persian ? 'محاسبه' : 'Calculated',
      TradingJournalFactQuality.userEntered => persian ? 'کاربر' : 'User',
      TradingJournalFactQuality.stale => persian ? 'قدیمی' : 'Stale',
      TradingJournalFactQuality.unverified =>
        persian ? 'تأییدنشده' : 'Unverified',
    };

Color _closeReasonColor(
  BuildContext context,
  TradingJournalCloseReason? reason,
) => switch (reason) {
  TradingJournalCloseReason.takeProfit1 ||
  TradingJournalCloseReason.takeProfit2 ||
  TradingJournalCloseReason.takeProfit3 => QuantaraColors.success,
  TradingJournalCloseReason.stop ||
  TradingJournalCloseReason.liquidation => QuantaraColors.danger,
  TradingJournalCloseReason.emergency => QuantaraColors.warning,
  _ => Theme.of(context).colorScheme.onSurfaceVariant,
};

String _closeReasonLabel(bool persian, TradingJournalCloseReason? reason) {
  if (reason == null) return persian ? 'باز' : 'Open';
  return switch (reason) {
    TradingJournalCloseReason.takeProfit1 => 'TP1',
    TradingJournalCloseReason.takeProfit2 => 'TP2',
    TradingJournalCloseReason.takeProfit3 => 'TP3',
    TradingJournalCloseReason.stop => persian ? 'حد ضرر' : 'Stop loss',
    TradingJournalCloseReason.breakEven => persian ? 'سربه‌سر' : 'Break-even',
    TradingJournalCloseReason.runner => persian ? 'رانر' : 'Runner',
    TradingJournalCloseReason.emergency => persian ? 'اضطراری' : 'Emergency',
    TradingJournalCloseReason.manual => persian ? 'دستی' : 'Manual',
    TradingJournalCloseReason.exchange => persian ? 'صرافی' : 'Exchange',
    TradingJournalCloseReason.liquidation =>
      persian ? 'لیکویید' : 'Liquidation',
    TradingJournalCloseReason.expired => persian ? 'منقضی' : 'Expired',
    TradingJournalCloseReason.notTaken => persian ? 'گرفته‌نشده' : 'Not taken',
    TradingJournalCloseReason.unknown => persian ? 'نامشخص' : 'Unknown',
  };
}

String _eventTitle(TradingJournalEventType type, bool persian) =>
    switch (type) {
      TradingJournalEventType.signalCreated =>
        persian ? 'Signal · ایجاد سیگنال' : 'Signal · Created',
      TradingJournalEventType.signalUpdated =>
        persian ? 'Signal · به‌روزرسانی' : 'Signal · Updated',
      TradingJournalEventType.signalExpired =>
        persian ? 'Signal · انقضا' : 'Signal · Expired',
      TradingJournalEventType.entrySubmitted =>
        persian ? 'Entry · ارسال ورود' : 'Entry · Submitted',
      TradingJournalEventType.entryPartiallyFilled =>
        persian ? 'Entry · پرشدن جزئی' : 'Entry · Partially filled',
      TradingJournalEventType.entryFilled =>
        persian ? 'Entry · ورود انجام شد' : 'Entry · Filled',
      TradingJournalEventType.entryCancelled =>
        persian ? 'Entry · لغو ورود' : 'Entry · Cancelled',
      TradingJournalEventType.entryRejected =>
        persian ? 'Entry · رد ورود' : 'Entry · Rejected',
      TradingJournalEventType.stopSubmitted =>
        persian ? 'Stop · ارسال حفاظت' : 'Stop · Submitted',
      TradingJournalEventType.stopConfirmed =>
        persian ? 'Stop · تأیید حفاظت' : 'Stop · Confirmed',
      TradingJournalEventType.stopRejected =>
        persian ? 'Stop · رد حفاظت' : 'Stop · Rejected',
      TradingJournalEventType.takeProfitSubmitted =>
        persian ? 'TP · ارسال تارگت' : 'TP · Submitted',
      TradingJournalEventType.takeProfitConfirmed =>
        persian ? 'TP · تأیید تارگت' : 'TP · Confirmed',
      TradingJournalEventType.takeProfitFilled =>
        persian ? 'TP · تارگت انجام شد' : 'TP · Filled',
      TradingJournalEventType.stopMoveRequested =>
        persian ? 'Stop · درخواست جابه‌جایی' : 'Stop · Move requested',
      TradingJournalEventType.stopMoveConfirmed =>
        persian ? 'Stop · جابه‌جایی تأیید شد' : 'Stop · Move confirmed',
      TradingJournalEventType.stopMoveRejected =>
        persian ? 'Stop · جابه‌جایی رد شد' : 'Stop · Move rejected',
      TradingJournalEventType.serviceStopped =>
        persian ? 'System · سرویس متوقف شد' : 'System · Service stopped',
      TradingJournalEventType.staleDetected =>
        persian ? 'Safety · داده قدیمی' : 'Safety · Stale data',
      TradingJournalEventType.reconciliationStarted =>
        persian ? 'Sync · شروع تطبیق' : 'Sync · Reconciliation started',
      TradingJournalEventType.reconciliationRecovered =>
        persian ? 'Sync · تطبیق بازیابی شد' : 'Sync · Recovered',
      TradingJournalEventType.appRestarted =>
        persian ? 'System · اجرای دوباره اپ' : 'System · App restarted',
      TradingJournalEventType.fundingApplied =>
        persian ? 'Cost · فاندینگ اعمال شد' : 'Cost · Funding applied',
      TradingJournalEventType.positionPartiallyClosed =>
        persian ? 'Close · خروج جزئی' : 'Close · Partial',
      TradingJournalEventType.positionClosed =>
        persian ? 'Close · پوزیشن بسته شد' : 'Close · Position closed',
      TradingJournalEventType.liquidation =>
        persian ? 'Close · لیکویید' : 'Close · Liquidation',
      TradingJournalEventType.manualNote =>
        persian ? 'Note · یادداشت دستی' : 'Note · Manual',
      TradingJournalEventType.counterfactualResolved =>
        persian ? 'Outcome · نتیجه فرضی' : 'Outcome · Counterfactual resolved',
    };

IconData _eventIcon(TradingJournalEventType type) => switch (type) {
  TradingJournalEventType.signalCreated ||
  TradingJournalEventType.signalUpdated ||
  TradingJournalEventType.signalExpired => Icons.radar_rounded,
  TradingJournalEventType.entrySubmitted ||
  TradingJournalEventType.entryPartiallyFilled ||
  TradingJournalEventType.entryFilled ||
  TradingJournalEventType.entryCancelled ||
  TradingJournalEventType.entryRejected => Icons.login_rounded,
  TradingJournalEventType.stopSubmitted ||
  TradingJournalEventType.stopConfirmed ||
  TradingJournalEventType.stopRejected ||
  TradingJournalEventType.stopMoveRequested ||
  TradingJournalEventType.stopMoveConfirmed ||
  TradingJournalEventType.stopMoveRejected => Icons.shield_outlined,
  TradingJournalEventType.takeProfitSubmitted ||
  TradingJournalEventType.takeProfitConfirmed ||
  TradingJournalEventType.takeProfitFilled => Icons.flag_outlined,
  TradingJournalEventType.serviceStopped ||
  TradingJournalEventType.appRestarted => Icons.settings_backup_restore_rounded,
  TradingJournalEventType.staleDetected => Icons.warning_amber_rounded,
  TradingJournalEventType.reconciliationStarted ||
  TradingJournalEventType.reconciliationRecovered => Icons.sync_rounded,
  TradingJournalEventType.fundingApplied => Icons.currency_exchange_rounded,
  TradingJournalEventType.positionPartiallyClosed ||
  TradingJournalEventType.positionClosed ||
  TradingJournalEventType.liquidation => Icons.logout_rounded,
  TradingJournalEventType.manualNote => Icons.edit_note_rounded,
  TradingJournalEventType.counterfactualResolved => Icons.query_stats_rounded,
};

String _formatHoldingDuration(Duration value) {
  final hours = value.inHours;
  final minutes = value.inMinutes.remainder(60);
  if (hours > 0) return '${hours}h ${minutes}m';
  if (value.inMinutes > 0) return '${value.inMinutes}m';
  return '${value.inSeconds}s';
}

String _formatDate(DateTime value) {
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${local.year}/${two(local.month)}/${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
}

class _JournalLivePositionChart extends StatelessWidget {
  const _JournalLivePositionChart({
    required this.projection,
    required this.analysis,
    required this.currentIdea,
    required this.persian,
  });

  final TradingJournalProjection projection;
  final TimeframeChartAnalysis? analysis;
  final TradeIdea? currentIdea;
  final bool persian;

  @override
  Widget build(BuildContext context) {
    final plan = projection.plan;
    if (plan == null) {
      return SectionCard(
        accentColor: QuantaraColors.warning,
        child: Text(
          persian
              ? 'برای این رکورد پلن تصمیم‌گیری قابل اتکا ثبت نشده است؛ نمودار زنده چیزی را حدس نمی‌زند.'
              : 'No attributable decision plan is stored for this record; the live chart will not invent one.',
        ),
      );
    }

    final live = analysis;
    if (live == null) {
      return SectionCard(
        accentColor: QuantaraColors.warning,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeading(
              title: persian ? 'نمودار پوزیشن' : 'Position chart',
              subtitle: persian
                  ? 'پلن ورود ثابت مانده؛ داده زنده این نماد/تایم‌فریم فعلاً در اسنپ‌شات بازار موجود نیست.'
                  : 'The entry plan remains frozen; live market data for this symbol/timeframe is not currently available.',
            ),
            const SizedBox(height: 10),
            Text(
              '${persian ? 'ورود' : 'Entry'} ${QuantaraNumberFormat.marketValue(projection.entryPrice ?? plan.plannedEntry)}  ·  '
              'SL ${QuantaraNumberFormat.marketValue(plan.originalStopLoss)}',
              textDirection: TextDirection.ltr,
            ),
          ],
        ),
      );
    }

    final frozenLong = plan.direction == TradingJournalDirection.long;
    final frozenShort = plan.direction == TradingJournalDirection.short;
    final actionableCurrent = currentIdea?.isActionable == true;
    final directionFlipped =
        actionableCurrent &&
        ((currentIdea!.direction == TradeDirection.long && frozenShort) ||
            (currentIdea!.direction == TradeDirection.short && frozenLong));
    final activeTargets = plan.targets
        .where((target) => target.isFinite && target > 0)
        .toList(growable: false);
    final validOverlay =
        (frozenLong || frozenShort) &&
        plan.originalStopLoss.isFinite &&
        plan.originalStopLoss > 0 &&
        (projection.entryPrice ?? plan.plannedEntry).isFinite &&
        (projection.entryPrice ?? plan.plannedEntry) > 0 &&
        activeTargets.isNotEmpty;
    final overlay = validOverlay
        ? ChartTradeOverlay(
            entry: projection.entryPrice ?? plan.plannedEntry,
            stop: plan.originalStopLoss,
            targets: activeTargets,
            isLong: frozenLong,
          )
        : null;
    final scheme = Theme.of(context).colorScheme;
    final currentPrice = live.latestCandle.close;
    final referenceLevels = <({String label, double value})>[
      for (final item in const [
        ('Donchian H20', 'previousDonchianHigh20'),
        ('Donchian L20', 'previousDonchianLow20'),
        ('Swing H', 'recentSwingHigh'),
        ('Swing L', 'recentSwingLow'),
        ('BB Upper', 'bollingerUpper20'),
        ('BB Lower', 'bollingerLower20'),
        ('EMA20', 'ema20'),
        ('EMA50', 'ema50'),
        ('EMA200', 'ema200'),
      ])
        if (plan.indicatorSnapshot[item.$2] case final value?)
          (label: item.$1, value: value),
    ];

    String zoneRole(ChartZoneRole role) => switch (role) {
      ChartZoneRole.support => persian ? 'حمایت زنده' : 'Live support',
      ChartZoneRole.resistance => persian ? 'مقاومت زنده' : 'Live resistance',
      ChartZoneRole.pivot => persian ? 'پیوت زنده' : 'Live pivot',
    };

    return SectionCard(
      accentColor: QuantaraColors.cyan,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeading(
            title: persian ? 'نمودار زنده پوزیشن' : 'Live position chart',
            subtitle: persian
                ? 'کندل‌ها و نواحی، زنده‌اند؛ Entry / SL / TP از پلن تغییرناپذیر لحظه ورود می‌آیند.'
                : 'Candles and zones are live; Entry / SL / TP come from the immutable decision-time plan.',
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Chip(
                avatar: const Icon(Icons.show_chart_rounded, size: 17),
                label: Text(
                  '${persian ? 'قیمت فعلی' : 'Current'} ${QuantaraNumberFormat.marketValue(currentPrice)}',
                ),
              ),
              Chip(
                avatar: const Icon(Icons.lock_clock_rounded, size: 17),
                label: Text(
                  persian
                      ? 'پلن ورود: ${plan.direction.name.toUpperCase()} · ${projection.timeframe}'
                      : 'Frozen entry: ${plan.direction.name.toUpperCase()} · ${projection.timeframe}',
                ),
              ),
              if (live.timeframe.trim() != projection.timeframe.trim())
                Chip(
                  avatar: const Icon(Icons.swap_horiz_rounded, size: 17),
                  label: Text(
                    persian
                        ? 'کانتکست زنده: ${live.timeframe} · پلن تاریخی بازنویسی نشده'
                        : 'Live context: ${live.timeframe} · historical plan unchanged',
                  ),
                ),
              if (currentIdea != null)
                Chip(
                  avatar: const Icon(Icons.radar_rounded, size: 17),
                  label: Text(
                    persian
                        ? 'تحلیل فعلی: ${currentIdea!.direction.name.toUpperCase()}'
                        : 'Current setup: ${currentIdea!.direction.name.toUpperCase()}',
                  ),
                ),
            ],
          ),
          if (directionFlipped) ...[
            const SizedBox(height: 12),
            DecoratedBox(
              decoration: BoxDecoration(
                color: QuantaraColors.warning.withValues(alpha: 0.10),
                border: Border.all(
                  color: QuantaraColors.warning.withValues(alpha: 0.45),
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.compare_arrows_rounded,
                      color: QuantaraColors.warning,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        persian
                            ? 'تحلیل بازار از زمان ورود تغییر جهت داده است. این پوزیشن متعلق به پلن ثابت ${plan.direction.name.toUpperCase()} زمان ورود است و با SL/TP صرافی مدیریت می‌شود؛ سیگنال جدید به‌تنهایی باعث معکوس‌کردن پوزیشن نمی‌شود.'
                            : 'Market analysis has changed direction since entry. This position still belongs to the frozen ${plan.direction.name.toUpperCase()} entry plan and remains managed by its exchange SL/TP; a newer signal does not auto-reverse it.',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.18),
              ),
              child: TradingViewLightweightChart(
                analysis: live,
                idea: currentIdea,
                tradeOverlay: overlay,
                height: 360,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            persian ? 'نواحی فعلی بازار' : 'Current market zones',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final zone in live.strongestZones)
                Chip(
                  label: Text(
                    '${zoneRole(zone.role)}  '
                    '${QuantaraNumberFormat.marketValue(zone.lower)}–${QuantaraNumberFormat.marketValue(zone.upper)}',
                  ),
                ),
            ],
          ),
          if (referenceLevels.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              persian
                  ? 'سطوح ثبت‌شده در لحظه تصمیم (فریز شده)'
                  : 'Captured decision-time levels (frozen)',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final level in referenceLevels)
                  Chip(
                    avatar: const Icon(
                      Icons.history_toggle_off_rounded,
                      size: 16,
                    ),
                    label: Text(
                      '${level.label} ${QuantaraNumberFormat.marketValue(level.value)}',
                    ),
                  ),
              ],
            ),
          ],
          if (plan.confluence.isNotEmpty ||
              plan.rationale.trim().isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              persian ? 'چرا این پوزیشن باز شد؟' : 'Why was this trade opened?',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            if (plan.rationale.trim().isNotEmpty) Text(plan.rationale),
            if (plan.confluence.isNotEmpty) ...[
              const SizedBox(height: 8),
              for (final reason in plan.confluence)
                Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 3),
                        child: Icon(
                          Icons.check_circle_outline_rounded,
                          size: 16,
                          color: QuantaraColors.success,
                        ),
                      ),
                      const SizedBox(width: 7),
                      Expanded(child: Text(reason)),
                    ],
                  ),
                ),
            ],
            if (plan.invalidation.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                '${persian ? 'ابطال پلن' : 'Invalidation'}: ${plan.invalidation}',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
