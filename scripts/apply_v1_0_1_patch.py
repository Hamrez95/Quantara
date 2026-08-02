from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding='utf-8')


def write(path: str, content: str) -> None:
    target = ROOT / path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(content, encoding='utf-8')


def replace_once(path: str, old: str, new: str) -> None:
    text = read(path)
    if old not in text:
        raise RuntimeError(f'Anchor missing in {path}: {old[:160]!r}')
    write(path, text.replace(old, new, 1))


# ---------------------------------------------------------------------------
# Persistent Local Live preferences. Running/armed state is intentionally not
# persisted, but every user-controlled value is.
# ---------------------------------------------------------------------------
write(
    'src/client/quantara_app/lib/features/auto_trade/data/local_live_preferences_store.dart',
    r'''import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

@immutable
class LocalLivePreferences {
  const LocalLivePreferences({
    required this.symbols,
    required this.timeframes,
    required this.leverage,
    required this.riskPercent,
    required this.dailyLossLimitPercent,
  });

  static const supportedTimeframes = {'5m', '15m', '1h', '4h'};
  static const minimumLeverage = 1;
  static const maximumLeverage = 125;
  static const minimumRiskPercent = 0.05;
  static const maximumRiskPercent = 2.0;
  static const minimumDailyLossPercent = 0.25;
  static const maximumDailyLossPercent = 10.0;

  final List<String> symbols;
  final Set<String> timeframes;
  final int leverage;
  final double riskPercent;
  final double dailyLossLimitPercent;

  factory LocalLivePreferences.defaults(List<String> availableSymbols) =>
      LocalLivePreferences(
        symbols: availableSymbols.take(4).toList(growable: false),
        timeframes: const {'1h', '4h'},
        leverage: 10,
        riskPercent: 0.10,
        dailyLossLimitPercent: 1,
      );

  LocalLivePreferences normalized(List<String> availableSymbols) {
    final allowed = availableSymbols
        .map((item) => item.trim().toUpperCase())
        .where((item) => item.isNotEmpty)
        .toSet();
    final keptSymbols = symbols
        .map((item) => item.trim().toUpperCase())
        .where(allowed.contains)
        .toSet()
        .toList(growable: false);
    final defaults = LocalLivePreferences.defaults(availableSymbols);
    final keptTimeframes = timeframes
        .where(supportedTimeframes.contains)
        .toSet();
    return LocalLivePreferences(
      symbols: keptSymbols.isEmpty ? defaults.symbols : keptSymbols,
      timeframes: keptTimeframes.isEmpty
          ? defaults.timeframes
          : Set.unmodifiable(keptTimeframes),
      leverage: leverage.clamp(minimumLeverage, maximumLeverage),
      riskPercent: riskPercent
          .clamp(minimumRiskPercent, maximumRiskPercent)
          .toDouble(),
      dailyLossLimitPercent: dailyLossLimitPercent
          .clamp(minimumDailyLossPercent, maximumDailyLossPercent)
          .toDouble(),
    );
  }
}

abstract interface class LocalLivePreferencesStore {
  Future<LocalLivePreferences> load({required List<String> availableSymbols});

  Future<void> save(LocalLivePreferences preferences);
}

final class SharedPreferencesLocalLivePreferencesStore
    implements LocalLivePreferencesStore {
  const SharedPreferencesLocalLivePreferencesStore();

  static const _symbolsKey = 'quantara.local-live.ui.symbols.v2';
  static const _timeframesKey = 'quantara.local-live.ui.timeframes.v2';
  static const _leverageKey = 'quantara.local-live.ui.leverage.v2';
  static const _riskKey = 'quantara.local-live.ui.risk.v2';
  static const _dailyLossKey = 'quantara.local-live.ui.daily-loss.v2';

  @override
  Future<LocalLivePreferences> load({
    required List<String> availableSymbols,
  }) async {
    final defaults = LocalLivePreferences.defaults(availableSymbols);
    final preferences = await SharedPreferences.getInstance();
    return LocalLivePreferences(
      symbols: preferences.getStringList(_symbolsKey) ?? defaults.symbols,
      timeframes: (preferences.getStringList(_timeframesKey) ??
              defaults.timeframes.toList(growable: false))
          .toSet(),
      leverage: preferences.getInt(_leverageKey) ?? defaults.leverage,
      riskPercent: preferences.getDouble(_riskKey) ?? defaults.riskPercent,
      dailyLossLimitPercent:
          preferences.getDouble(_dailyLossKey) ??
          defaults.dailyLossLimitPercent,
    ).normalized(availableSymbols);
  }

  @override
  Future<void> save(LocalLivePreferences value) async {
    final preferences = await SharedPreferences.getInstance();
    await Future.wait([
      preferences.setStringList(_symbolsKey, value.symbols),
      preferences.setStringList(
        _timeframesKey,
        value.timeframes.toList(growable: false)..sort(),
      ),
      preferences.setInt(_leverageKey, value.leverage),
      preferences.setDouble(_riskKey, value.riskPercent),
      preferences.setDouble(_dailyLossKey, value.dailyLossLimitPercent),
    ]);
  }
}
''',
)

