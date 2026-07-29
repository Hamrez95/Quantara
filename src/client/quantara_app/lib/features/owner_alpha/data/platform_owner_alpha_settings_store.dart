import 'package:shared_preferences/shared_preferences.dart';

import '../domain/owner_alpha_models.dart';

final class PlatformOwnerAlphaSettingsStore implements OwnerAlphaSettingsStore {
  const PlatformOwnerAlphaSettingsStore();

  static const _symbolsKey = 'quantara.owner-alpha.symbols';
  static const _capitalKey = 'quantara.owner-alpha.capital';
  static const _riskKey = 'quantara.owner-alpha.risk-percent';
  static const _strategyKey = 'quantara.owner-alpha.strategy';
  static const _cadenceKey = 'quantara.owner-alpha.cadence';

  @override
  Future<OwnerAlphaSettings?> load() async {
    try {
      final preferences = SharedPreferencesAsync();
      final symbols = await preferences.getStringList(_symbolsKey);
      final capital = await preferences.getDouble(_capitalKey);
      final riskPercent = await preferences.getDouble(_riskKey);
      if (symbols == null ||
          symbols.isEmpty ||
          capital == null ||
          !capital.isFinite ||
          capital <= 0 ||
          riskPercent == null ||
          !riskPercent.isFinite ||
          riskPercent <= 0 ||
          riskPercent > 2) {
        return null;
      }
      final normalized = symbols
          .where((item) => RegExp(r'^[A-Z0-9]{5,24}$').hasMatch(item))
          .toSet()
          .take(12)
          .toList(growable: false);
      if (normalized.isEmpty || normalized.length != symbols.length) {
        return null;
      }
      final strategyName = await preferences.getString(_strategyKey);
      final cadenceName = await preferences.getString(_cadenceKey);
      return OwnerAlphaSettings(
        symbols: normalized,
        capital: capital,
        riskPercent: riskPercent,
        strategy: AnalysisStrategy.values.firstWhere(
          (item) => item.name == strategyName,
          orElse: () => AnalysisStrategy.structureZones,
        ),
        cadence: SignalCadence.values.firstWhere(
          (item) => item.name == cadenceName,
          orElse: () => SignalCadence.balanced,
        ),
      );
    } on Object {
      return null;
    }
  }

  @override
  Future<void> save(OwnerAlphaSettings settings) async {
    try {
      final preferences = SharedPreferencesAsync();
      await preferences.setStringList(_symbolsKey, settings.symbols);
      await preferences.setDouble(_capitalKey, settings.capital);
      await preferences.setDouble(_riskKey, settings.riskPercent);
      await preferences.setString(_strategyKey, settings.strategy.name);
      await preferences.setString(_cadenceKey, settings.cadence.name);
    } on Object {
      // Settings persistence is helpful but must never block live analysis.
    }
  }
}
