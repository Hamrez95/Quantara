import 'dart:convert';

import '../domain/owner_alpha_models.dart';

abstract final class OwnerAlphaSettingsTransfer {
  static const marker = 'QUANTARA_SETTINGS_V1:';

  static String encode(OwnerAlphaSettings settings) {
    final payload = <String, Object>{
      'schema': 1,
      'symbols': settings.symbols,
      'capital': settings.capital,
      'riskPercent': settings.riskPercent,
      'strategy': settings.strategy.name,
      'cadence': settings.cadence.name,
    };
    return '$marker${jsonEncode(payload)}';
  }

  static OwnerAlphaSettings decode(String value) {
    final normalized = value.trim();
    if (!normalized.startsWith(marker)) {
      throw const FormatException('unsupported Quantara settings backup');
    }
    final decoded = jsonDecode(normalized.substring(marker.length));
    if (decoded is! Map<String, dynamic> || decoded['schema'] != 1) {
      throw const FormatException('invalid Quantara settings schema');
    }
    final rawSymbols = decoded['symbols'];
    final capital = decoded['capital'];
    final risk = decoded['riskPercent'];
    final strategyName = decoded['strategy'];
    final cadenceName = decoded['cadence'];
    if (rawSymbols is! List ||
        capital is! num ||
        risk is! num ||
        strategyName is! String ||
        cadenceName is! String) {
      throw const FormatException('invalid Quantara settings fields');
    }
    final symbols = rawSymbols
        .whereType<String>()
        .map((item) => item.trim().toUpperCase())
        .where((item) => RegExp(r'^[A-Z0-9]{5,24}$').hasMatch(item))
        .toSet()
        .take(12)
        .toList(growable: false);
    final safeCapital = capital.toDouble();
    final safeRisk = risk.toDouble();
    if (symbols.isEmpty ||
        symbols.length != rawSymbols.length ||
        !safeCapital.isFinite ||
        safeCapital < 100 ||
        safeCapital > 100000000 ||
        !safeRisk.isFinite ||
        safeRisk < 0.1 ||
        safeRisk > 2) {
      throw const FormatException('unsafe Quantara settings values');
    }
    return OwnerAlphaSettings(
      symbols: symbols,
      capital: safeCapital,
      riskPercent: safeRisk,
      strategy: _enumByName(AnalysisStrategy.values, strategyName),
      cadence: _enumByName(SignalCadence.values, cadenceName),
    );
  }

  static T _enumByName<T extends Enum>(List<T> values, String name) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    throw FormatException('unknown enum value: $name');
  }
}