page = 'src/client/quantara_app/lib/features/owner_alpha/presentation/owner_alpha_page.dart'
replace_once(
    page,
    "import '../../auto_trade/data/bitunix_private_api_client.dart';\n",
    "import '../../auto_trade/data/bitunix_private_api_client.dart';\nimport '../../auto_trade/data/local_live_preferences_store.dart';\n",
)

# ---------------------------------------------------------------------------
# Persisted controls, broader bounded settings and explicit advanced warning.
# ---------------------------------------------------------------------------
auto = 'src/client/quantara_app/lib/features/owner_alpha/presentation/owner_alpha_auto_trade.dart'
replace_once(
    auto,
    """  final Set<String> _enabledSymbols = {};
  final Set<String> _enabledTimeframes = {'1h', '4h'};
  int _leverage = 10;
  double _riskPercent = 0.10;
  double _dailyLossLimit = 1;
""",
    """  final LocalLivePreferencesStore _preferencesStore =
      const SharedPreferencesLocalLivePreferencesStore();
  final Set<String> _enabledSymbols = {};
  final Set<String> _enabledTimeframes = {'1h', '4h'};
  int _leverage = 10;
  double _riskPercent = 0.10;
  double _dailyLossLimit = 1;
  bool _preferencesLoaded = false;
""",
)
replace_once(
    auto,
    """  @override
  void initState() {
    super.initState();
    _enabledSymbols.addAll(widget.analysisController.symbols.take(4));
  }

  @override
  Widget build(BuildContext context) {
""",
    """  @override
  void initState() {
    super.initState();
    _enabledSymbols.addAll(widget.analysisController.symbols.take(4));
    unawaited(_restorePreferences());
  }

  Future<void> _restorePreferences() async {
    final value = await _preferencesStore.load(
      availableSymbols: widget.analysisController.symbols,
    );
    if (!mounted) return;
    setState(() {
      _enabledSymbols
        ..clear()
        ..addAll(value.symbols);
      _enabledTimeframes
        ..clear()
        ..addAll(value.timeframes);
      _leverage = value.leverage;
      _riskPercent = value.riskPercent;
      _dailyLossLimit = value.dailyLossLimitPercent;
      _preferencesLoaded = true;
    });
  }

  LocalLivePreferences get _currentPreferences => LocalLivePreferences(
    symbols: _enabledSymbols.toList(growable: false),
    timeframes: Set.unmodifiable(_enabledTimeframes),
    leverage: _leverage,
    riskPercent: _riskPercent,
    dailyLossLimitPercent: _dailyLossLimit,
  ).normalized(widget.analysisController.symbols);

  void _mutateAndSave(VoidCallback mutation) {
    setState(mutation);
    unawaited(_preferencesStore.save(_currentPreferences));
  }

  Future<void> _persistPreferences() =>
      _preferencesStore.save(_currentPreferences);

  @override
  Widget build(BuildContext context) {
""",
)
replace_once(
    auto,
    """              'این حالت می‌تواند سفارش واقعی فیوچرز ارسال کند. نسخه Canary فقط یک پوزیشن هم‌زمان و حداکثر ۰٫۲۵٪ ریسک در هر معامله دارد، Isolated است و هر ورود باید با SL صرافی و سه TP تأیید شود.',
              'This mode can submit real futures orders. Canary is limited to one concurrent position and 0.25% risk per trade, uses isolated margin, and requires exchange-confirmed SL plus three targets.',
""",
    """              'این حالت می‌تواند سفارش واقعی فیوچرز ارسال کند. فقط یک پوزیشن هم‌زمان و Isolated مجاز است؛ ریسک قابل تنظیم تا ۲٪ و سقف ضرر روزانه تا ۱۰٪ باز شده، اما هر ورود همچنان باید با SL کامل و سه TP تأییدشده صرافی محافظت شود.',
              'This mode can submit real futures orders. It remains isolated and limited to one concurrent position; risk is adjustable up to 2% and the daily cap up to 10%, while every entry still requires a full exchange-confirmed stop and three targets.',
""",
)
replace_once(
    auto,
    """          const Divider(height: 28),
          AbsorbPointer(
            absorbing: running || widget.controller.isBusy,
""",
    """          const Divider(height: 28),
          if (!_preferencesLoaded) ...[
            const LinearProgressIndicator(),
            const SizedBox(height: 12),
          ],
          AbsorbPointer(
            absorbing:
                running || widget.controller.isBusy || !_preferencesLoaded,
""",
)
replace_once(
    auto,
    """                          onSelected: (selected) => setState(() {
                            if (selected) {
                              _enabledSymbols.add(symbol);
                            } else {
                              _enabledSymbols.remove(symbol);
                            }
                          }),
""",
    """                          onSelected: (selected) => _mutateAndSave(() {
                            if (selected) {
                              _enabledSymbols.add(symbol);
                            } else {
                              _enabledSymbols.remove(symbol);
                            }
                          }),
""",
)
replace_once(
    auto,
    """                      for (final timeframe in const ['15m', '1h', '4h'])
""",
    """                      for (final timeframe in const ['5m', '15m', '1h', '4h'])
""",
)
replace_once(
    auto,
    """                          onSelected: (selected) => setState(() {
                            if (selected) {
                              _enabledTimeframes.add(timeframe);
                            } else {
                              _enabledTimeframes.remove(timeframe);
                            }
                          }),
""",
    """                          onSelected: (selected) => _mutateAndSave(() {
                            if (selected) {
                              _enabledTimeframes.add(timeframe);
                            } else {
                              _enabledTimeframes.remove(timeframe);
                            }
                          }),
""",
)
replace_once(
    auto,
    """                    onMinus: () =>
                        setState(() => _leverage = math.max(1, _leverage - 1)),
                    onPlus: () => setState(
                      () => _leverage = math.min(125, _leverage + 1),
                    ),
""",
    """                    onMinus: () => _mutateAndSave(
                      () => _leverage = math.max(1, _leverage - 1),
                    ),
                    onPlus: () => _mutateAndSave(
                      () => _leverage = math.min(125, _leverage + 1),
                    ),
""",
)
replace_once(
    auto,
    """                    onMinus: () => setState(
                      () => _riskPercent = math.max(0.05, _riskPercent - 0.05),
                    ),
                    onPlus: () => setState(
                      () => _riskPercent = math.min(0.25, _riskPercent + 0.05),
                    ),
""",
    """                    onMinus: () => _mutateAndSave(() {
                      final step = _riskPercent > 0.50 ? 0.25 : 0.05;
                      _riskPercent = math.max(0.05, _riskPercent - step);
                    }),
                    onPlus: () => _mutateAndSave(() {
                      final step = _riskPercent >= 0.50 ? 0.25 : 0.05;
                      _riskPercent = math.min(2.0, _riskPercent + step);
                    }),
""",
)
replace_once(
    auto,
    """                    onMinus: () => setState(
                      () => _dailyLossLimit = math.max(
                        0.25,
                        _dailyLossLimit - 0.25,
                      ),
                    ),
                    onPlus: () => setState(
                      () =>
                          _dailyLossLimit = math.min(2, _dailyLossLimit + 0.25),
                    ),
""",
    """                    onMinus: () => _mutateAndSave(() {
                      final step = _dailyLossLimit > 3 ? 1.0 : 0.25;
                      _dailyLossLimit = math.max(0.25, _dailyLossLimit - step);
                    }),
                    onPlus: () => _mutateAndSave(() {
                      final step = _dailyLossLimit >= 3 ? 1.0 : 0.25;
                      _dailyLossLimit = math.min(10, _dailyLossLimit + step);
                    }),
""",
)
replace_once(
    auto,
    """                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
""",
    """                  ),
                  if (_riskPercent > 0.50 ||
                      _dailyLossLimit > 3 ||
                      _leverage > 25) ...[
                    const SizedBox(height: 8),
                    _BoundaryNotice(
                      text: _t(
                        'حالت پیشرفته فعال است. اهرم بالا فقط مارجین را کم می‌کند و فاصله لیکویید را کاهش می‌دهد؛ ریسک بالاتر مستقیماً زیان مجاز هر معامله را افزایش می‌دهد.',
                        'Advanced settings are active. Higher leverage reduces required margin but narrows liquidation distance; higher risk directly increases allowed loss per trade.',
                      ),
                      color: QuantaraColors.warning,
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
""",
)
replace_once(
    auto,
    """  Future<void> _confirmStart() async {
    if (!widget.accountController.isConnected) {
""",
    """  Future<void> _confirmStart() async {
    if (!_preferencesLoaded) return;
    if (!widget.accountController.isConnected) {
""",
)
replace_once(
    auto,
    """    final confirmed = await showDialog<bool>(
""",
    """    if (_riskPercent > 0.50 ||
        _dailyLossLimit > 3 ||
        _leverage > 25) {
      final advancedConfirmed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: Text(_t('تأیید تنظیمات پرریسک', 'Confirm advanced risk')),
          content: Text(
            _t(
              'این تنظیمات می‌توانند زیان واقعی را سریع‌تر افزایش دهند. Quantara استاپ را دورتر نمی‌کند، بعد از ضرر ریسک را بالا نمی‌برد و همچنان فقط یک پوزیشن Isolated باز می‌کند. ادامه می‌دهی؟',
              'These settings can increase real losses faster. Quantara will not widen stops, increase risk after losses, or open more than one isolated position. Continue?',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(_t('بازگشت', 'Go back')),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: QuantaraColors.danger,
              ),
              onPressed: () => Navigator.pop(context, true),
              child: Text(_t('ریسک را می‌پذیرم', 'I accept the risk')),
            ),
          ],
        ),
      );
      if (advancedConfirmed != true || !mounted) return;
    }
    final confirmed = await showDialog<bool>(
""",
)
replace_once(
    auto,
    """    if (confirmed != true || !mounted) return;
    final started = await widget.controller.start(
""",
    """    if (confirmed != true || !mounted) return;
    await _persistPreferences();
    if (!mounted) return;
    final started = await widget.controller.start(
""",
)
replace_once(
    auto,
    """                    title: Text(event.message),
""",
    """                    title: Text(
                      LocalLiveMessageLocalizer.localize(
                        event.message,
                        persian: _fa,
                      ),
                    ),
""",
)

