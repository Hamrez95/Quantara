import 'package:shared_preferences/shared_preferences.dart';

import '../domain/strategy_lab_models.dart';

final class PlatformStrategyLabSessionStore implements StrategyLabSessionStore {
  const PlatformStrategyLabSessionStore();

  static const _strategyKey = 'quantara.strategy-lab.strategy';
  static const _symbolKey = 'quantara.strategy-lab.symbol';
  static const _timeframeKey = 'quantara.strategy-lab.timeframe';
  static const _windowKey = 'quantara.strategy-lab.window-minutes';
  static const _capitalKey = 'quantara.strategy-lab.initial-capital';
  static const _riskKey = 'quantara.strategy-lab.risk-percent';
  static const _startedKey = 'quantara.strategy-lab.started-at-ms';
  static const _endsKey = 'quantara.strategy-lab.ends-at-ms';

  @override
  Future<StrategyLabSession?> load() async {
    try {
      final preferences = SharedPreferencesAsync();
      final strategyName = await preferences.getString(_strategyKey);
      final symbol = await preferences.getString(_symbolKey);
      final timeframe = await preferences.getString(_timeframeKey);
      final windowMinutes = await preferences.getInt(_windowKey);
      final capital = await preferences.getDouble(_capitalKey);
      final risk = await preferences.getDouble(_riskKey);
      final startedAtMs = await preferences.getInt(_startedKey);
      final endsAtMs = await preferences.getInt(_endsKey);
      if (strategyName == null ||
          symbol == null ||
          timeframe == null ||
          windowMinutes == null ||
          capital == null ||
          risk == null ||
          startedAtMs == null ||
          endsAtMs == null) {
        return null;
      }
      final strategy = StrategyKind.values
          .where((item) => item.name == strategyName)
          .firstOrNull;
      if (strategy == null ||
          !RegExp(r'^[A-Z0-9]{5,24}$').hasMatch(symbol) ||
          windowMinutes <= 0 ||
          windowMinutes > const Duration(days: 30).inMinutes ||
          !capital.isFinite ||
          capital <= 0 ||
          !risk.isFinite ||
          risk <= 0 ||
          risk > 1) {
        return null;
      }
      final startedAt = DateTime.fromMillisecondsSinceEpoch(
        startedAtMs,
        isUtc: true,
      );
      final endsAt = DateTime.fromMillisecondsSinceEpoch(endsAtMs, isUtc: true);
      if (!endsAt.isAfter(startedAt)) {
        return null;
      }
      return StrategyLabSession(
        config: StrategyLabConfig(
          strategy: strategy,
          symbol: symbol,
          timeframe: timeframe,
          window: Duration(minutes: windowMinutes),
          initialCapital: capital,
          riskPercent: risk,
        ),
        startedAt: startedAt,
        endsAt: endsAt,
      );
    } on Object {
      return null;
    }
  }

  @override
  Future<void> save(StrategyLabSession? session) async {
    try {
      final preferences = SharedPreferencesAsync();
      if (session == null) {
        for (final key in const [
          _strategyKey,
          _symbolKey,
          _timeframeKey,
          _windowKey,
          _capitalKey,
          _riskKey,
          _startedKey,
          _endsKey,
        ]) {
          await preferences.remove(key);
        }
        return;
      }
      await preferences.setString(_strategyKey, session.config.strategy.name);
      await preferences.setString(_symbolKey, session.config.symbol);
      await preferences.setString(_timeframeKey, session.config.timeframe);
      await preferences.setInt(_windowKey, session.config.window.inMinutes);
      await preferences.setDouble(_capitalKey, session.config.initialCapital);
      await preferences.setDouble(_riskKey, session.config.riskPercent);
      await preferences.setInt(
        _startedKey,
        session.startedAt.millisecondsSinceEpoch,
      );
      await preferences.setInt(_endsKey, session.endsAt.millisecondsSinceEpoch);
    } on Object {
      // A failed journal write must not block market analysis.
    }
  }
}
