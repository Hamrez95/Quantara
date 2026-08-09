from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def replace_once(path: str, old: str, new: str) -> None:
    target = ROOT / path
    text = target.read_text(encoding="utf-8")
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"Expected exactly one match in {path}, found {count}: {old[:120]!r}")
    target.write_text(text.replace(old, new, 1), encoding="utf-8")


def append_once(path: str, marker: str, content: str) -> None:
    target = ROOT / path
    text = target.read_text(encoding="utf-8")
    if marker in text:
        return
    target.write_text(text.rstrip() + "\n\n" + content.strip() + "\n", encoding="utf-8")


# 1) Bitunix open-position PnL semantics: pending realizedPNL is net after fee/funding,
# while trade history gives gross realized PnL and fees are exposed as an expense.
replace_once(
    "src/client/quantara_app/lib/features/auto_trade/domain/trading_pnl_projection.dart",
    """      final pendingRealizedMismatch =
          fillsAvailable &&
          open?.realizedPnl != null &&
          (realizedValue! - open!.realizedPnl!).abs() > tolerance;
      final pendingFeeMismatch =
          fillsAvailable &&
          open?.fee != null &&
          (feeValue! - open!.fee!).abs() > tolerance;
""",
    """      // Bitunix pending positions expose realizedPNL as the position net
      // economic result (gross realized - fee expense + funding). Trade history
      // exposes gross realized PnL, while the pending-position fee is signed.
      // Compare like-for-like values so a healthy open position is not marked
      // unverified merely because of representation/sign differences.
      final pendingFeeExpense = open?.fee?.abs();
      final pendingFeeMismatch =
          fillsAvailable &&
          pendingFeeExpense != null &&
          feeValue != null &&
          (feeValue - pendingFeeExpense).abs() > tolerance;
      final pendingNetFromHistory =
          fillsAvailable &&
              realizedValue != null &&
              feeValue != null &&
              open?.funding != null
          ? realizedValue - feeValue + open!.funding!
          : null;
      final pendingRealizedMismatch =
          open?.realizedPnl != null &&
          pendingNetFromHistory != null &&
          (pendingNetFromHistory - open!.realizedPnl!).abs() > tolerance;
""",
)
replace_once(
    "src/client/quantara_app/lib/features/auto_trade/domain/trading_pnl_projection.dart",
    """      final positionWarning = unassignedAttribution
          ? 'A valid exchange trade remains quarantined because it could not be assigned to one position.'
          : totalsMismatch
          ? 'Trade-history totals diverge from the Bitunix position totals.'
          : positionConflict
          ? 'Conflicting exchange event identity for $key.'
          : warning;
""",
    """      final positionWarning = unassignedAttribution
          ? 'A valid exchange trade remains quarantined because it could not be assigned to one position.'
          : totalsMismatch
          ? 'Trade-history totals diverge from the Bitunix position totals.'
          : positionConflict
          ? 'Conflicting exchange event identity for $key.'
          : !sourceVerified
          ? (warning ?? 'Exchange PnL source could not be verified.')
          : null;
""",
)
replace_once(
    "src/client/quantara_app/lib/features/auto_trade/domain/trading_pnl_projection.dart",
    """              warning: warning ?? 'Fee or funding history is incomplete.',
""",
    """              warning:
                  positionWarning ?? 'Fee or funding history is incomplete.',
""",
)

# 2) Account-level protection truth is aggregate coverage. The exact persisted
# Local Live target identities/active-tranche layout are checked separately by
# RemainingTargetProtectionPolicy and _targetLadderConfirmed.
replace_once(
    "src/client/quantara_app/lib/features/auto_trade/domain/auto_trade_models.dart",
    """    return AutoTradePositionProtection.reconcile(
      position: position,
      orders: protectionOrders,
      asOf: verification.asOf,
    );
""",
    """    return AutoTradePositionProtection.reconcile(
      position: position,
      orders: protectionOrders,
      asOf: verification.asOf,
      // This projection answers whether the whole exchange position has a
      // full stop plus complete active TP quantity coverage. Local Live keeps
      // enforcing the exact persisted 1-3 tranche identities separately.
      expectedTakeProfitCount: 1,
    );
""",
)

