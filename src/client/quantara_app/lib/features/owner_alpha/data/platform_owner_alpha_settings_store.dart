import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/persistence/quantara_database_provider.dart';
import '../../../core/persistence/quantara_durable_database.dart';
import '../domain/owner_alpha_models.dart';

final class PlatformOwnerAlphaSettingsStore implements OwnerAlphaSettingsStore {
  const PlatformOwnerAlphaSettingsStore();

  static const _recordKey = 'owner-alpha-settings';
  static const _symbolsKey = 'quantara.owner-alpha.symbols';
  static const _capitalKey = 'quantara.owner-alpha.capital';
  static const _riskKey = 'quantara.owner-alpha.risk-percent';
  static const _strategyKey = 'quantara.owner-alpha.strategy';
  static const _cadenceKey = 'quantara.owner-alpha.cadence';
  static const _maximumSymbolCount = 30;

  @override
  Future<OwnerAlphaSettings?> load() async {
    try {
      final database = await QuantaraDatabaseProvider.instance;
      final record = await database.read(
        QuantaraDurableCategory.settings,
        _recordKey,
      );
      final durable = record == null ? null : _decode(record.payload);
      if (durable != null) return durable;

      final migrated = await _loadLegacy();
      if (migrated != null) await _saveDatabase(database, migrated);
      return migrated;
    } on Object {
      return _loadLegacy();
    }
  }

  @override
  Future<void> save(OwnerAlphaSettings settings) async {
    try {
      final database = await QuantaraDatabaseProvider.instance;
      await _saveDatabase(database, settings);
    } on Object {
      // The compatibility mirror below remains available during migration.
    }
    await _saveLegacy(settings);
  }

  static OwnerAlphaSettings? _decode(Map<String, Object?> payload) {
    final rawSymbols = payload['symbols'];
    final symbols = rawSymbols is List<Object?>
        ? rawSymbols.map((item) => item.toString()).toList(growable: false)
        : const <String>[];
    final capital = _number(payload['capital']);
    final riskPercent = _number(payload['riskPercent']);
    if (symbols.isEmpty ||
        symbols.length > _maximumSymbolCount ||
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
        .map((item) => item.trim().toUpperCase())
        .where((item) => RegExp(r'^[A-Z0-9]{5,24}$').hasMatch(item))
        .toSet()
        .take(_maximumSymbolCount)
        .toList(growable: false);
    if (normalized.isEmpty || normalized.length != symbols.length) return null;
    return OwnerAlphaSettings(
      symbols: normalized,
      capital: capital,
      riskPercent: riskPercent,
      strategy: AnalysisStrategy.values.firstWhere(
        (item) => item.name == payload['strategy']?.toString(),
        orElse: () => AnalysisStrategy.structureZones,
      ),
      cadence: SignalCadence.values.firstWhere(
        (item) => item.name == payload['cadence']?.toString(),
        orElse: () => SignalCadence.balanced,
      ),
    );
  }

  static Future<OwnerAlphaSettings?> _loadLegacy() async {
    try {
      final preferences = SharedPreferencesAsync();
      final symbols = await preferences.getStringList(_symbolsKey);
      final capital = await preferences.getDouble(_capitalKey);
      final riskPercent = await preferences.getDouble(_riskKey);
      return _decode({
        'symbols': symbols,
        'capital': capital,
        'riskPercent': riskPercent,
        'strategy': await preferences.getString(_strategyKey),
        'cadence': await preferences.getString(_cadenceKey),
      });
    } on Object {
      return null;
    }
  }

  static Future<void> _saveDatabase(
    QuantaraDurableDatabase database,
    OwnerAlphaSettings settings,
  ) async {
    final current = await database.read(
      QuantaraDurableCategory.settings,
      _recordKey,
    );
    await database.put(
      QuantaraDurableRecord(
        category: QuantaraDurableCategory.settings,
        key: _recordKey,
        schemaVersion: 1,
        revision: (current?.revision ?? 0) + 1,
        updatedAt: DateTime.now().toUtc(),
        payload: {
          'symbols': settings.symbols,
          'capital': settings.capital,
          'riskPercent': settings.riskPercent,
          'strategy': settings.strategy.name,
          'cadence': settings.cadence.name,
        },
      ),
    );
  }

  static Future<void> _saveLegacy(OwnerAlphaSettings settings) async {
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

double? _number(Object? value) =>
    value is num ? value.toDouble() : double.tryParse(value?.toString() ?? '');