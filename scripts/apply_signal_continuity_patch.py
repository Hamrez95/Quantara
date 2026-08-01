from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def replace_once(path: str, old: str, new: str) -> None:
    target = ROOT / path
    text = target.read_text(encoding="utf-8")
    if old not in text:
        raise RuntimeError(f"Expected patch anchor not found in {path}: {old[:80]!r}")
    target.write_text(text.replace(old, new, 1), encoding="utf-8")


# 1. Use the documented 35% / 35% / 30% scale-out ladder for all
# hypothetical signal outcomes, including stop-after-target scenarios.
replace_once(
    "src/client/quantara_app/lib/features/owner_alpha/data/signal_outcome_evaluator.dart",
    """    var effectiveExit = exitPrice;
    var grossPnl =
        (exitPrice - referenceEntry) * entry.positionSize * direction;

    // When price reaches one or more targets and later stops, model equal
    // one-third scale-outs at the reached targets and send only the remaining
    // size to the stop. This avoids reporting the whole position as a stop
    // after the journal already recorded TP1/TP2.
    if (outcome == SignalOutcome.stopped && highestTarget > 0) {
      final trancheSize = entry.positionSize / entry.targets.length;
      final realizedTargets = entry.targets
          .take(highestTarget)
          .fold<double>(
            0,
            (sum, target) =>
                sum + (target - referenceEntry) * trancheSize * direction,
          );
      final remainingSize = entry.positionSize - trancheSize * highestTarget;
      final stoppedRemainder =
          (entry.stopLoss! - referenceEntry) * remainingSize * direction;
      grossPnl = realizedTargets + stoppedRemainder;
      effectiveExit =
          referenceEntry + grossPnl / entry.positionSize * direction;
    }
""",
    """    const targetFractions = <double>[0.35, 0.35, 0.30];
    final reachedTargets = highestTarget
        .clamp(0, targetFractions.length)
        .toInt();
    var realizedSize = 0.0;
    var grossPnl = 0.0;

    for (var index = 0; index < reachedTargets; index++) {
      final trancheSize = entry.positionSize * targetFractions[index];
      realizedSize += trancheSize;
      grossPnl +=
          (entry.targets[index] - referenceEntry) * trancheSize * direction;
    }

    // A target event marks the still-open remainder at the latest reached
    // target. A later stop sends only that remainder to the original stop.
    // This preserves the documented 35% / 35% / 30% paper-management policy
    // without pretending that the entire position exited at TP2 or TP3.
    final remainingSize = (entry.positionSize - realizedSize)
        .clamp(0, entry.positionSize)
        .toDouble();
    final remainingExit = outcome == SignalOutcome.stopped
        ? entry.stopLoss!
        : exitPrice;
    grossPnl +=
        (remainingExit - referenceEntry) * remainingSize * direction;
    final effectiveExit =
        referenceEntry + grossPnl / entry.positionSize * direction;
""",
)