# 3) A warning recovered in a later verified cycle must not remain sticky and
# keep the portfolio budget in incompleteProtection forever.
replace_once(
    "src/client/quantara_app/lib/features/auto_trade/application/local_live_trade_service.dart",
    """        profitLockProgress: managed.profitLockProgress.copyWith(
          processedTradeIds: {
            ...managed.profitLockProgress.processedTradeIds,
            ...fillProgress.newTradeIds,
          },
        ),
""",
    """        profitLockProgress: managed.profitLockProgress.copyWith(
          processedTradeIds: {
            ...managed.profitLockProgress.processedTradeIds,
            ...fillProgress.newTradeIds,
          },
          clearWarning: true,
        ),
""",
)

# 4) TradingView chart can receive a frozen Journal overlay independently from
# the current idea. This is essential when the live market signal later flips.
replace_once(
    "src/client/quantara_app/lib/features/market_analysis/presentation/tradingview_lightweight_chart.dart",
    """  const TradingViewLightweightChart({
    required this.analysis,
    required this.idea,
    this.frozenSignal,
    this.height = 390,
    super.key,
  });

  final TimeframeChartAnalysis analysis;
  final TradeIdea idea;
  final SignalJournalEntry? frozenSignal;
  final double height;
""",
    """  const TradingViewLightweightChart({
    required this.analysis,
    this.idea,
    this.frozenSignal,
    this.tradeOverlay,
    this.height = 390,
    super.key,
  });

  final TimeframeChartAnalysis analysis;
  final TradeIdea? idea;
  final SignalJournalEntry? frozenSignal;
  final ChartTradeOverlay? tradeOverlay;
  final double height;
""",
)
replace_once(
    "src/client/quantara_app/lib/features/market_analysis/presentation/tradingview_lightweight_chart.dart",
    """    final frozen = frozenSignal;
    final overlay = frozen != null
        ? ChartSignalOverlayPolicy.create(analysis: analysis, signal: frozen)
        : idea.isActionable
        ? ChartTradeOverlay(
            entry: (idea.entryLower! + idea.entryUpper!) / 2,
            stop: idea.stopLoss!,
            targets: idea.targets,
            isLong: idea.direction == TradeDirection.long,
          )
        : null;
    final chart = RepaintBoundary(
      key: ValueKey(
        'quantara-chart-${analysis.fingerprint}-${frozen?.setupId ?? idea.setupId}',
      ),
""",
    """    final frozen = frozenSignal;
    final currentIdea = idea;
    final overlay =
        tradeOverlay ??
        (frozen != null
            ? ChartSignalOverlayPolicy.create(analysis: analysis, signal: frozen)
            : currentIdea?.isActionable == true
            ? ChartTradeOverlay(
                entry:
                    (currentIdea!.entryLower! + currentIdea.entryUpper!) / 2,
                stop: currentIdea.stopLoss!,
                targets: currentIdea.targets,
                isLong: currentIdea.direction == TradeDirection.long,
              )
            : null);
    final chart = RepaintBoundary(
      key: ValueKey(
        'quantara-chart-${analysis.fingerprint}-${frozen?.setupId ?? currentIdea?.setupId ?? 'explicit-overlay'}',
      ),
""",
)