# ---------------------------------------------------------------------------
# Bounded advanced limits and 5m execution support.
# ---------------------------------------------------------------------------
models = 'src/client/quantara_app/lib/features/auto_trade/domain/local_live_trade_models.dart'
replace_once(
    models,
    """        timeframes.any((item) => !const {'15m', '1h', '4h'}.contains(item))) {
""",
    """        timeframes.any(
          (item) => !const {'5m', '15m', '1h', '4h'}.contains(item),
        )) {
""",
)
replace_once(
    models,
    """    if (!riskPercent.isFinite || riskPercent <= 0 || riskPercent > 0.25) {
      throw const FormatException(
        'Local live canary risk must be between 0.01% and 0.25%.',
      );
    }
    if (!dailyLossLimitPercent.isFinite ||
        dailyLossLimitPercent < 0.25 ||
        dailyLossLimitPercent > 2) {
      throw const FormatException(
        'Daily loss limit must be between 0.25% and 2%.',
      );
""",
    """    if (!riskPercent.isFinite || riskPercent < 0.05 || riskPercent > 2) {
      throw const FormatException(
        'Local live risk must be between 0.05% and 2%.',
      );
    }
    if (!dailyLossLimitPercent.isFinite ||
        dailyLossLimitPercent < 0.25 ||
        dailyLossLimitPercent > 10) {
      throw const FormatException(
        'Daily loss limit must be between 0.25% and 10%.',
      );
""",
)

