import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../market_analysis/domain/market_chart_models.dart';
import '../data/bitunix_owner_alpha_repository.dart';
import '../data/signal_outcome_evaluator.dart';
import '../data/trade_idea_factory.dart';
import '../domain/owner_alpha_models.dart';

enum OwnerAlphaConnectionState {
  connecting,
  refreshing,
  fresh,
  stale,
  unavailable,
}

final class OwnerAlphaController extends ChangeNotifier {
  factory OwnerAlphaController({
    required OwnerAlphaRepository repository,
    required OwnerAlphaSettingsStore settingsStore,
    OpportunityStateStore? opportunityStateStore,
    SetupNotificationGateway notificationGateway =
        const NoopSetupNotificationGateway(),
    BackgroundScanGateway backgroundScanGateway =
        const NoopBackgroundScanGateway(),
    Duration scanInterval = const Duration(seconds: 60),
    String languageCode = 'fa',
  }) {
    return OwnerAlphaController._(
      repository,
      settingsStore,
      opportunityStateStore,
      notificationGateway,
      backgroundScanGateway,
      scanInterval,
      languageCode,
    );
  }

  OwnerAlphaController._(
    this._repository,
    this._settingsStore,
    this._opportunityStateStore,
    this._notificationGateway,
    this._backgroundScanGateway,
    this._scanInterval,
    this._languageCode,
  ) {
    if (_scanInterval < const Duration(seconds: 30)) {
      throw ArgumentError.value(_scanInterval, 'scanInterval');
    }
  }

  static const defaultSymbols = ['BTCUSDT', 'ETHUSDT', 'SOLUSDT', 'AVAXUSDT'];
  static final _symbolPattern = RegExp(r'^[A-Z0-9]{2,20}$');
  static const timeframes = ['15m', '1h', '4h', '1D'];

  final OwnerAlphaRepository _repository;
  final OwnerAlphaSettingsStore _settingsStore;
  final OpportunityStateStore? _opportunityStateStore;
  final SetupNotificationGateway _notificationGateway;
  final BackgroundScanGateway _backgroundScanGateway;
  final Duration _scanInterval;

  List<String> _symbols = List.of(defaultSymbols);
  String _selectedSymbol = defaultSymbols.first;
  String _selectedTimeframe = '1h';
  double _capital = 10000;
  double _riskPercent = 1;
  AnalysisStrategy _strategy = AnalysisStrategy.structureZones;
  SignalCadence _cadence = SignalCadence.balanced;
  OwnerAlphaSnapshot? _snapshot;
  String? _error;
  OwnerAlphaDataException? _lastDataException;
  bool _unexpectedError = false;
  bool _loading = false;
  bool _initialized = false;
  DateTime? _nextScanAt;
  Timer? _timer;
  int _requestGeneration = 0;
  Future<bool>? _activeScan;
  bool _disposed = false;
  String _languageCode;
  OpportunityState _opportunityState = const OpportunityState();