# 2. Keep unresolved journal entries alive even after their symbols leave the
# watchlist. Missing symbols are fetched in bounded batches of two, and the
# result is used only for outcome replay (never to mutate the watchlist).
controller = "src/client/quantara_app/lib/features/owner_alpha/application/owner_alpha_controller.dart"
replace_once(
    controller,
    "  static const timeframes = ['15m', '1h', '4h', '1D'];\n",
    "  static const timeframes = ['15m', '1h', '4h', '1D'];\n"
    "  static const outcomeCatchUpBatchSize = 2;\n",
)
replace_once(
    controller,
    "  OpportunityState _opportunityState = const OpportunityState();\n",
    "  OpportunityState _opportunityState = const OpportunityState();\n"
    "  String? _selectedChartSignalId;\n",
)
replace_once(
    controller,
    """  List<SignalJournalEntry> get signalJournal =>
      List.unmodifiable(_opportunityState.journal);
  SignalJournalEntry? signalEntry(String setupId) {
""",
    """  List<SignalJournalEntry> get signalJournal =>
      List.unmodifiable(_opportunityState.journal);
  SignalJournalEntry? get selectedChartSignal {
    final setupId = _selectedChartSignalId;
    return setupId == null ? null : signalEntry(setupId);
  }

  SignalJournalEntry? signalEntry(String setupId) {
""",
)
replace_once(
    controller,
    """  Future<void> selectSymbol(String symbol) async {
    if (!_symbols.contains(symbol) || symbol == _selectedSymbol) {
""",
    """  Future<void> selectSymbol(String symbol) async {
    _selectedChartSignalId = null;
    if (!_symbols.contains(symbol) || symbol == _selectedSymbol) {
""",
)
replace_once(
    controller,
    """  Future<void> selectTimeframe(String timeframe) async {
    if (!timeframes.contains(timeframe) || timeframe == _selectedTimeframe) {
""",
    """  Future<void> selectTimeframe(String timeframe) async {
    _selectedChartSignalId = null;
    if (!timeframes.contains(timeframe) || timeframe == _selectedTimeframe) {
""",
)
replace_once(
    controller,
    """  Future<void> selectTimeframe(String timeframe) async {
    _selectedChartSignalId = null;
    if (!timeframes.contains(timeframe) || timeframe == _selectedTimeframe) {
      return;
    }
    if (_selectFromSnapshot(_selectedSymbol, timeframe)) {
      return;
    }
    await _requestScan(selectedTimeframe: timeframe);
  }

  bool _selectFromSnapshot(String symbol, String timeframe) {
""",
    """  Future<void> selectTimeframe(String timeframe) async {
    _selectedChartSignalId = null;
    if (!timeframes.contains(timeframe) || timeframe == _selectedTimeframe) {
      return;
    }
    if (_selectFromSnapshot(_selectedSymbol, timeframe)) {
      return;
    }
    await _requestScan(selectedTimeframe: timeframe);
  }

  Future<bool> selectChartContext({
    required String symbol,
    required String timeframe,
    String? setupId,
  }) async {
    if (!_symbols.contains(symbol) || !timeframes.contains(timeframe)) {
      return false;
    }

    var loaded = _selectFromSnapshot(symbol, timeframe);
    if (!loaded) {
      loaded = await _requestScan(
        selectedSymbol: symbol,
        selectedTimeframe: timeframe,
      );
    }
    if (!loaded) return false;

    final signal = setupId == null ? null : signalEntry(setupId);
    _selectedChartSignalId = signal != null &&
            signal.symbol == symbol &&
            signal.timeframe == timeframe
        ? setupId
        : null;
    notifyListeners();
    return true;
  }

  bool _selectFromSnapshot(String symbol, String timeframe) {
""",
)
replace_once(
    controller,
    """  Future<void> _evaluateSignalJournal(OwnerAlphaSnapshot snapshot) async {
    if (_opportunityState.journal.isEmpty) return;
    final candles = <String, List<ChartCandle>>{
      for (final result in snapshot.radar)
        for (final analysis in result.analysesByTimeframe.values)
          '${analysis.symbol}|${analysis.timeframe}': analysis.candles.toList(
            growable: false,
          ),
    };
""",
    """  Future<Map<String, List<ChartCandle>>> _collectOutcomeCandles(
    OwnerAlphaSnapshot snapshot,
  ) async {
    final candles = <String, List<ChartCandle>>{
      for (final result in snapshot.radar)
        for (final analysis in result.analysesByTimeframe.values)
          '${analysis.symbol}|${analysis.timeframe}': analysis.candles.toList(
            growable: false,
          ),
    };
    final missingSymbols = _opportunityState.journal
        .where((entry) => !entry.hasTerminalOutcome && !entry.closed)
        .where(
          (entry) =>
              !candles.containsKey('${entry.symbol}|${entry.timeframe}'),
        )
        .map((entry) => entry.symbol)
        .toSet()
        .toList(growable: false);

    for (
      var start = 0;
      start < missingSymbols.length;
      start += outcomeCatchUpBatchSize
    ) {
      final batch = missingSymbols
          .skip(start)
          .take(outcomeCatchUpBatchSize)
          .toList(growable: false);
      if (batch.isEmpty) continue;
      final matchingEntry = _opportunityState.journal.firstWhere(
        (entry) => entry.symbol == batch.first,
      );
      final selectedTimeframe = timeframes.contains(matchingEntry.timeframe)
          ? matchingEntry.timeframe
          : '1h';
      try {
        final catchUp = await _repository.scan(
          symbols: batch,
          selectedSymbol: batch.first,
          selectedTimeframe: selectedTimeframe,
          capital: _capital,
          riskPercent: _riskPercent,
          languageCode: _languageCode,
        );
        for (final result in catchUp.radar) {
          for (final analysis in result.analysesByTimeframe.values) {
            candles['${analysis.symbol}|${analysis.timeframe}'] = analysis
                .candles
                .toList(growable: false);
          }
        }
      } catch (_) {
        // Catch-up is best-effort and must never hide the current watchlist.
        // Missing data leaves the signal unresolved until a later scan.
      }
    }
    return candles;
  }

  Future<void> _evaluateSignalJournal(OwnerAlphaSnapshot snapshot) async {
    if (_opportunityState.journal.isEmpty) return;
    final candles = await _collectOutcomeCandles(snapshot);
""",
)