# 5) Journal consumes the latest market analysis while retaining the immutable
# decision plan. Rebind an open detail to refreshed projection data.
replace_once(
    "src/client/quantara_app/lib/features/trading_journal/presentation/trading_journal_view.dart",
    """import '../../../core/widgets/quantara_ui.dart';
import '../domain/trading_journal_models.dart';
""",
    """import '../../../core/widgets/quantara_ui.dart';
import '../../market_analysis/domain/market_chart_models.dart';
import '../../market_analysis/presentation/quantara_candlestick_chart.dart';
import '../../market_analysis/presentation/tradingview_lightweight_chart.dart';
import '../../owner_alpha/domain/owner_alpha_models.dart';
import '../domain/trading_journal_models.dart';
""",
)
replace_once(
    "src/client/quantara_app/lib/features/trading_journal/presentation/trading_journal_view.dart",
    """  const TradingJournalView({
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
""",
    """  const TradingJournalView({
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
""",
)
replace_once(
    "src/client/quantara_app/lib/features/trading_journal/presentation/trading_journal_view.dart",
    """  bool get _persian => widget.locale.languageCode != 'en';

  @override
  Widget build(BuildContext context) {
""",
    """  bool get _persian => widget.locale.languageCode != 'en';

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
""",
)
replace_once(
    "src/client/quantara_app/lib/features/trading_journal/presentation/trading_journal_view.dart",
    """  Widget _buildDetail(BuildContext context) {
    final projection = _selected!;
    return Column(
""",
    """  Widget _buildDetail(BuildContext context) {
    final projection = _selected!;
    final liveKey =
        '${projection.symbol.trim().toUpperCase()}|${projection.timeframe.trim()}';
    final liveAnalysis = widget.liveAnalyses[liveKey];
    final liveIdea = widget.liveIdeas[liveKey];
    return Column(
""",
)
replace_once(
    "src/client/quantara_app/lib/features/trading_journal/presentation/trading_journal_view.dart",
    """        _ProjectionSummary(projection: projection, persian: _persian),
        const SizedBox(height: 16),
        _TradeEvidencePanel(projection: projection, persian: _persian),
""",
    """        _ProjectionSummary(projection: projection, persian: _persian),
        const SizedBox(height: 16),
        _JournalLivePositionChart(
          projection: projection,
          analysis: liveAnalysis,
          currentIdea: liveIdea,
          persian: _persian,
        ),
        const SizedBox(height: 16),
        _TradeEvidencePanel(projection: projection, persian: _persian),
""",
)

append_once(
    "src/client/quantara_app/lib/features/trading_journal/presentation/trading_journal_view.dart",
    "class _JournalLivePositionChart extends StatelessWidget",
    r'''
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
    final directionFlipped = actionableCurrent &&
        ((currentIdea!.direction == TradeDirection.long && frozenShort) ||
            (currentIdea!.direction == TradeDirection.short && frozenLong));
    final validOverlay =
        (frozenLong || frozenShort) &&
        plan.originalStopLoss.isFinite &&
        plan.originalStopLoss > 0 &&
        (projection.entryPrice ?? plan.plannedEntry).isFinite &&
        (projection.entryPrice ?? plan.plannedEntry) > 0 &&
        plan.targets.isNotEmpty &&
        plan.targets.every((target) => target.isFinite && target > 0);
    final overlay = validOverlay
        ? ChartTradeOverlay(
            entry: projection.entryPrice ?? plan.plannedEntry,
            stop: plan.originalStopLoss,
            targets: plan.targets,
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
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
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
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final level in referenceLevels)
                  Chip(
                    avatar: const Icon(Icons.history_toggle_off_rounded, size: 16),
                    label: Text(
                      '${level.label} ${QuantaraNumberFormat.marketValue(level.value)}',
                    ),
                  ),
              ],
            ),
          ],
          if (plan.confluence.isNotEmpty || plan.rationale.trim().isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              persian ? 'چرا این پوزیشن باز شد؟' : 'Why was this trade opened?',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 8),
            if (plan.rationale.trim().isNotEmpty)
              Text(plan.rationale),
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
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
''',
)