  List<String> get symbols => List.unmodifiable(_symbols);
  String get selectedSymbol => _selectedSymbol;
  String get selectedTimeframe => _selectedTimeframe;
  double get capital => _capital;
  double get riskPercent => _riskPercent;
  AnalysisStrategy get strategy => _strategy;
  SignalCadence get cadence => _cadence;
  OwnerAlphaSnapshot? get snapshot => _snapshot;
  String? get error => _error;
  bool get isLoading => _loading;
  bool get isInitialized => _initialized;
  DateTime? get nextScanAt => _nextScanAt;
  bool get hasStaleSnapshot => _snapshot != null && _error != null;
  String get languageCode => _languageCode;
  bool get notificationsEnabled => _opportunityState.notificationsEnabled;
  Set<String> get takenSetupIds =>
      Set.unmodifiable(_opportunityState.takenSetupIds);
  bool isTaken(String setupId) =>
      _opportunityState.takenSetupIds.contains(setupId);
  List<SignalJournalEntry> get signalJournal =>
      List.unmodifiable(_opportunityState.journal);
  SignalJournalEntry? signalEntry(String setupId) {
    for (final item in _opportunityState.journal) {
      if (item.setupId == setupId) return item;
    }
    return null;
  }
  DateTime? get lastBackgroundScanAt =>
      _opportunityState.lastBackgroundScanAt;
  String? get lastBackgroundError =>
      _opportunityState.lastBackgroundError;
  OwnerAlphaConnectionState get connectionState {
    final current = _snapshot;
    if (current == null) {
      return _error == null
          ? OwnerAlphaConnectionState.connecting
          : OwnerAlphaConnectionState.unavailable;
    }
    if (_error != null ||
        DateTime.now().toUtc().difference(current.generatedAt) >
            _scanInterval * 2) {
      return OwnerAlphaConnectionState.stale;
    }
    return _loading
        ? OwnerAlphaConnectionState.refreshing
        : OwnerAlphaConnectionState.fresh;
  }

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    _initialized = true;
    if (_opportunityStateStore != null) {
      _opportunityState = await _opportunityStateStore.load();
    }
    final saved = await _settingsStore.load();
    if (saved != null) {
      final normalized = saved.symbols
          .map(_normalizeSymbol)
          .whereType<String>()
          .toSet()
          .take(12)
          .toList(growable: false);
      if (normalized.isNotEmpty) {
        _symbols = normalized;
        _selectedSymbol = normalized.first;
      }
      _capital = saved.capital.clamp(100, 100000000).toDouble();
      _riskPercent = saved.riskPercent.clamp(0.1, 2).toDouble();
      _strategy = saved.strategy;
      _cadence = saved.cadence;
    }
    await _configureBackgroundScan();
    await refresh();
    if (!_disposed) {
      _timer = Timer.periodic(_scanInterval, (_) => refresh(silent: true));
    }
  }

  Future<void> refresh({bool silent = false}) async {
    await _requestScan(silent: silent);
  }

  Future<bool> _requestScan({
    bool silent = false,
    List<String>? symbols,
    String? selectedSymbol,
    String? selectedTimeframe,
    bool persistSettings = false,
  }) async {
    if (_disposed) {
      return false;
    }
    final active = _activeScan;
    if (active != null) {
      if (silent) {
        return false;
      }
      await active;
      return _requestScan(
        silent: silent,
        symbols: symbols,
        selectedSymbol: selectedSymbol,
        selectedTimeframe: selectedTimeframe,
        persistSettings: persistSettings,
      );
    }

    late final Future<bool> operation;
    operation =
        _performScan(
          silent: silent,
          symbols: symbols,
          selectedSymbol: selectedSymbol,
          selectedTimeframe: selectedTimeframe,
          persistSettings: persistSettings,
        ).whenComplete(() {
          if (identical(_activeScan, operation)) {
            _activeScan = null;
          }
        });
    _activeScan = operation;
    return operation;
  }

  Future<bool> _performScan({
    required bool silent,
    required List<String>? symbols,
    required String? selectedSymbol,
    required String? selectedTimeframe,
    required bool persistSettings,
  }) async {
    final requestedSymbols = List<String>.unmodifiable(symbols ?? _symbols);
    final requestedSymbol = selectedSymbol ?? _selectedSymbol;
    final requestedTimeframe = selectedTimeframe ?? _selectedTimeframe;
    final generation = ++_requestGeneration;
    _loading = true;
    if (!silent || _snapshot == null) {
      _error = null;
      _lastDataException = null;
      _unexpectedError = false;
    }
    notifyListeners();
    try {
      final result = await _repository.scan(
        symbols: requestedSymbols,
        selectedSymbol: requestedSymbol,
        selectedTimeframe: requestedTimeframe,
        capital: _capital,
        riskPercent: _riskPercent,
        languageCode: _languageCode,
      );
      if (_disposed || generation != _requestGeneration) {
        return false;
      }
      if (persistSettings) {
        await _settingsStore.save(
          OwnerAlphaSettings(
            symbols: requestedSymbols,
            capital: _capital,
            riskPercent: _riskPercent,
            strategy: _strategy,
            cadence: _cadence,
          ),
        );
      }
      if (_disposed || generation != _requestGeneration) {
        return false;
      }
      _symbols = requestedSymbols;
      _selectedSymbol = result.selectedSymbol;
      _selectedTimeframe = result.selectedTimeframe;
      await _configureBackgroundScan();
      final configuredResult = _applyStrategy(result);
      _snapshot = configuredResult;
      _error = null;
      _lastDataException = null;
      _unexpectedError = false;
      _nextScanAt = DateTime.now().toUtc().add(_scanInterval);
      await _reloadOpportunityState();
      await _captureOpportunities(configuredResult.opportunities);
      await _evaluateSignalJournal(configuredResult);
      await _notifyNewOpportunities(configuredResult.opportunities);
      return true;
    } catch (error) {
      if (_disposed || generation != _requestGeneration) {
        return false;
      }
      _lastDataException = error is OwnerAlphaDataException ? error : null;
      _unexpectedError = error is! OwnerAlphaDataException;
      _error = _lastDataException != null
          ? _lastDataException!.messageFor(_languageCode)
          : _t(
              'خطای پیش‌بینی‌نشده هنگام دریافت بازار رخ داد.',
              'An unexpected error occurred while loading the market.',
            );
      _nextScanAt = DateTime.now().toUtc().add(_scanInterval);
      return false;
    } finally {
      if (!_disposed && generation == _requestGeneration) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  Future<void> selectSymbol(String symbol) async {
    if (!_symbols.contains(symbol) || symbol == _selectedSymbol) {
      return;
    }
    if (_selectFromSnapshot(symbol, _selectedTimeframe)) {
      return;
    }
    await _requestScan(selectedSymbol: symbol);
  }

  Future<void> selectTimeframe(String timeframe) async {
    if (!timeframes.contains(timeframe) || timeframe == _selectedTimeframe) {
      return;
    }
    if (_selectFromSnapshot(_selectedSymbol, timeframe)) {
      return;
    }
    await _requestScan(selectedTimeframe: timeframe);
  }

  bool _selectFromSnapshot(String symbol, String timeframe) {
    final current = _snapshot;
    if (current == null) {
      return false;
    }
    SymbolRadarResult? result;
    for (final item in current.radar) {
      if (item.quote.symbol == symbol) {
        result = item;
        break;
      }
    }
    final analysis = result?.analysesByTimeframe[timeframe];
    if (result == null || analysis == null) {
      return false;
    }
    final directions = <String, ChartDirection>{
      for (final entry in result.analysesByTimeframe.entries)
        entry.key: entry.value.direction,
    };
    _selectedSymbol = symbol;
    _selectedTimeframe = timeframe;
    _snapshot = OwnerAlphaSnapshot(
      radar: current.radar,
      selectedSymbol: symbol,
      selectedTimeframe: timeframe,
      selectedAnalysis: analysis,
      selectedIdea:
          result.ideasByTimeframe[timeframe] ??
          TradeIdeaFactory.create(
            analysis: analysis,
            capital: _capital,
            riskPercent: _riskPercent,
            languageCode: _languageCode,
            confluence: directions,
            strategy: _strategy,
            cadence: _cadence,
          ),
      timeframeDirections: directions,
      scanFailures: current.scanFailures,
      diagnostics: current.diagnostics,
      generatedAt: current.generatedAt,
    );
    notifyListeners();
    return true;
  }

  Future<String?> addSymbol(String rawValue) async {
    final symbol = _normalizeSymbol(rawValue);
    if (symbol == null) {
      return _t(
        'نماد فقط باید شامل حروف انگلیسی و عدد باشد.',
        'A symbol may contain only Latin letters and numbers.',
      );
    }
    if (_symbols.contains(symbol)) {
      return _t(
        'این نماد از قبل در واچ‌لیست است.',
        'This symbol is already in the watchlist.',
      );
    }
    if (_symbols.length >= 12) {
      return _t(
        'حداکثر ۱۲ نماد قابل پایش است.',
        'You can monitor up to 12 symbols.',
      );
    }
    final added = await _requestScan(
      symbols: [..._symbols, symbol],
      persistSettings: true,
    );
    return added ? null : _error;
  }

  Future<void> removeSymbol(String symbol) async {
    if (_symbols.length <= 1 || !_symbols.contains(symbol)) {
      return;
    }
    final remaining = _symbols.where((item) => item != symbol).toList();
    await _requestScan(
      symbols: remaining,
      selectedSymbol: _selectedSymbol == symbol
          ? remaining.first
          : _selectedSymbol,
      persistSettings: true,
    );
  }

  Future<void> updateRiskSettings({
    required double capital,
    required double riskPercent,
  }) async {
    while (_activeScan != null) {
      await _activeScan!;
    }
    if (_disposed) {
      return;
    }
    final safeCapital = capital.clamp(100, 100000000).toDouble();
    final safeRisk = riskPercent.clamp(0.1, 2).toDouble();
    if (_capital == safeCapital && _riskPercent == safeRisk) {
      return;
    }
    _capital = safeCapital;
    _riskPercent = safeRisk;
    await _saveSettings();
    final current = _snapshot;
    if (current != null) {
      final directions = current.timeframeDirections;
      _snapshot = OwnerAlphaSnapshot(
        radar: [
          for (final result in current.radar)
            SymbolRadarResult(
              quote: result.quote,
              analysis: result.analysis,
              idea: _rebuildIdea(result.analysis, result.analysesByTimeframe),
              analysesByTimeframe: result.analysesByTimeframe,
              ideasByTimeframe: {
                for (final entry in result.analysesByTimeframe.entries)
                  if (BitunixOwnerAlphaRepository.opportunityTimeframes
                      .contains(entry.key))
                    entry.key: _rebuildIdea(
                      entry.value,
                      result.analysesByTimeframe,
                    ),
              },
            ),
        ],
        selectedSymbol: current.selectedSymbol,
        selectedTimeframe: current.selectedTimeframe,
        selectedAnalysis: current.selectedAnalysis,
        selectedIdea: _rebuildIdea(
          current.selectedAnalysis,
          current.radar
              .firstWhere((item) => item.quote.symbol == current.selectedSymbol)
              .analysesByTimeframe,
        ),
        timeframeDirections: directions,
        scanFailures: current.scanFailures,
        diagnostics: current.diagnostics,
        generatedAt: current.generatedAt,
      );
    }
    notifyListeners();
  }

  static String? _normalizeSymbol(String rawValue) {
    var value = rawValue.trim().toUpperCase().replaceAll('/', '');
    if (value.isEmpty || !_symbolPattern.hasMatch(value)) {
      return null;
    }
    if (!value.endsWith('USDT')) {
      value = '${value}USDT';
    }
    return value.length <= 24 ? value : null;
  }

  Future<void> updateSignalPolicy({
    required AnalysisStrategy strategy,
    required SignalCadence cadence,
  }) async {
    if (_strategy == strategy && _cadence == cadence) {
      return;
    }
    _strategy = strategy;
    _cadence = cadence;
    await _saveSettings();
    final current = _snapshot;
    if (current != null) {
      _snapshot = _applyStrategy(current);
    }
    notifyListeners();
  }

  OwnerAlphaSnapshot _applyStrategy(OwnerAlphaSnapshot current) {
    final rebuiltRadar = <SymbolRadarResult>[
      for (final result in current.radar)
        SymbolRadarResult(
          quote: result.quote,
          analysis: result.analysis,
          idea: _rebuildIdea(result.analysis, result.analysesByTimeframe),
          analysesByTimeframe: result.analysesByTimeframe,
          ideasByTimeframe: {
            for (final entry in result.analysesByTimeframe.entries)
              if (BitunixOwnerAlphaRepository.opportunityTimeframes.contains(
                entry.key,
              ))
                entry.key: _rebuildIdea(
                  entry.value,
                  result.analysesByTimeframe,
                ),
          },
        ),
    ];
    final selectedResult = rebuiltRadar.firstWhere(
      (item) => item.quote.symbol == current.selectedSymbol,
    );
    final selectedAnalysis =
        selectedResult.analysesByTimeframe[current.selectedTimeframe] ??
        current.selectedAnalysis;
    return OwnerAlphaSnapshot(
      radar: rebuiltRadar,
      selectedSymbol: current.selectedSymbol,
      selectedTimeframe: current.selectedTimeframe,
      selectedAnalysis: selectedAnalysis,
      selectedIdea: _rebuildIdea(
        selectedAnalysis,
        selectedResult.analysesByTimeframe,
      ),
      timeframeDirections: {
        for (final entry in selectedResult.analysesByTimeframe.entries)
          entry.key: entry.value.direction,
      },
      scanFailures: current.scanFailures,
      diagnostics: current.diagnostics,
      generatedAt: current.generatedAt,
    );
  }

  void setLanguage(String languageCode, {bool notify = true}) {
    final normalized = languageCode == 'en' ? 'en' : 'fa';
    if (_languageCode == normalized) {
      return;
    }
    _languageCode = normalized;
    if (_lastDataException != null) {
      _error = _lastDataException!.messageFor(_languageCode);
    } else if (_unexpectedError) {
      _error = _t(
        'خطای پیش‌بینی‌نشده هنگام دریافت بازار رخ داد.',
        'An unexpected error occurred while loading the market.',
      );
    }
    final current = _snapshot;
    if (current != null) {
      final directions = current.timeframeDirections;
      _snapshot = OwnerAlphaSnapshot(
        radar: [
          for (final result in current.radar)
            SymbolRadarResult(
              quote: result.quote,
              analysis: result.analysis,
              idea: _rebuildIdea(result.analysis, result.analysesByTimeframe),
              analysesByTimeframe: result.analysesByTimeframe,
              ideasByTimeframe: {
                for (final entry in result.analysesByTimeframe.entries)
                  if (BitunixOwnerAlphaRepository.opportunityTimeframes
                      .contains(entry.key))
                    entry.key: _rebuildIdea(
                      entry.value,
                      result.analysesByTimeframe,
                    ),
              },
            ),
        ],
        selectedSymbol: current.selectedSymbol,
        selectedTimeframe: current.selectedTimeframe,
        selectedAnalysis: current.selectedAnalysis,
        selectedIdea: _rebuildIdea(
          current.selectedAnalysis,
          current.radar
              .firstWhere((item) => item.quote.symbol == current.selectedSymbol)
              .analysesByTimeframe,
        ),
        timeframeDirections: directions,
        scanFailures: current.scanFailures,
        diagnostics: current.diagnostics,
        generatedAt: current.generatedAt,
      );
    }
    unawaited(_configureBackgroundScan());
    if (notify) {
      notifyListeners();
    }
  }

  String _t(String fa, String en) => _languageCode == 'en' ? en : fa;

  OwnerAlphaSettings get _currentSettings => OwnerAlphaSettings(
    symbols: _symbols,
    capital: _capital,
    riskPercent: _riskPercent,
    strategy: _strategy,
    cadence: _cadence,
  );

  Future<void> _saveSettings() async {
    await _settingsStore.save(_currentSettings);
    await _configureBackgroundScan();
  }

  Future<void> _configureBackgroundScan() {
    return _backgroundScanGateway.configure(
      enabled: _opportunityState.notificationsEnabled,
      settings: _currentSettings,
      languageCode: _languageCode,
    );
  }

  TradeIdea _rebuildIdea(
    TimeframeChartAnalysis analysis,
    Map<String, TimeframeChartAnalysis> analyses,
  ) {
    return TradeIdeaFactory.create(
      analysis: analysis,
      capital: _capital,
      riskPercent: _riskPercent,
      confluence: {
        for (final entry in analyses.entries) entry.key: entry.value.direction,
      },
      languageCode: _languageCode,
      strategy: _strategy,
      cadence: _cadence,
    );
  }

  Future<bool> setNotificationsEnabled(bool enabled) async {
    if (enabled && !await _notificationGateway.requestPermission()) {
      return false;
    }
    _opportunityState = _opportunityState.copyWith(
      notificationsEnabled: enabled,
    );
    await _persistOpportunityState();
    await _configureBackgroundScan();
    notifyListeners();
    return true;
  }

  Future<void> openBackgroundSettings() =>
      _notificationGateway.openBackgroundSettings();

  Future<void> setTaken(String setupId, bool taken) async {
    final updated = Set<String>.of(_opportunityState.takenSetupIds);
    taken ? updated.add(setupId) : updated.remove(setupId);
    _opportunityState = _opportunityState.copyWith(takenSetupIds: updated);
    await _persistOpportunityState();
    notifyListeners();
  }

  Future<void> updateSignalNote(String setupId, String note) async {
    final safeNote = note.trim();
    if (safeNote.length > 2000) {
      throw ArgumentError.value(note, 'note');
    }
    _opportunityState = _opportunityState.copyWith(
      journal: [
        for (final item in _opportunityState.journal)
          item.setupId == setupId ? item.copyWith(note: safeNote) : item,
      ],
    );
    await _persistOpportunityState();
    notifyListeners();
  }

  Future<void> closeSignal(String setupId, bool closed) async {
    _opportunityState = _opportunityState.copyWith(
      journal: [
        for (final item in _opportunityState.journal)
          item.setupId == setupId ? item.copyWith(closed: closed) : item,
      ],
    );
    await _persistOpportunityState();
    notifyListeners();
  }

  Future<void> setSignalLeverage(String setupId, int leverage) async {
    SignalJournalEntry? entry;
    for (final item in _opportunityState.journal) {
      if (item.setupId == setupId) {
        entry = item;
        break;
      }
    }
    if (entry == null ||
        leverage < 1 ||
        leverage > entry.maximumSafeLeverage) {
      return;
    }
    final margin = entry.notionalValue / leverage;
    final marginReturn = entry.simulatedPnl == null || margin <= 0
        ? entry.marginReturnPercent
        : entry.simulatedPnl! / margin * 100;
    _opportunityState = _opportunityState.copyWith(
      journal: [
        for (final item in _opportunityState.journal)
          item.setupId == setupId
              ? item.copyWith(
                  selectedLeverage: leverage,
                  marginReturnPercent: marginReturn,
                )
              : item,
      ],
    );
    await _persistOpportunityState();
    notifyListeners();
  }

  Future<void> _captureOpportunities(List<TradeIdea> ideas) async {
    if (ideas.isEmpty) return;
    final byId = {
      for (final item in _opportunityState.journal) item.setupId: item,
    };
    for (final idea in ideas) {
      final existing = byId[idea.setupId];
      if (existing == null) {
        byId[idea.setupId] = SignalJournalEntry.fromIdea(idea);
      } else if (existing.positionSize <= 0 || existing.notionalValue <= 0) {
        byId[idea.setupId] = SignalJournalEntry.fromIdea(
          idea,
        ).copyWith(note: existing.note, closed: existing.closed);
      }
    }
    final journal = byId.values.toList()
      ..sort((left, right) => right.createdAt.compareTo(left.createdAt));
    _opportunityState = _opportunityState.copyWith(
      journal: journal.take(100).toList(growable: false),
    );
    await _persistOpportunityState();
  }

  Future<void> _reloadOpportunityState() async {
    final store = _opportunityStateStore;
    if (store == null) return;
    _opportunityState = await store.load();
  }

  Future<void> _evaluateSignalJournal(OwnerAlphaSnapshot snapshot) async {
    if (_opportunityState.journal.isEmpty) return;
    final candles = <String, List<ChartCandle>>{
      for (final result in snapshot.radar)
        for (final analysis in result.analysesByTimeframe.values)
          '${analysis.symbol}|${analysis.timeframe}':
              analysis.candles.toList(growable: false),
    };
    final evaluatedAt = DateTime.now().toUtc();
    _opportunityState = _opportunityState.copyWith(
      journal: [
        for (final entry in _opportunityState.journal)
          SignalOutcomeEvaluator.evaluate(
            entry: entry,
            candles:
                candles['${entry.symbol}|${entry.timeframe}'] ??
                const <ChartCandle>[],
            evaluatedAt: evaluatedAt,
          ),
      ],
    );
    await _persistOpportunityState();
  }

  Future<void> _notifyNewOpportunities(List<TradeIdea> ideas) async {
    if (!_opportunityState.notificationsEnabled || ideas.isEmpty) {
      return;
    }
    final notified = Set<String>.of(_opportunityState.notifiedSetupIds);
    var changed = false;
    for (final idea in ideas) {
      if (!notified.add(idea.setupId)) {
        continue;
      }
      await _notificationGateway.show(idea, languageCode: _languageCode);
      changed = true;
    }
    if (changed) {
      final bounded = notified.length <= 250
          ? notified
          : notified.skip(notified.length - 250).toSet();
      _opportunityState = _opportunityState.copyWith(notifiedSetupIds: bounded);
      await _persistOpportunityState();
    }
  }

  Future<void> _persistOpportunityState() async {
    await _opportunityStateStore?.save(_opportunityState);
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _requestGeneration++;
    super.dispose();
  }
}
