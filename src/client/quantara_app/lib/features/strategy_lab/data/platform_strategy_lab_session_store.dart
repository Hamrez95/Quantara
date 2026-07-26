import 'package:flutter/services.dart';

import '../domain/strategy_lab_models.dart';

final class PlatformStrategyLabSessionStore implements StrategyLabSessionStore {
  const PlatformStrategyLabSessionStore({
    this._channel = const MethodChannel('quantara/settings'),
  });

  final MethodChannel _channel;

  @override
  Future<StrategyLabSession?> load() async {
    try {
      final value = await _channel.invokeMapMethod<String, Object?>(
        'loadStrategyLabSession',
      );
      if (value == null) {
        return null;
      }
      final strategyName = value['strategy'];
      final symbol = value['symbol'];
      final timeframe = value['timeframe'];
      final windowMinutes = value['windowMinutes'];
      final capital = value['initialCapital'];
      final risk = value['riskPercent'];
      final startedAtMs = value['startedAtMs'];
      final endsAtMs = value['endsAtMs'];
      if (strategyName is! String ||
          symbol is! String ||
          timeframe is! String ||
          windowMinutes is! int ||
          capital is! num ||
          risk is! num ||
          startedAtMs is! int ||
          endsAtMs is! int) {
        return null;
      }
      final strategy = StrategyKind.values
          .where((item) => item.name == strategyName)
          .firstOrNull;
      if (strategy == null ||
          !RegExp(r'^[A-Z0-9]{5,24}$').hasMatch(symbol) ||
          windowMinutes <= 0 ||
          windowMinutes > const Duration(days: 30).inMinutes ||
          capital <= 0 ||
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
          initialCapital: capital.toDouble(),
          riskPercent: risk.toDouble(),
        ),
        startedAt: startedAt,
        endsAt: endsAt,
      );
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  @override
  Future<void> save(StrategyLabSession? session) async {
    try {
      await _channel.invokeMethod<void>('saveStrategyLabSession', {
        if (session != null) ...{
          'strategy': session.config.strategy.name,
          'symbol': session.config.symbol,
          'timeframe': session.config.timeframe,
          'windowMinutes': session.config.window.inMinutes,
          'initialCapital': session.config.initialCapital,
          'riskPercent': session.config.riskPercent,
          'startedAtMs': session.startedAt.millisecondsSinceEpoch,
          'endsAtMs': session.endsAt.millisecondsSinceEpoch,
        },
      });
    } on PlatformException {
      // A failed journal write must not block market analysis.
    } on MissingPluginException {
      // Tests and web previews intentionally have no Android channel.
    }
  }
}