# 3. Opening a signal now selects its immutable symbol + timeframe and retains
# the originating journal entry for a frozen chart overlay.
page = "src/client/quantara_app/lib/features/owner_alpha/presentation/owner_alpha_page.dart"
replace_once(
    page,
    "part 'owner_alpha_strategy_lab.dart';\n\nclass OwnerAlphaPage",
    "part 'owner_alpha_strategy_lab.dart';\n\n"
    "typedef _OpenAnalysis = void Function(\n"
    "  String symbol, [\n"
    "  String? timeframe,\n"
    "  String? setupId,\n"
    "]);\n\n"
    "class OwnerAlphaPage",
)
replace_once(
    page,
    """  void _openAnalysis(String symbol) {
    unawaited(_controller.selectSymbol(symbol));
    setState(() => _destination = 2);
  }
""",
    """  void _openAnalysis(
    String symbol, [
    String? timeframe,
    String? setupId,
  ]) {
    unawaited(_openAnalysisContext(symbol, timeframe, setupId));
  }

  Future<void> _openAnalysisContext(
    String symbol,
    String? timeframe,
    String? setupId,
  ) async {
    final opened = await _controller.selectChartContext(
      symbol: symbol,
      timeframe: timeframe ?? _controller.selectedTimeframe,
      setupId: setupId,
    );
    if (!mounted) return;
    if (opened) {
      setState(() => _destination = 2);
      return;
    }
    final persian = widget.locale.languageCode != 'en';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(
          persian
              ? 'زمینه دقیق این پیشنهاد فعلاً در واچ‌لیست یا داده بازار موجود نیست.'
              : 'The exact signal context is not currently available in the watchlist or market data.',
        ),
      ),
    );
  }
""",
)
replace_once(
    page,
    "  final ValueChanged<String> onOpenAnalysis;\n",
    "  final _OpenAnalysis onOpenAnalysis;\n",
)

signals = "src/client/quantara_app/lib/features/owner_alpha/presentation/owner_alpha_signals.dart"
replace_once(
    signals,
    "  final ValueChanged<String> onOpenAnalysis;\n",
    "  final _OpenAnalysis onOpenAnalysis;\n",
)
replace_once(
    signals,
    "              onOpen: () => widget.onOpenAnalysis(filtered[index].symbol),\n",
    """              onOpen: () => widget.onOpenAnalysis(
                filtered[index].symbol,
                filtered[index].timeframe,
                filtered[index].setupId,
              ),
""",
)

analysis = "src/client/quantara_app/lib/features/owner_alpha/presentation/owner_alpha_analysis.dart"
replace_once(
    analysis,
    "              TradingViewLightweightChart(analysis: analysis, idea: idea),\n",
    """              TradingViewLightweightChart(
                analysis: analysis,
                idea: idea,
                frozenSignal: controller.selectedChartSignal,
              ),
""",
)