owner_models = 'src/client/quantara_app/lib/features/owner_alpha/domain/owner_alpha_models.dart'
replace_once(
    owner_models,
    """  Duration get validityWindow => switch (timeframe) {
    '15m' => const Duration(minutes: 45),
""",
    """  Duration get validityWindow => switch (timeframe) {
    '5m' => const Duration(minutes: 15),
    '15m' => const Duration(minutes: 45),
""",
)

controller = 'src/client/quantara_app/lib/features/owner_alpha/application/owner_alpha_controller.dart'
replace_once(
    controller,
    "static const timeframes = ['15m', '1h', '4h', '1D'];",
    "static const timeframes = ['5m', '15m', '1h', '4h', '1D'];",
)

repo = 'src/client/quantara_app/lib/features/owner_alpha/data/bitunix_owner_alpha_repository.dart'
replace_once(
    repo,
    "static const supportedTimeframes = ['15m', '1h', '4h', '1D'];\n  static const opportunityTimeframes = ['15m', '1h', '4h'];",
    "static const supportedTimeframes = ['5m', '15m', '1h', '4h', '1D'];\n  static const opportunityTimeframes = ['5m', '15m', '1h', '4h'];",
)
replace_once(
    repo,
    """            analyses['1h'] ??
            analyses['15m'] ??
            analyses['4h'] ??
""",
    """            analyses['1h'] ??
            analyses['15m'] ??
            analyses['5m'] ??
            analyses['4h'] ??
""",
)
replace_once(
    repo,
    """    return switch (timeframe) {
      '15m' => const Duration(minutes: 15),
""",
    """    return switch (timeframe) {
      '5m' => const Duration(minutes: 5),
      '15m' => const Duration(minutes: 15),
""",
)

