import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/bitunix_owner_alpha_repository.dart';
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
  OwnerAlphaController({
    required OwnerAlphaRepository repository,
    required OwnerAlphaSettingsStore settingsStore,
    Duration scanInterval = const Duration(seconds: 60),
    String languageCode = 'fa',
  }) : _repository = repository,
       _settingsStore = settingsStore,
       _scanInterval = scanInterval,
       _languageCode = languageCode {
    if (scanInterval < const Duration(seconds: 30)) {
      throw ArgumentError.value(scanInterval, 'scanInterval');
    }
  }

  static const defaultSymbols = ['BTCUSDT', 'ETHUSDT', 'SOLUSDT', 'AVAXUSDT'];
  static final _symbolPattern = RegExp(r'^[A-Z0-9]{2,20}$');
  static const timeframes = ['15m', '1h', '4h', '1D'];

  final OwnerAlphaRepository _repository;
  final OwnerAlphaSettingsStore _settingsStore;
  final Duration _scanInterval;

  List<String> _symbols = List.of(defaultSymbols);
  String _selectedSymbol = defaultSymbols.first;
  String _selectedTimeframe = '1h';
  double _capital = 10000;
  double _riskPercent = 1;
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

  List<String> get symbols => List.unmodifiable(_symbols);
  String get selectedSymbol => _selectedSymbol;
  String get selectedTimeframe => _selectedTimeframe;
  double get capital => _capital;
  double get riskPercent => _riskPercent;
  OwnerAlphaSnapshot? get snapshot => _snapshot;
  String? get error => _error;
  bool get isLoading => _loading;
  bool get isInitialized => _initialized;
  DateTime? get nextScanAt => _nextScanAt;
  bool get hasStaleSnapshot => _snapshot != null && _error != null;
  String get languageCode => _languageCode;
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
      _riskPercent = saved.riskPercent.clamp(0.1, 5).toDouble();
    }
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
          ),
        );
      }
      if (_disposed || generation != _requestGeneration) {
        return false;
      }
      _symbols = requestedSymbols;
      _selectedSymbol = requestedSymbol;
      _selectedTimeframe = requestedTimeframe;
      _snapshot = result;
      _error = null;
      _lastDataException = null;
      _unexpectedError = false;
      _nextScanAt = DateTime.now().toUtc().add(_scanInterval);
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
    await _requestScan(selectedSymbol: symbol);
  }

  Future<void> selectTimeframe(String timeframe) async {
    if (!timeframes.contains(timeframe) || timeframe == _selectedTimeframe) {
      return;
    }
    await _requestScan(selectedTimeframe: timeframe);
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
    final safeRisk = riskPercent.clamp(0.1, 5).toDouble();
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
              idea: TradeIdeaFactory.create(
                analysis: result.analysis,
                capital: _capital,
                riskPercent: _riskPercent,
                languageCode: _languageCode,
                confluence: result.quote.symbol == current.selectedSymbol
                    ? directions
                    : const {},
              ),
            ),
        ],
        selectedSymbol: current.selectedSymbol,
        selectedTimeframe: current.selectedTimeframe,
        selectedAnalysis: current.selectedAnalysis,
        selectedIdea: TradeIdeaFactory.create(
          analysis: current.selectedAnalysis,
          capital: _capital,
          riskPercent: _riskPercent,
          languageCode: _languageCode,
          confluence: directions,
        ),
        timeframeDirections: directions,
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
              idea: TradeIdeaFactory.create(
                analysis: result.analysis,
                capital: _capital,
                riskPercent: _riskPercent,
                confluence: result.quote.symbol == current.selectedSymbol
                    ? directions
                    : const {},
                languageCode: _languageCode,
              ),
            ),
        ],
        selectedSymbol: current.selectedSymbol,
        selectedTimeframe: current.selectedTimeframe,
        selectedAnalysis: current.selectedAnalysis,
        selectedIdea: TradeIdeaFactory.create(
          analysis: current.selectedAnalysis,
          capital: _capital,
          riskPercent: _riskPercent,
          confluence: directions,
          languageCode: _languageCode,
        ),
        timeframeDirections: directions,
        generatedAt: current.generatedAt,
      );
    }
    if (notify) {
      notifyListeners();
    }
  }

  String _t(String fa, String en) => _languageCode == 'en' ? en : fa;

  Future<void> _saveSettings() {
    return _settingsStore.save(
      OwnerAlphaSettings(
        symbols: _symbols,
        capital: _capital,
        riskPercent: _riskPercent,
      ),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _requestGeneration++;
    super.dispose();
  }
}