# 4. Draw a frozen journal overlay only when symbol, timeframe, prices and the
# historical candle range are all valid. Otherwise show the chart without a
# misleading historical overlay.
chart = "src/client/quantara_app/lib/features/market_analysis/presentation/tradingview_lightweight_chart.dart"
replace_once(
    chart,
    """class TradingViewLightweightChart extends StatelessWidget {
  const TradingViewLightweightChart({
    required this.analysis,
    required this.idea,
    this.height = 390,
    super.key,
  });

  final TimeframeChartAnalysis analysis;
  final TradeIdea idea;
  final double height;
""",
    """abstract final class ChartSignalOverlayPolicy {
  static ChartTradeOverlay? create({
    required TimeframeChartAnalysis analysis,
    required SignalJournalEntry signal,
  }) {
    if (!canRender(analysis: analysis, signal: signal)) return null;
    return ChartTradeOverlay(
      entry: (signal.entryLower! + signal.entryUpper!) / 2,
      stop: signal.stopLoss!,
      targets: signal.targets,
      isLong: signal.direction == TradeDirection.long,
    );
  }

  static bool canRender({
    required TimeframeChartAnalysis analysis,
    required SignalJournalEntry signal,
  }) {
    final entryLower = signal.entryLower;
    final entryUpper = signal.entryUpper;
    final stopLoss = signal.stopLoss;
    if (analysis.symbol != signal.symbol ||
        analysis.timeframe != signal.timeframe ||
        signal.direction == TradeDirection.wait ||
        entryLower == null ||
        entryUpper == null ||
        stopLoss == null ||
        !entryLower.isFinite ||
        !entryUpper.isFinite ||
        !stopLoss.isFinite ||
        entryLower <= 0 ||
        entryUpper < entryLower ||
        stopLoss <= 0 ||
        signal.targets.length != 3 ||
        signal.targets.any((target) => !target.isFinite || target <= 0)) {
      return false;
    }
    final candles = analysis.candles;
    if (candles.isEmpty ||
        candles.any(
          (candle) =>
              !candle.open.isFinite ||
              !candle.high.isFinite ||
              !candle.low.isFinite ||
              !candle.close.isFinite,
        )) {
      return false;
    }
    return !candles.first.openTime.isAfter(signal.createdAt) &&
        !candles.last.openTime.isBefore(signal.createdAt);
  }
}

class TradingViewLightweightChart extends StatelessWidget {
  const TradingViewLightweightChart({
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
)
replace_once(
    chart,
    """    final overlay = idea.isActionable
        ? ChartTradeOverlay(
            entry: (idea.entryLower! + idea.entryUpper!) / 2,
            stop: idea.stopLoss!,
            targets: idea.targets,
            isLong: idea.direction == TradeDirection.long,
          )
        : null;
""",
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
""",
)
replace_once(
    chart,
    "      key: ValueKey('quantara-chart-${analysis.fingerprint}-${idea.setupId}'),\n",
    """      key: ValueKey(
        'quantara-chart-${analysis.fingerprint}-${frozen?.setupId ?? idea.setupId}',
      ),
""",
)

# 5. Strengthen numerical regression coverage for TP allocation.
outcome_test = "src/client/quantara_app/test/signal_outcome_evaluator_test.dart"
replace_once(
    outcome_test,
    """    expect(result.outcome, SignalOutcome.tp2);
    expect(result.highestTargetHit, 2);
    expect(result.simulatedPnl, greaterThan(0));
    expect(result.marginReturnPercent, greaterThan(result.priceChangePercent!));
""",
    """    expect(result.outcome, SignalOutcome.tp2);
    expect(result.highestTargetHit, 2);
    expect(result.simulatedPnl, closeTo(13, 0.000001));
    expect(result.marginReturnPercent, greaterThan(result.priceChangePercent!));
""",
)
replace_once(
    outcome_test,
    """    expect(stopped.outcome, SignalOutcome.stopped);
    expect(stopped.highestTargetHit, 2);
    expect(stopped.simulatedPnl, greaterThan(0));
""",
    """    expect(stopped.outcome, SignalOutcome.stopped);
    expect(stopped.highestTargetHit, 2);
    expect(stopped.simulatedPnl, closeTo(4, 0.000001));
""",
)