priority = 'src/client/quantara_app/lib/features/owner_alpha/data/signal_timeframe_priority.dart'
replace_once(
    priority,
    """        : group.any((entry) => entry.timeframe == '15m')
        ? '15m'
        : group.any((entry) => entry.timeframe == '1D')
""",
    """        : group.any((entry) => entry.timeframe == '15m')
        ? '15m'
        : group.any((entry) => entry.timeframe == '5m')
        ? '5m'
        : group.any((entry) => entry.timeframe == '1D')
""",
)

chart = 'src/client/quantara_app/lib/features/market_analysis/presentation/tradingview_lightweight_chart.dart'
replace_once(
    chart,
    """  static Duration _timeframeDuration(String timeframe) => switch (timeframe) {
    '15m' => const Duration(minutes: 15),
""",
    """  static Duration _timeframeDuration(String timeframe) => switch (timeframe) {
    '5m' => const Duration(minutes: 5),
    '15m' => const Duration(minutes: 15),
""",
)

# ---------------------------------------------------------------------------
# Real and hypothetical exit ladder: TP1 is the largest reduction, SL moves
# beyond break-even after TP1, then the runner stop moves to TP1 after TP2.
# ---------------------------------------------------------------------------
service = 'src/client/quantara_app/lib/features/auto_trade/application/local_live_trade_service.dart'
replace_once(
    service,
    """  DateTime? _lastScanAt;
  DateTime? _lastExchangeSync;
""",
    """  DateTime? _lastScanAt;
  DateTime? _lastExchangeSync;
  String? _lastAuditFingerprint;
  DateTime? _lastAuditAt;

  static const _targetFractions = <double>[0.40, 0.30, 0.30];
""",
)
replace_once(
    service,
    """      final idea = _pickPrimaryIdea(ideas);
      if (idea == null || _executedSetupIds.contains(idea.setupId)) return;
      if (idea.isExpiredAt(DateTime.now().toUtc()) ||
          idea.stopLoss == null ||
          idea.targets.length < 3 ||
          idea.entryLower == null ||
          idea.entryUpper == null) {
        return;
      }
""",
    """      if (ideas.isEmpty) {
        _auditEvent(
          'scan_skip',
          'No actionable setup passed the selected strategy and timeframe filters.',
        );
        return;
      }
      final idea = _pickPrimaryIdea(ideas);
      if (idea == null) {
        _auditEvent(
          'scan_skip',
          'Actionable setups were skipped because selected timeframes disagreed on direction.',
        );
        return;
      }
      if (_executedSetupIds.contains(idea.setupId)) {
        _auditEvent(
          'scan_skip',
          'The highest-ranked setup was already executed in this local-live history.',
          symbol: idea.symbol,
        );
        return;
      }
      if (idea.isExpiredAt(DateTime.now().toUtc()) ||
          idea.stopLoss == null ||
          idea.targets.length < 3 ||
          idea.entryLower == null ||
          idea.entryUpper == null) {
        _auditEvent(
          'scan_skip',
          'The highest-ranked setup was expired or missing a complete protected plan.',
          symbol: idea.symbol,
        );
        return;
      }
""",
)
replace_once(
    service,
    """      if (markPrice < lower || markPrice > upper) return;
      final rules = await exchange.fetchInstrumentRules(idea.symbol);
      if (!rules.open || !rules.apiSupported) return;
""",
    """      if (markPrice < lower || markPrice > upper) {
        _auditEvent(
          'scan_skip',
          'The highest-ranked setup is valid but the live mark price is outside its entry zone.',
          symbol: idea.symbol,
        );
        return;
      }
      final rules = await exchange.fetchInstrumentRules(idea.symbol);
      if (!rules.open || !rules.apiSupported) {
        _auditEvent(
          'scan_skip',
          'The selected instrument is closed or unavailable for API futures execution.',
          symbol: idea.symbol,
        );
        return;
      }
""",
)
replace_once(
    service,
    """      if (quantity < rules.minimumQuantity * 3 ||
          quantity > rules.maximumMarketQuantity ||
          quantity <= 0) {
        return;
      }
      final requiredMargin = quantity * entryPrice / leverage;
      if (requiredMargin * 1.15 > account.available) return;
""",
    """      if (quantity < rules.minimumQuantity / _targetFractions.last ||
          quantity > rules.maximumMarketQuantity ||
          quantity <= 0) {
        _auditEvent(
          'scan_skip',
          'Calculated position size is below the exchange minimum for three protected target tranches.',
          symbol: idea.symbol,
        );
        return;
      }
      final requiredMargin = quantity * entryPrice / leverage;
      if (requiredMargin * 1.15 > account.available) {
        _auditEvent(
          'scan_skip',
          'Available margin is below the protected entry requirement including the safety buffer.',
          symbol: idea.symbol,
        );
        return;
      }
""",
)
replace_once(
    service,
    """      final tp1Quantity = rules.roundQuantityDown(quantity * 0.35);
      final tp2Quantity = rules.roundQuantityDown(quantity * 0.35);
      final tp3Quantity = rules.roundQuantityDown(
        quantity - tp1Quantity - tp2Quantity,
      );
""",
    """      final tp1Quantity = rules.roundQuantityDown(
        quantity * _targetFractions[0],
      );
      final tp2Quantity = rules.roundQuantityDown(
        quantity * _targetFractions[1],
      );
      final tp3Quantity = rules.roundQuantityDown(
        quantity - tp1Quantity - tp2Quantity,
      );
""",
)
replace_once(
    service,
    """      if (managed.stage < 1 && ratio <= 0.70) {
""",
    """      if (managed.stage < 1 && ratio <= 0.62) {
""",
)
replace_once(
    service,
    """      if (next.stage < 2 && ratio <= 0.38) {
""",
    """      if (next.stage < 2 && ratio <= 0.32) {
""",
)
replace_once(
    service,
    """          'TP1 reduction observed; remaining position moved beyond break-even.',
""",
    """          'TP1 largest reduction observed; remaining position moved beyond break-even including costs.',
""",
)
replace_once(
    service,
    """          : timeframes.contains('1h')
          ? '1h'
          : '15m';
""",
    """          : timeframes.contains('1h')
          ? '1h'
          : timeframes.contains('15m')
          ? '15m'
          : '5m';
""",
)
replace_once(
    service,
    """  void _auditEvent(String type, String message, {String? symbol}) {
    _audit.add(
""",
    """  void _auditEvent(String type, String message, {String? symbol}) {
    final now = DateTime.now().toUtc();
    final fingerprint = '$type|${symbol ?? ''}|$message';
    if (_lastAuditFingerprint == fingerprint &&
        _lastAuditAt != null &&
        now.difference(_lastAuditAt!) < const Duration(minutes: 10)) {
      return;
    }
    _lastAuditFingerprint = fingerprint;
    _lastAuditAt = now;
    _audit.add(
""",
)
replace_once(
    service,
    """        at: DateTime.now().toUtc(),
""",
    """        at: now,
""",
)

