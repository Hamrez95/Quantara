import 'package:flutter/services.dart';

import '../domain/owner_alpha_models.dart';

final class PlatformOwnerAlphaSettingsStore implements OwnerAlphaSettingsStore {
  const PlatformOwnerAlphaSettingsStore({
    this._channel = const MethodChannel('quantara/settings'),
  });

  final MethodChannel _channel;

  @override
  Future<OwnerAlphaSettings?> load() async {
    try {
      final value = await _channel.invokeMapMethod<String, Object?>(
        'loadOwnerAlphaSettings',
      );
      if (value == null) {
        return null;
      }
      final rawSymbols = value['symbols'];
      final capital = value['capital'];
      final riskPercent = value['riskPercent'];
      if (rawSymbols is! List<Object?> ||
          capital is! num ||
          riskPercent is! num) {
        return null;
      }
      final symbols = rawSymbols.whereType<String>().toList(growable: false);
      if (symbols.isEmpty ||
          capital <= 0 ||
          riskPercent <= 0 ||
          riskPercent > 5) {
        return null;
      }
      return OwnerAlphaSettings(
        symbols: symbols,
        capital: capital.toDouble(),
        riskPercent: riskPercent.toDouble(),
      );
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  @override
  Future<void> save(OwnerAlphaSettings settings) async {
    try {
      await _channel.invokeMethod<void>('saveOwnerAlphaSettings', {
        'symbols': settings.symbols,
        'capital': settings.capital,
        'riskPercent': settings.riskPercent,
      });
    } on PlatformException {
      // Settings persistence is helpful but must never block live analysis.
    } on MissingPluginException {
      // Widget tests and non-Android previews intentionally have no channel.
    }
  }
}
