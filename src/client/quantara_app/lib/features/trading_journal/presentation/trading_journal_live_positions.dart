import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/formatting/number_formatters.dart';
import '../../../core/theme/quantara_theme.dart';
import '../../../core/widgets/quantara_ui.dart';
import '../../market_analysis/application/live_trade_context_registry.dart';
import '../../market_analysis/presentation/quantara_candlestick_chart.dart';
import '../../owner_alpha/domain/owner_alpha_models.dart';
import '../domain/trading_journal_models.dart';
import '../domain/trading_journal_projection.dart';

@visibleForTesting
bool tradingJournalDirectionsOppose(
  TradingJournalDirection frozen,
  TradeDirection current,
) =>
    (frozen == TradingJournalDirection.long && current == TradeDirection.short) ||
    (frozen == TradingJournalDirection.short && current == TradeDirection.long);

class TradingJournalLivePositionsPanel extends StatelessWidget {
  const TradingJournalLivePositionsPanel({
    required this.locale,
    required this.projections,
    super.key,
  });

  final Locale locale;
  final List<TradingJournalProjection> projections;

  @override
  Widget build(BuildContext context) {
    final openLocalLive = projections
        .where(
          (item) =>
              item.state == TradingJournalTradeState.open &&
              item.source == TradingJournalSource.localLive &&
              item.plan != null,
        )
        .toList(growable: false);
    if (openLocalLive.isEmpty) return const SizedBox.shrink();
    final persian = locale.languageCode != 'en';

    return ValueListenableBuilder<Map<String, LiveTradeContext>>(
      valueListenable: LiveTradeContextRegistry.listenable,
      builder: (context, _, __) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeading(
            title: persian ? 'پوزیشن‌های زنده در ژورنال' : 'Live journal positions',
            subtitle: persian
                ? 'پلن فریز‌شده زمان ورود روی داده فعلی بازار؛ بدون تغییر خودکار پوزیشن'
                : 'The frozen entry-time plan over current market data; no automatic position reversal',
          ),
          const SizedBox(height: 12),
          for (var index = 0; index < openLocalLive.length; index++) ...[
            _LivePositionCard(
              projection: openLocalLive[index],
              persian: persian,
            ),
            if (index != openLocalLive.length - 1) const SizedBox(height: 12),
          ],
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _LivePositionCard extends StatelessWidget {
  const _LivePositionCard({required this.projection, required this.persian});

  final TradingJournalProjection projection;
  final bool persian;

  @override
  Widget build(BuildContext context) {
    final plan = projection.plan!;
    final live = LiveTradeContextRegistry.find(
      symbol: projection.symbol,
      timeframe: projection.timeframe,
      strategy: plan.strategy,
    );
    final directionColor = projection.direction == TradingJournalDirection.long
        ? QuantaraColors.electricBlue
        : QuantaraColors.violet;

    if (live == null) {
      return SectionCard(
        accentColor: directionColor,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.candlestick_chart_rounded, color: directionColor),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${projection.symbol} · ${projection.timeframe} · ${_frozenDirectionLabel(projection.direction, persian)}',
                    textDirection: TextDirection.ltr,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    persian
                        ? 'پلن و دلایل ورود محفوظ هستند؛ داده عمومی زنده این نماد هنوز در این نشست آماده نشده است. با تازه‌شدن تحلیل بازار، چارت اینجا خودکار ظاهر می‌شود.'
                        : 'The frozen plan and entry evidence are preserved. Live public-market context is not ready in this session yet; the chart will appear automatically after market analysis refreshes.',
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final analysis = live.analysis;
    final currentIdea = live.idea;
    final currentPrice = analysis.latestCandle.close;
    final entryPrice = projection.entryPrice ?? plan.plannedEntry;
    final favorableMove = entryPrice <= 0
        ? 0.0
        : (currentPrice - entryPrice) /
              entryPrice *
              100 *
              (projection.direction == TradingJournalDirection.short ? -1 : 1);
    final opposite = currentIdea.isActionable &&
        tradingJournalDirectionsOppose(projection.direction, currentIdea.direction);
    final scheme = Theme.of(context).colorScheme;
    final currentDirectionColor = switch (currentIdea.direction) {
      TradeDirection.long => QuantaraColors.success,
      TradeDirection.short => QuantaraColors.danger,
      TradeDirection.wait => QuantaraColors.warning,
    };
    final referenceLevels = _decisionReferenceLevels(plan.indicatorSnapshot);

    return SectionCard(
      accentColor: opposite ? QuantaraColors.warning : directionColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final title = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${projection.symbol} · ${projection.timeframe}',
                    textDirection: TextDirection.ltr,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    persian
                        ? 'چارت زنده بازار با Entry / SL / TP فریز‌شده پوزیشن'
                        : 'Live market chart with the position’s frozen Entry / SL / TP',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              );
              final pills = Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  StatusPill(
                    label: persian
                        ? 'پلن ورود: ${_frozenDirectionLabel(projection.direction, true)} · فریز‌شده'
                        : 'Entry plan: ${_frozenDirectionLabel(projection.direction, false)} · Frozen setup',
                    color: directionColor,
                    icon: Icons.lock_clock_outlined,
                  ),
                  StatusPill(
                    label: persian
                        ? 'تحلیل فعلی: ${_currentDirectionLabel(currentIdea.direction, true)}'
                        : 'Current setup: ${_currentDirectionLabel(currentIdea.direction, false)}',
                    color: currentDirectionColor,
                    icon: Icons.radar_rounded,
                  ),
                ],
              );
              if (constraints.maxWidth < 620) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [title, const SizedBox(height: 12), pills],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: title),
                  const SizedBox(width: 16),
                  Flexible(child: pills),
                ],
              );
            },
          ),
          if (opposite) ...[
            const SizedBox(height: 12),
            DecoratedBox(
              decoration: BoxDecoration(
                color: QuantaraColors.warning.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: QuantaraColors.warning.withValues(alpha: 0.34),
                ),
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
                            ? 'تحلیل فعلی از زمان ورود عوض شده و اکنون جهت مخالف را پیشنهاد می‌کند. این پوزیشن همچنان متعلق به پلن فریز‌شده زمان ورود است و فقط با حفاظت تأییدشده صرافی مدیریت می‌شود؛ سیگنال جدید به‌تنهایی باعث بستن یا برعکس‌کردن خودکار پوزیشن نمی‌شود.'
                            : 'Current analysis has changed since entry and now points the opposite way. This open position still belongs to its frozen entry-time plan and remains managed by confirmed exchange protection; a later signal alone does not auto-close or reverse it.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
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
                color: scheme.surfaceContainerLowest,
                border: Border.all(
                  color: scheme.outline.withValues(alpha: 0.35),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: QuantaraCandlestickChart(
                  analysis: analysis,
                  tradeOverlay: ChartTradeOverlay(
                    entry: plan.plannedEntry,
                    stop: plan.originalStopLoss,
                    targets: plan.targets
                        .where((value) => value.isFinite && value > 0)
                        .toList(growable: false),
                    isLong:
                        projection.direction == TradingJournalDirection.long,
                  ),
                  height: 350,
                  visibleCandleCount: 64,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            persian
                ? 'ناحیه‌های حمایت/مقاومت روی چارت از تحلیل زنده فعلی هستند. Entry، SL و TP از پلن فریز‌شده ژورنال می‌آیند. سطوح مرجع زمان تصمیم جداگانه در پایین نمایش داده می‌شوند تا داده تاریخی با تحلیل جدید قاطی نشود.'
                : 'Support/resistance zones on the chart are from current live analysis. Entry, SL and TP come from the frozen Journal plan. Decision-time reference levels are listed separately below so historical evidence is not mixed with new analysis.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 760 ? 4 : 2;
              const gap = 8.0;
              final width =
                  (constraints.maxWidth - gap * (columns - 1)) / columns;
              final metrics = <(String, String, IconData, Color)>[
                (
                  persian ? 'قیمت فعلی' : 'Current price',
                  QuantaraNumberFormat.marketValue(currentPrice),
                  Icons.price_change_rounded,
                  QuantaraColors.cyan,
                ),
                (
                  persian ? 'ورود واقعی/پلن' : 'Entry',
                  QuantaraNumberFormat.marketValue(entryPrice),
                  Icons.login_rounded,
                  directionColor,
                ),
                (
                  persian ? 'حد ضرر اولیه' : 'Original stop',
                  QuantaraNumberFormat.marketValue(plan.originalStopLoss),
                  Icons.shield_outlined,
                  QuantaraColors.danger,
                ),
                (
                  persian ? 'حرکت به نفع پلن' : 'Move vs plan',
                  '${favorableMove >= 0 ? '+' : ''}${favorableMove.toStringAsFixed(2)}%',
                  Icons.show_chart_rounded,
                  favorableMove >= 0
                      ? QuantaraColors.success
                      : QuantaraColors.danger,
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
          if (referenceLevels.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              persian ? 'سطوح مرجع زمان تصمیم' : 'Decision-time reference levels',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final item in referenceLevels)
                  StatusPill(
                    label:
                        '${_referenceLabel(item.$1, persian)} ${QuantaraNumberFormat.marketValue(item.$2)}',
                    color: _referenceColor(item.$1),
                    icon: _referenceIcon(item.$1),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 14),
          Text(
            persian ? 'چرا این پوزیشن باز شد؟' : 'Why this position was opened',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 7),
          if (plan.rationale.trim().isNotEmpty) Text(plan.rationale),
          if (plan.confluence.isNotEmpty) ...[
            const SizedBox(height: 6),
            for (final reason in plan.confluence.take(5)) ...[
              Text('• $reason'),
              const SizedBox(height: 3),
            ],
          ],
          const SizedBox(height: 8),
          Text(
            '${persian ? 'آخرین دیتای چارت' : 'Chart data as of'}: ${_formatLiveTime(live.observedAt)}',
            textDirection: TextDirection.ltr,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

List<(String, double)> _decisionReferenceLevels(Map<String, double> snapshot) {
  const keys = [
    'recentSwingHigh',
    'recentSwingLow',
    'previousDonchianHigh20',
    'previousDonchianLow20',
    'bollingerUpper20',
    'bollingerMiddle20',
    'bollingerLower20',
  ];
  return [
    for (final key in keys)
      if (snapshot[key] case final value? when value.isFinite && value > 0)
        (key, value),
  ];
}

String _referenceLabel(String key, bool persian) => switch (key) {
  'recentSwingHigh' => persian ? 'سقف سویینگ' : 'Swing high',
  'recentSwingLow' => persian ? 'کف سویینگ' : 'Swing low',
  'previousDonchianHigh20' => persian ? 'دانچیان بالا' : 'Donchian high',
  'previousDonchianLow20' => persian ? 'دانچیان پایین' : 'Donchian low',
  'bollingerUpper20' => persian ? 'بولینگر بالا' : 'Bollinger upper',
  'bollingerMiddle20' => persian ? 'بولینگر میانی' : 'Bollinger middle',
  'bollingerLower20' => persian ? 'بولینگر پایین' : 'Bollinger lower',
  _ => key,
};

Color _referenceColor(String key) {
  if (key.contains('High') || key.contains('Upper')) {
    return QuantaraColors.danger;
  }
  if (key.contains('Low') || key.contains('Lower')) {
    return QuantaraColors.success;
  }
  return QuantaraColors.warning;
}

IconData _referenceIcon(String key) {
  if (key.contains('High') || key.contains('Upper')) {
    return Icons.vertical_align_top_rounded;
  }
  if (key.contains('Low') || key.contains('Lower')) {
    return Icons.vertical_align_bottom_rounded;
  }
  return Icons.horizontal_rule_rounded;
}

String _frozenDirectionLabel(TradingJournalDirection direction, bool persian) =>
    switch (direction) {
      TradingJournalDirection.long => persian ? 'لانگ' : 'LONG',
      TradingJournalDirection.short => persian ? 'شورت' : 'SHORT',
      TradingJournalDirection.wait => persian ? 'انتظار' : 'WAIT',
    };

String _currentDirectionLabel(TradeDirection direction, bool persian) =>
    switch (direction) {
      TradeDirection.long => persian ? 'لانگ' : 'LONG',
      TradeDirection.short => persian ? 'شورت' : 'SHORT',
      TradeDirection.wait => persian ? 'بدون ورود' : 'WAIT',
    };

String _formatLiveTime(DateTime value) {
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${local.year}/${two(local.month)}/${two(local.day)} ${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
}
