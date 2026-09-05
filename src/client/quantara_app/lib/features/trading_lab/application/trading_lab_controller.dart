import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../owner_alpha/application/owner_alpha_controller.dart';
import '../../owner_alpha/domain/owner_alpha_models.dart';
import '../data/database_trading_lab_store.dart';
import '../domain/trading_lab_account_context.dart';
import '../domain/trading_lab_models.dart';
import '../domain/trading_lab_real_account_evidence.dart';
import 'trading_lab_benchmark.dart';
import 'trading_lab_paper_broker.dart';
import 'trading_lab_shadow_evidence.dart';
import 'trading_lab_strategy_identity.dart';
import 'trading_lab_zip_bundle.dart';

final class TradingLabController extends ChangeNotifier {
  factory TradingLabController({
    required OwnerAlphaController marketController,
    required TradingLabRunStore store,
    TradingLabPaperBroker broker = const TradingLabPaperBroker(),
    TradingLabAccountContext Function()? accountContextProvider,
    TradingLabRealAccountEvidence Function()? realAccountEvidenceProvider,
  }) => TradingLabController._(
    marketController,
    store,
    broker,
    accountContextProvider,
    realAccountEvidenceProvider,
  );

  TradingLabController._(
    this._marketController,
    this._store,
    this._broker,
    this._accountContextProvider,
    this._realAccountEvidenceProvider,
  );

  final OwnerAlphaController _marketController;
  final TradingLabRunStore _store;
  final TradingLabPaperBroker _broker;
  final TradingLabAccountContext Function()? _accountContextProvider;
  final TradingLabRealAccountEvidence Function()? _realAccountEvidenceProvider;

  TradingLabRun? _run;
  List<TradingLabRun> _history = const [];
  bool _initialized = false;
  bool _disposed = false;
  bool _processing = false;
  bool _queued = false;
  String? _error;

  TradingLabRun? get run => _run;
  List<TradingLabRun> get history => List.unmodifiable(_history);
  bool get isInitialized => _initialized;
  bool get isProcessing => _processing;
  String? get error => _error;
  bool get hasRunningExperiment => _run?.isRunning == true;
  TradingLabAccountContext get accountContext =>
      _accountContextProvider?.call() ??
      TradingLabAccountContext.disconnected();
  TradingLabRealAccountEvidence get realAccountEvidence =>
      _realAccountEvidenceProvider?.call() ??
      TradingLabRealAccountEvidence.unavailable();

  List<TradeIdea> get availableEvaluationIdeas {
    final snapshot = _marketController.snapshot;
    if (snapshot == null) return const <TradeIdea>[];
    final byIdentity = <String, TradeIdea>{};
    for (final radar in snapshot.radar) {
      for (final idea in radar.ideasByTimeframe.values) {
        if (!getTradingLabIdeaHasImmutableRegistryIdentity(idea)) continue;
        final key = tradingLabStrategyIdentityKey(idea);
        final current = byIdentity[key];
        if (current == null || (!current.isActionable && idea.isActionable)) {
          byIdentity[key] = idea;
        }
      }
    }
    final result = byIdentity.values.toList(growable: false)
      ..sort((left, right) {
        final strategy = left.registryStrategyId.compareTo(
          right.registryStrategyId,
        );
        if (strategy != 0) return strategy;
        final symbol = left.symbol.compareTo(right.symbol);
        if (symbol != 0) return symbol;
        return left.timeframe.compareTo(right.timeframe);
      });
    return List<TradeIdea>.unmodifiable(result);
  }

