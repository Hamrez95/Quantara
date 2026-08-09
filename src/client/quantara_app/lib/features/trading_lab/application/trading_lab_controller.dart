import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../owner_alpha/application/owner_alpha_controller.dart';
import '../data/database_trading_lab_store.dart';
import '../domain/trading_lab_models.dart';
import 'trading_lab_paper_broker.dart';
import 'trading_lab_review_bundle.dart';

final class TradingLabController extends ChangeNotifier {
  factory TradingLabController({
    required OwnerAlphaController marketController,
    required TradingLabRunStore store,
    TradingLabPaperBroker broker = const TradingLabPaperBroker(),
  }) => TradingLabController._(marketController, store, broker);

  TradingLabController._(this._marketController, this._store, this._broker);

  final OwnerAlphaController _marketController;
  final TradingLabRunStore _store;
  final TradingLabPaperBroker _broker;

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
    if (snapshot != null) {
      for (final radar in snapshot.radar) {
        for (final idea in radar.ideasByTimeframe.values) {
          strategyVersions.add('${idea.strategy.name}@${idea.strategyVersion}');
        }
      }
    }
    if (strategyVersions.isEmpty) {
      strategyVersions.add('${_marketController.strategy.name}@runtime');
    }
    _run = TradingLabRun(
      manifest: TradingLabRunManifest(
        runId: 'lab-${now.microsecondsSinceEpoch}',
        startedAtUtc: now,
        startingEquity: startingEquity,
        riskPercent: riskPercent,
        maximumConcurrentPositions: maximumConcurrentPositions,
        leverage: leverage,
        symbols: _marketController.symbols,
        timeframes: OwnerAlphaController.timeframes.where(
          (item) => item != '1D',
        ),
        strategies: strategyVersions,
        feeRateBps: feeRateBps,
        slippageBps: slippageBps,
        fundingRatePerEightHours: fundingRatePerEightHours,
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
          _broker.processSnapshot(current!, snapshot);
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
    return buildTradingLabAiReviewJson(current);
  }

  String suggestedExportFileName() {
    final current = _run;
    if (current == null) return 'quantara-lab-ai-review.json';
    return 'quantara-lab-${current.manifest.runId}-ai-review.json';
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