outcome = 'src/client/quantara_app/lib/features/owner_alpha/data/signal_outcome_evaluator.dart'
replace_once(
    outcome,
    "const targetFractions = <double>[0.35, 0.35, 0.30];",
    "const targetFractions = <double>[0.40, 0.30, 0.30];",
)
replace_once(
    outcome,
    """    // This preserves the documented 35% / 35% / 30% paper-management policy
""",
    """    // This preserves the documented 40% / 30% / 30% paper-management policy
""",
)

# ---------------------------------------------------------------------------
# Localize audit rejection reasons.
# ---------------------------------------------------------------------------
localizer = 'src/client/quantara_app/lib/core/localization/local_live_message_localizer.dart'
replace_once(
    localizer,
    """      'Quantara could not confirm an affordable API-supported symbol from the selected allow-list.':
          'Quantara نتوانست میان نمادهای انتخاب‌شده، نمادی معتبر و متناسب با موجودی تأیید کند.',
""",
    """      'Quantara could not confirm an affordable API-supported symbol from the selected allow-list.':
          'Quantara نتوانست میان نمادهای انتخاب‌شده، نمادی معتبر و متناسب با موجودی تأیید کند.',
      'No actionable setup passed the selected strategy and timeframe filters.':
          'هیچ ستاپ قابل اجرایی از فیلتر استراتژی و تایم‌فریم‌های انتخاب‌شده عبور نکرد.',
      'Actionable setups were skipped because selected timeframes disagreed on direction.':
          'ستاپ‌های قابل بررسی به‌دلیل تضاد جهت در تایم‌فریم‌های انتخاب‌شده رد شدند.',
      'The highest-ranked setup was already executed in this local-live history.':
          'ستاپ برتر قبلاً در تاریخچه ترید محلی اجرا شده و دوباره وارد نمی‌شود.',
      'The highest-ranked setup was expired or missing a complete protected plan.':
          'ستاپ برتر منقضی شده یا برنامه کامل Entry، SL و سه TP را ندارد.',
      'The highest-ranked setup is valid but the live mark price is outside its entry zone.':
          'ستاپ معتبر است، اما قیمت لحظه‌ای هنوز داخل محدوده ورود قرار ندارد.',
      'The selected instrument is closed or unavailable for API futures execution.':
          'نماد انتخاب‌شده بسته است یا اجرای فیوچرز API برای آن در دسترس نیست.',
      'Calculated position size is below the exchange minimum for three protected target tranches.':
          'حجم محاسبه‌شده برای تقسیم ایمن بین سه حد سود، از حداقل صرافی کمتر است.',
      'Available margin is below the protected entry requirement including the safety buffer.':
          'مارجین آزاد برای ورود محافظت‌شده همراه با حاشیه ایمنی کافی نیست.',
      'TP1 largest reduction observed; remaining position moved beyond break-even including costs.':
          'بخش اصلی حجم در TP1 بسته شد و استاپ باقی‌مانده با احتساب هزینه‌ها به محدوده ریسک‌فری منتقل شد.',
""",
)