  TradeIdea? get defaultEvaluationIdea {
    final selected = _marketController.snapshot?.selectedIdea;
    if (selected != null &&
        getTradingLabIdeaHasImmutableRegistryIdentity(selected)) {
      return selected;
    }
    return availableEvaluationIdeas.firstOrNull;
  }

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    _marketController.addListener(_onMarketChanged);
    try {
      _run = await _store.loadActive();
      _history = await _store.loadHistory();
      _error = null;
    } on Object catch (error) {
      _error = 'Trading Lab persistence could not be loaded: $error';
    }
    if (!_disposed) notifyListeners();
    if (_run?.isRunning == true) {
      await consumeLatestMarketSnapshot();
    }
  }

  Future<void> startExperiment({
    required double startingEquity,
    required double riskPercent,
    required int maximumConcurrentPositions,
    required int leverage,
    double feeRateBps = 6,
    double slippageBps = 2,
    double fundingRatePerEightHours = 0,
    double spreadBps = 1,
    double portfolioRiskPercent = 3,
    double symbolHeatPercent = 1,
    int scannerIntervalSeconds = 15,
    int minimumConfidencePercent = 65,
    double minimumRiskReward = 1.5,
    double maxEstimatedCostToRiskPercent = 25,
    TradingLabMarginMode marginMode = TradingLabMarginMode.isolated,
    TradingLabExecutionModel executionModel =
        TradingLabExecutionModel.conservativeCandlePath,
    TradeIdea? evaluationIdea,
    String experimentTag = '',
    String notes = '',
  }) async {
    if (_run?.isRunning == true) {
      throw StateError(
        'Stop the active Trading Lab experiment before starting a new one.',
      );
    }
    final now = DateTime.now().toUtc();
    final snapshot = _marketController.snapshot;
    final strategyVersions = <String>{};
    late final List<String> symbols;
    late final List<String> timeframes;

    if (evaluationIdea != null) {
      if (!getTradingLabIdeaHasImmutableRegistryIdentity(evaluationIdea)) {
        throw StateError(
          'The selected setup has no immutable registry snapshot and cannot start a reproducible evaluation.',
        );
      }
      strategyVersions.add(tradingLabStrategyIdentityKey(evaluationIdea));
      symbols = <String>[evaluationIdea.symbol.trim().toUpperCase()];
      timeframes = <String>[evaluationIdea.timeframe.trim()];
    } else {
      if (snapshot != null) {
        for (final radar in snapshot.radar) {
          for (final idea in radar.ideasByTimeframe.values) {
            strategyVersions.add(tradingLabStrategyIdentityKey(idea));
          }
        }
      }
      if (strategyVersions.isEmpty) {
        strategyVersions.add('${_marketController.strategy.name}@runtime');
      }
      symbols = _marketController.symbols;
      timeframes = const ['5m', '15m', '30m', '1h'];
    }

    _run = TradingLabRun(
      manifest: TradingLabRunManifest(
        runId: 'lab-${now.microsecondsSinceEpoch}',
        startedAtUtc: now,
        startingEquity: startingEquity,
        riskPercent: riskPercent,
        maximumConcurrentPositions: maximumConcurrentPositions,
        leverage: leverage,
        symbols: symbols,
        timeframes: timeframes,
        strategies: strategyVersions,
        feeRateBps: feeRateBps,
        slippageBps: slippageBps,
        fundingRatePerEightHours: fundingRatePerEightHours,
        spreadBps: spreadBps,
        portfolioRiskPercent: portfolioRiskPercent,
        symbolHeatPercent: symbolHeatPercent,
        scannerIntervalSeconds: scannerIntervalSeconds,
        minimumConfidencePercent: minimumConfidencePercent,
        minimumRiskReward: minimumRiskReward,
        maxEstimatedCostToRiskPercent: maxEstimatedCostToRiskPercent,
        marginMode: marginMode,
        executionModel: executionModel,
        experimentTag: experimentTag,
        notes: notes,
      ),
    );
    _error = null;
    await _store.save(_run!);
    if (!_disposed) notifyListeners();
    await consumeLatestMarketSnapshot();
  }

  Future<void> stopExperiment() async {
    final current = _run;
    if (current == null || !current.isRunning) return;
    current.status = TradingLabRunStatus.stopped;
    await _store.save(current);
    _history = await _store.loadHistory();
    if (!_disposed) notifyListeners();
  }

  Future<void> consumeLatestMarketSnapshot() async {
    if (_disposed || _run?.isRunning != true) return;
    if (_processing) {
      _queued = true;
      return;
    }
    _processing = true;
    if (!_disposed) notifyListeners();
    try {
      do {
        _queued = false;
        final snapshot = _marketController.snapshot;
        final current = _run;
        if (snapshot != null && current?.isRunning == true) {
          _broker.processSnapshot(
            current!,
            snapshot,
            accountContext: accountContext,
          );
          await _store.save(current);
          _history = await _store.loadHistory();
          _error = null;
        }
      } while (_queued && !_disposed && _run?.isRunning == true);
    } on Object catch (error) {
      _error = 'Trading Lab cycle failed safely: $error';
    } finally {
      _processing = false;
      if (!_disposed) notifyListeners();
    }
  }

  String exportAiReviewJson() {
    final current = _run;
    if (current == null) {
      throw StateError('No Trading Lab experiment is available to export.');
    }
    return buildTradingLabAiReviewJsonWithShadows(
      current,
      _marketController.signalJournal,
      accountContext: accountContext,
    );
  }

  TradingLabZipBundle exportFullEvidenceZip() {
    final current = _run;
    if (current == null) {
      throw StateError('No Trading Lab experiment is available to export.');
    }
    final context = accountContext;
    final shadowEvidence = buildTradingLabShadowEvidence(
      current,
      _marketController.signalJournal,
    );
    final aiReviewJson = buildTradingLabAiReviewJsonWithShadows(
      current,
      _marketController.signalJournal,
      accountContext: context,
    );
    return const TradingLabZipBundleCodec().encode(
      run: current,
      aiReviewJson: aiReviewJson,
      shadowEvidence: shadowEvidence,
      accountContext: context,
      realAccountEvidence: realAccountEvidence,
      benchmarkMatrix: buildTradingLabBenchmarkMatrix(<TradingLabRun>[
        ..._history,
        current,
      ]),
    );
  }

  Future<void> restoreFullEvidenceZip(Uint8List bytes) async {
    if (_run?.isRunning == true) {
      throw StateError(
        'Stop the active Trading Lab experiment before restoring another bundle.',
      );
    }
    final imported = const TradingLabZipBundleCodec().decode(bytes);
    final restored = imported.run;
    // Imported evidence is restored read-only/stopped. A historical ZIP must
    // never start processing fresh market data merely because it was opened.
    restored.status = TradingLabRunStatus.stopped;
    _run = restored;
    _error = null;
    await _store.save(restored);
    _history = await _store.loadHistory();
    if (!_disposed) notifyListeners();
  }

  String suggestedExportFileName() {
    final current = _run;
    if (current == null) return 'quantara-lab-ai-review.json';
    return 'quantara-lab-${current.manifest.runId}-ai-review.json';
  }

  String suggestedZipExportFileName() {
    final current = _run;
    if (current == null) return 'quantara-lab-evidence.zip';
    return 'quantara-lab-${current.manifest.runId}.zip';
  }

  void _onMarketChanged() {
    if (_run?.isRunning != true || _disposed) return;
    unawaited(consumeLatestMarketSnapshot());
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _marketController.removeListener(_onMarketChanged);
    super.dispose();
  }
}