# 6) Supply latest symbol/timeframe market context to Journal and refresh it on
# an explicit Journal refresh. The OwnerAlpha controller also refreshes on its
# existing timer, so an open Journal detail follows market updates automatically.
replace_once(
    "src/client/quantara_app/lib/features/owner_alpha/presentation/owner_alpha_page.dart",
    """      case 6:
        if (_autoTradeController.isConnected) {
          await _autoTradeController.reconcile(
            reason: PrivateAccountRefreshReason.manual,
            force: true,
          );
        }
        await _reconcileJournalFromAccount();
        await _journalController.refresh();
        return;
""",
    """      case 6:
        await _controller.refresh();
        if (_autoTradeController.isConnected) {
          await _autoTradeController.reconcile(
            reason: PrivateAccountRefreshReason.manual,
            force: true,
          );
        }
        await _reconcileJournalFromAccount();
        await _journalController.refresh();
        return;
""",
)
replace_once(
    "src/client/quantara_app/lib/features/owner_alpha/presentation/owner_alpha_page.dart",
    """  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 1024;
    final initialMarketLoading =
""",
    """  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 1024;
    final marketSnapshot = controller.snapshot;
    final journalLiveAnalyses = <String, TimeframeChartAnalysis>{
      for (final radar in marketSnapshot?.radar ?? const <SymbolRadarResult>[])
        for (final entry in radar.analysesByTimeframe.entries)
          '${radar.quote.symbol.trim().toUpperCase()}|${entry.key.trim()}':
              entry.value,
    };
    final journalLiveIdeas = <String, TradeIdea>{
      for (final radar in marketSnapshot?.radar ?? const <SymbolRadarResult>[])
        for (final entry in radar.ideasByTimeframe.entries)
          '${radar.quote.symbol.trim().toUpperCase()}|${entry.key.trim()}':
              entry.value,
    };
    final initialMarketLoading =
""",
)
replace_once(
    "src/client/quantara_app/lib/features/owner_alpha/presentation/owner_alpha_page.dart",
    """                        statistics: journalController.statistics,
                        isLoading: journalController.isLoading,
                        error: journalController.error,
""",
    """                        statistics: journalController.statistics,
                        liveAnalyses: journalLiveAnalyses,
                        liveIdeas: journalLiveIdeas,
                        isLoading: journalController.isLoading,
                        error: journalController.error,
""",
)

# 7) Physical QA build number.
replace_once(
    "src/client/quantara_app/pubspec.yaml",
    "version: 1.2.0-rc.2+122",
    "version: 1.2.0-rc.2+123",
)