# ---------------------------------------------------------------------------
# Tests.
# ---------------------------------------------------------------------------
write(
    'src/client/quantara_app/test/local_live_preferences_store_test.dart',
    r'''import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/auto_trade/data/local_live_preferences_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('persists every Local Live user control across reconstruction', () async {
    const store = SharedPreferencesLocalLivePreferencesStore();
    const value = LocalLivePreferences(
      symbols: ['BTCUSDT', 'ETHUSDT', 'XRPUSDT'],
      timeframes: {'5m', '15m'},
      leverage: 37,
      riskPercent: 1.25,
      dailyLossLimitPercent: 6,
    );

    await store.save(value);
    final restored = await store.load(
      availableSymbols: const ['BTCUSDT', 'ETHUSDT', 'XRPUSDT', 'SOLUSDT'],
    );

    expect(restored.symbols, value.symbols);
    expect(restored.timeframes, value.timeframes);
    expect(restored.leverage, 37);
    expect(restored.riskPercent, 1.25);
    expect(restored.dailyLossLimitPercent, 6);
  });

  test('normalizes stale symbols and out-of-range legacy values', () async {
    SharedPreferences.setMockInitialValues({
      'quantara.local-live.ui.symbols.v2': ['OLDUSDT', 'BTCUSDT'],
      'quantara.local-live.ui.timeframes.v2': ['2m', '5m'],
      'quantara.local-live.ui.leverage.v2': 500,
      'quantara.local-live.ui.risk.v2': 20.0,
      'quantara.local-live.ui.daily-loss.v2': 50.0,
    });
    const store = SharedPreferencesLocalLivePreferencesStore();

    final restored = await store.load(
      availableSymbols: const ['BTCUSDT', 'ETHUSDT'],
    );

    expect(restored.symbols, const ['BTCUSDT']);
    expect(restored.timeframes, const {'5m'});
    expect(restored.leverage, 125);
    expect(restored.riskPercent, 2);
    expect(restored.dailyLossLimitPercent, 10);
  });
}
''',
)