(ROOT / "src/client/quantara_app/test/chart_signal_overlay_policy_test.dart").write_text(
    """import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/market_analysis/domain/market_chart_models.dart';
import 'package:quantara_app/features/market_analysis/presentation/tradingview_lightweight_chart.dart';
import 'package:quantara_app/features/owner_alpha/domain/owner_alpha_models.dart';

void main() {
  test('renders a frozen overlay only when historical candles cover the signal', () {
    final signal = _signal();
    final covered = _analysis(start: _origin.subtract(const Duration(minutes: 10)));
    final afterSignal = _analysis(start: _origin.add(const Duration(minutes: 1)));

    expect(
      ChartSignalOverlayPolicy.canRender(analysis: covered, signal: signal),
      isTrue,
    );
    expect(
      ChartSignalOverlayPolicy.create(analysis: covered, signal: signal),
      isNotNull,
    );
    expect(
      ChartSignalOverlayPolicy.canRender(
        analysis: afterSignal,
        signal: signal,
      ),
      isFalse,
    );
  });

  test('rejects a frozen overlay for a different timeframe', () {
    final analysis = _analysis(
      start: _origin.subtract(const Duration(minutes: 10)),
      timeframe: '1h',
    );

    expect(
      ChartSignalOverlayPolicy.canRender(
        analysis: analysis,
        signal: _signal(),
      ),
      isFalse,
    );
  });
}

final _origin = DateTime.utc(2026, 8, 1, 12);

TimeframeChartAnalysis _analysis({
  required DateTime start,
  String timeframe = '15m',
}) {
  return TimeframeChartAnalysis(
    symbol: 'BTCUSDT',
    timeframe: timeframe,
    candles: [
      for (var index = 0; index < 20; index++)
        ChartCandle(
          openTime: start.add(Duration(minutes: index)),
          open: 100,
          high: 102,
          low: 99,
          close: 101,
          volume: 10,
        ),
    ],
    zones: const [],
    direction: ChartDirection.bullish,
    directionStrength: 0.7,
    volatilityPercent: 1,
    summary: 'test',
    generatedAt: start.add(const Duration(minutes: 20)),
    fingerprint: 'overlay-test-$timeframe-${start.millisecondsSinceEpoch}',
  );
}

SignalJournalEntry _signal() => SignalJournalEntry(
  setupId: 'BTCUSDT|15m|long|frozen',
  symbol: 'BTCUSDT',
  timeframe: '15m',
  direction: TradeDirection.long,
  strategy: AnalysisStrategy.structureZones,
  strategyVersion: 'test/1',
  createdAt: _origin,
  validUntil: _origin.add(const Duration(minutes: 45)),
  entryLower: 99.5,
  entryUpper: 100.5,
  stopLoss: 98,
  targets: const [102, 104, 106],
  maximumLoss: 10,
  positionSize: 5,
  notionalValue: 500,
  estimatedRoundTripCosts: 1,
  recommendedLeverage: 5,
  maximumSafeLeverage: 8,
  selectedLeverage: 5,
  summary: 'test',
  invalidation: 'test',
);
""",
    encoding="utf-8",
)

(ROOT / "src/client/quantara_app/test/signal_continuity_source_test.dart").write_text(
    """import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('signal continuity stays bounded and opens exact chart context', () {
    final controller = File(
      'lib/features/owner_alpha/application/owner_alpha_controller.dart',
    ).readAsStringSync();
    final signals = File(
      'lib/features/owner_alpha/presentation/owner_alpha_signals.dart',
    ).readAsStringSync();
    final analysis = File(
      'lib/features/owner_alpha/presentation/owner_alpha_analysis.dart',
    ).readAsStringSync();

    expect(controller, contains('outcomeCatchUpBatchSize = 2'));
    expect(controller, contains('_collectOutcomeCandles'));
    expect(controller, contains('selectChartContext'));
    expect(signals, contains('filtered[index].timeframe'));
    expect(signals, contains('filtered[index].setupId'));
    expect(analysis, contains('frozenSignal: controller.selectedChartSignal'));
  });
}
""",
    encoding="utf-8",
)

# Remove the one-shot patch machinery in the same generated commit.
(ROOT / ".github/workflows/apply-signal-continuity.yml").unlink(missing_ok=True)
Path(__file__).unlink(missing_ok=True)