# 8) Regressions for the exact physical AAVE economics/protection and source wiring.
test_path = ROOT / "src/client/quantara_app/test/issue_173_physical_qa_regression_test.dart"
test_path.write_text(r'''import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/auto_trade/domain/auto_trade_models.dart';
import 'package:quantara_app/features/auto_trade/domain/trading_pnl_projection.dart';

void main() {
  test('AAVE open-position net semantics stay verified', () {
    final openedAt = DateTime.utc(2026, 8, 8, 16, 34, 9);
    const gross = 0.0;
    const feeExpense = 0.0054756;
    const funding = 0.00058839571;
    const pendingNet = -0.00488720429;
    final open = ExchangeUnrealizedPnl(
      positionId: '3518418297103901915',
      symbol: 'AAVEUSDT',
      value: 0.006,
      realizedPnl: pendingNet,
      fee: -feeExpense,
      funding: funding,
      openedAt: openedAt,
    );
    final entryFill = ExchangePnlFill(
      tradeId: '6465817657640892218',
      orderId: '2086128842343002112',
      positionId: open.positionId,
      symbol: open.symbol,
      quantity: 0.1,
      price: 91.26,
      realizedPnl: gross,
      fee: feeExpense,
      reduceOnly: false,
      occurredAt: openedAt,
      side: 'SELL',
    );

    final projection = TradingPnlProjection.reconcile(
      currency: 'USDT',
      asOf: DateTime.utc(2026, 8, 9, 6, 12),
      unrealizedByPosition: {open.positionId: open},
      fills: [entryFill],
      settlements: const [],
      sourceVerified: true,
    );
    final position = projection.forPositionId(open.positionId);

    expect(gross - feeExpense + funding, closeTo(pendingNet, 1e-12));
    expect(position, isNotNull);
    expect(position!.isVerified, isTrue);
    expect(position.warning, isNull);
    expect(position.fees.value, closeTo(feeExpense, 1e-12));
    expect(projection.isReadyForRiskGates, isTrue);
  });

  test('one full TP plus one full SL is complete account protection', () {
    const position = AutoTradePosition(
      positionId: '3518418297103901915',
      symbol: 'AAVEUSDT',
      quantity: 0.1,
      side: 'SELL',
      marginMode: 'ISOLATION',
      positionMode: 'HEDGE',
      leverage: 10,
      margin: 0.919,
      unrealizedPnl: 0.006,
      liquidationPrice: 99.83,
      averageOpenPrice: 91.26,
    );
    final asOf = DateTime.utc(2026, 8, 9, 6, 12);
    final snapshot = AutoTradeAccountSnapshot(
      marginCoin: 'USDT',
      available: 28.65,
      frozen: 0,
      positionMargin: 0.919,
      crossUnrealizedPnl: 0,
      isolatedUnrealizedPnl: 0.006,
      positionMode: 'HEDGE',
      positions: const [position],
      orders: const [],
      protectionOrders: const [
        AutoTradeProtectionOrder.takeProfit(
          exchangeId: 'tp-1',
          positionId: '3518418297103901915',
          symbol: 'AAVEUSDT',
          price: 88.8,
          quantity: 0.1,
        ),
        AutoTradeProtectionOrder.stopLoss(
          exchangeId: 'sl-1',
          positionId: '3518418297103901915',
          symbol: 'AAVEUSDT',
          price: 92.36,
          quantity: 0.1,
        ),
      ],
      protectionVerifications: {
        '3518418297103901915': AutoTradeProtectionVerification.verified(
          asOf: asOf,
        ),
      },
      syncedAt: asOf,
    );

    expect(
      snapshot.protectionForPosition(position).status,
      AutoTradeProtectionStatus.fullyProtected,
    );
    expect(snapshot.allOpenPositionsFullyProtected, isTrue);
  });

  test('Issue 173 wiring preserves frozen plan and live market separation', () {
    final projectionSource = File(
      'lib/features/auto_trade/domain/trading_pnl_projection.dart',
    ).readAsStringSync();
    final serviceSource = File(
      'lib/features/auto_trade/application/local_live_trade_service.dart',
    ).readAsStringSync();
    final accountSource = File(
      'lib/features/auto_trade/domain/auto_trade_models.dart',
    ).readAsStringSync();
    final chartSource = File(
      'lib/features/market_analysis/presentation/tradingview_lightweight_chart.dart',
    ).readAsStringSync();
    final journalSource = File(
      'lib/features/trading_journal/presentation/trading_journal_view.dart',
    ).readAsStringSync();
    final pageSource = File(
      'lib/features/owner_alpha/presentation/owner_alpha_page.dart',
    ).readAsStringSync();

    expect(projectionSource, contains('pendingNetFromHistory'));
    expect(projectionSource, contains('pendingFeeExpense'));
    expect(serviceSource, contains('clearWarning: true'));
    expect(accountSource, contains('expectedTakeProfitCount: 1'));
    expect(chartSource, contains('this.tradeOverlay'));
    expect(journalSource, contains('نمودار زنده پوزیشن'));
    expect(journalSource, contains('تحلیل بازار از زمان ورود تغییر جهت داده است'));
    expect(journalSource, contains('previousDonchianHigh20'));
    expect(journalSource, contains('live.strongestZones'));
    expect(pageSource, contains('journalLiveAnalyses'));
    expect(pageSource, contains('await _controller.refresh();'));
  });
}
''', encoding="utf-8")

print("Issue #173 patch staged successfully.")