trade_models_test = 'src/client/quantara_app/test/local_live_trade_models_test.dart'
replace_once(
    trade_models_test,
    """  test('rejects risk above the 0.25 percent canary ceiling', () {
    expect(
      () => validConfiguration(riskPercent: 0.30).validate(),
      throwsFormatException,
    );
  });
""",
    """  test('accepts bounded advanced risk and rejects values above 2 percent', () {
    expect(
      validConfiguration(
        riskPercent: 2,
        dailyLossLimitPercent: 10,
      ).validate,
      returnsNormally,
    );
    expect(
      () => validConfiguration(riskPercent: 2.01).validate(),
      throwsFormatException,
    );
    expect(
      () => validConfiguration(dailyLossLimitPercent: 10.01).validate(),
      throwsFormatException,
    );
  });
""",
)
replace_once(
    trade_models_test,
    """  test('rejects unsupported execution timeframes', () {
    expect(
      () => validConfiguration(timeframes: const ['5m']).validate(),
      throwsFormatException,
    );
  });
""",
    """  test('accepts 5m and rejects unsupported execution timeframes', () {
    expect(
      validConfiguration(timeframes: const ['5m']).validate,
      returnsNormally,
    );
    expect(
      () => validConfiguration(timeframes: const ['2m']).validate(),
      throwsFormatException,
    );
  });
""",
)

outcome_test = 'src/client/quantara_app/test/signal_outcome_evaluator_test.dart'
replace_once(outcome_test, 'closeTo(13, 0.000001)', 'closeTo(12.5, 0.000001)')
replace_once(outcome_test, 'closeTo(4, 0.000001)', 'closeTo(3.5, 0.000001)')

write(
    'src/client/quantara_app/test/local_live_v1_0_1_source_test.dart',
    r'''import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('5m, persisted controls and protected 40/30/30 exits stay wired', () {
    final root = Directory.current.path;
    String source(String path) => File('$root/$path').readAsStringSync();

    final repository = source(
      'lib/features/owner_alpha/data/bitunix_owner_alpha_repository.dart',
    );
    final ui = source(
      'lib/features/owner_alpha/presentation/owner_alpha_auto_trade.dart',
    );
    final service = source(
      'lib/features/auto_trade/application/local_live_trade_service.dart',
    );

    expect(repository, contains("['5m', '15m', '1h', '4h', '1D']"));
    expect(repository, contains("'5m' => const Duration(minutes: 5)"));
    expect(ui, contains('SharedPreferencesLocalLivePreferencesStore'));
    expect(ui, contains("['5m', '15m', '1h', '4h']"));
    expect(service, contains('<double>[0.40, 0.30, 0.30]'));
    expect(service, contains('ratio <= 0.62'));
    expect(service, contains('ratio <= 0.32'));
  });
}
''',
)

# ---------------------------------------------------------------------------
# Version and candidate labels.
# ---------------------------------------------------------------------------
pubspec = 'src/client/quantara_app/pubspec.yaml'
replace_once(
    pubspec,
    '# Quantara 1.0 source candidate. Public Android publication remains gated by the owner-managed permanent signing key.\nversion: 1.0.0+100',
    '# Quantara 1.0.1 guarded Local Live hardening candidate. Public Stable signing remains owner-gated.\nversion: 1.0.1+101',
)

workflow = '.github/workflows/flutter-ci.yml'
workflow_text = read(workflow)
workflow_text = workflow_text.replace('1.0.0-preview', '1.0.1-preview')
workflow_text = workflow_text.replace('1.0.0', '1.0.1')
write(workflow, workflow_text)

# Remove one-shot automation from the implementation commit.
(ROOT / '.github/workflows/apply-v1-0-1.yml').unlink(missing_ok=True)
Path(__file__).unlink(missing_ok=True)
