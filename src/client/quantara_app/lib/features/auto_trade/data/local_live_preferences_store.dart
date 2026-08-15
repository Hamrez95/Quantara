import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/persistence/quantara_database_provider.dart';
import '../../../core/persistence/quantara_durable_database.dart';
import '../../owner_alpha/domain/owner_alpha_models.dart';
import '../../owner_alpha/domain/profit_protection_policy.dart';

@immutable
class LocalLivePreferences {
  const LocalLivePreferences({
    required this.symbols,
    required this.timeframes,
    required this.leverage,
    required this.riskPercent,
    required this.dailyLossLimitPercent,
    this.maximumConcurrentPositions = 2,
    this.strategies = recommendedStrategies,
    this.targetAllocation = ProfitProtectionTargetAllocation.standard,
  });

  static const supportedTimeframes = {'5m', '15m', '1h', '4h'};
  static const minimumLeverage = 1;
  static const maximumLeverage = 125;
  static const minimumRiskPercent = 0.05;
  static const maximumRiskPercent = 2.0;
  static const minimumDailyLossPercent = 0.25;
  static const maximumDailyLossPercent = 10.0;
  static const minimumConcurrentPositionCount = 1;
  static const maximumConcurrentPositionCount = 3;
  static const maximumSymbolCount = 30;
  static const recommendedStrategies = <AnalysisStrategy>[
    AnalysisStrategy.structureZones,
    AnalysisStrategy.trendPullback,
    AnalysisStrategy.momentumContinuation,
  ];

  final List<String> symbols;
  final Set<String> timeframes;
  final int leverage;
  final double riskPercent;
  final double dailyLossLimitPercent;
  final int maximumConcurrentPositions;
  final List<AnalysisStrategy> strategies;
  final ProfitProtectionTargetAllocation targetAllocation;

  factory LocalLivePreferences.defaults(List<String> availableSymbols) =>
      LocalLivePreferences(
        symbols: availableSymbols.take(4).toList(growable: false),
        timeframes: const {'1h', '4h'},
        leverage: 10,
        riskPercent: 0.10,
        dailyLossLimitPercent: 1,
        maximumConcurrentPositions: 2,
        strategies: recommendedStrategies,
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
        .take(maximumSymbolCount)
        .toList(growable: false);
    final defaults = LocalLivePreferences.defaults(availableSymbols);
    final keptTimeframes = timeframes
        .where(supportedTimeframes.contains)
        .toSet();
    final keptStrategies = strategies.toSet().toList(growable: false);
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
      maximumConcurrentPositions: maximumConcurrentPositions.clamp(
        minimumConcurrentPositionCount,
        maximumConcurrentPositionCount,
      ),
      strategies: keptStrategies.isEmpty
          ? recommendedStrategies
          : List.unmodifiable(keptStrategies),
      targetAllocation: ProfitProtectionTargetAllocation.fromFractions(
        targetAllocation.fractions,
      ),
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

  static const _recordKey = 'local-live-preferences';
  static const _symbolsKey = 'quantara.local-live.ui.symbols.v2';
  static const _timeframesKey = 'quantara.local-live.ui.timeframes.v2';
  static const _leverageKey = 'quantara.local-live.ui.leverage.v2';
  static const _riskKey = 'quantara.local-live.ui.risk.v2';
  static const _dailyLossKey = 'quantara.local-live.ui.daily-loss.v2';
  static const _maximumPositionsKey =
      'quantara.local-live.ui.maximum-positions.v4';
  static const _strategiesKey = 'quantara.local-live.ui.strategies.v1';
  static const _tp1Key = 'quantara.local-live.ui.tp1-fraction.v3';
  static const _tp2Key = 'quantara.local-live.ui.tp2-fraction.v3';
  static const _tp3Key = 'quantara.local-live.ui.tp3-fraction.v3';
  static final StreamController<LocalLivePreferences> _changes =
      StreamController<LocalLivePreferences>.broadcast(sync: true);

  /// Emits a revision only after the durable/compatibility save path finishes.
  /// Consumers compare the universe fingerprint so leverage/risk-only changes
  /// do not restart public realtime monitoring.
  static Stream<LocalLivePreferences> get changes => _changes.stream;

  @override
  Future<LocalLivePreferences> load({
    required List<String> availableSymbols,
  }) async {
    final defaults = LocalLivePreferences.defaults(availableSymbols);
    try {
      final database = await QuantaraDatabaseProvider.instance;
      final record = await database.read(
        QuantaraDurableCategory.settings,
        _recordKey,
      );
      if (record != null) {
        return _decode(record.payload, defaults).normalized(availableSymbols);
      }
      final migrated = await _loadLegacy(defaults);
      await _saveDatabase(database, migrated);
      return migrated.normalized(availableSymbols);
    } on Object {
      return (await _loadLegacy(defaults)).normalized(availableSymbols);
    }
  }

  @override
  Future<void> save(LocalLivePreferences value) async {
    try {
      final database = await QuantaraDatabaseProvider.instance;
      await _saveDatabase(database, value);
    } on Object {
      // The compatibility mirror below remains available during migration.
    }
    await _saveLegacy(value);
    _changes.add(value);
  }

  static LocalLivePreferences _decode(
    Map<String, Object?> payload,
    LocalLivePreferences defaults,
  ) {
    final symbols = payload['symbols'];
    final timeframes = payload['timeframes'];
    final allocation = payload['targetAllocation'];
    final strategies = payload['strategies'];
    return LocalLivePreferences(
      symbols: symbols is List<Object?>
          ? symbols.map((item) => item.toString()).toList(growable: false)
          : defaults.symbols,
      timeframes: timeframes is List<Object?>
          ? timeframes.map((item) => item.toString()).toSet()
          : defaults.timeframes,
      leverage: _integer(payload['leverage'], fallback: defaults.leverage),
      riskPercent: _number(
        payload['riskPercent'],
        fallback: defaults.riskPercent,
      ),
      dailyLossLimitPercent: _number(
        payload['dailyLossLimitPercent'],
        fallback: defaults.dailyLossLimitPercent,
      ),
      maximumConcurrentPositions: _integer(
        payload['maximumConcurrentPositions'],
        fallback: defaults.maximumConcurrentPositions,
      ),
      strategies: strategies is List<Object?>
          ? strategies
                .map(
                  (value) => AnalysisStrategy.values
                      .where((item) => item.name == value.toString())
                      .firstOrNull,
                )
                .whereType<AnalysisStrategy>()
                .toSet()
                .toList(growable: false)
          : defaults.strategies,
      targetAllocation: ProfitProtectionTargetAllocation.fromFractions(
        allocation is List<Object?>
            ? allocation
                  .map((item) => _number(item, fallback: 0))
                  .toList(growable: false)
            : defaults.targetAllocation.fractions,
      ),
    );
  }

  static Future<LocalLivePreferences> _loadLegacy(
    LocalLivePreferences defaults,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    final targetAllocation = ProfitProtectionTargetAllocation.fromFractions([
      preferences.getDouble(_tp1Key) ?? defaults.targetAllocation.tp1Fraction,
      preferences.getDouble(_tp2Key) ?? defaults.targetAllocation.tp2Fraction,
      preferences.getDouble(_tp3Key) ?? defaults.targetAllocation.tp3Fraction,
    ]);
    return LocalLivePreferences(
      symbols: preferences.getStringList(_symbolsKey) ?? defaults.symbols,
      timeframes:
          (preferences.getStringList(_timeframesKey) ??
                  defaults.timeframes.toList(growable: false))
              .toSet(),
      leverage: preferences.getInt(_leverageKey) ?? defaults.leverage,
      riskPercent: preferences.getDouble(_riskKey) ?? defaults.riskPercent,
      dailyLossLimitPercent:
          preferences.getDouble(_dailyLossKey) ??
          defaults.dailyLossLimitPercent,
      maximumConcurrentPositions:
          preferences.getInt(_maximumPositionsKey) ??
          defaults.maximumConcurrentPositions,
      strategies: (preferences.getStringList(_strategiesKey) ?? const [])
          .map(
            (value) => AnalysisStrategy.values
                .where((item) => item.name == value)
                .firstOrNull,
          )
          .whereType<AnalysisStrategy>()
          .toSet()
          .toList(growable: false),
      targetAllocation: targetAllocation,
    );
  }

  static Future<void> _saveDatabase(
    QuantaraDurableDatabase database,
    LocalLivePreferences value,
  ) async {
    final existing = await database.read(
      QuantaraDurableCategory.settings,
      _recordKey,
    );
    await database.put(
      QuantaraDurableRecord(
        category: QuantaraDurableCategory.settings,
        key: _recordKey,
        schemaVersion: 1,
        revision: (existing?.revision ?? 0) + 1,
        updatedAt: DateTime.now().toUtc(),
        payload: {
          'symbols': value.symbols,
          'timeframes': value.timeframes.toList(growable: false)..sort(),
          'leverage': value.leverage,
          'riskPercent': value.riskPercent,
          'dailyLossLimitPercent': value.dailyLossLimitPercent,
          'maximumConcurrentPositions': value.maximumConcurrentPositions,
          'strategies': value.strategies.map((item) => item.name).toList(),
          'targetAllocation': value.targetAllocation.fractions,
        },
      ),
    );
  }

  static Future<void> _saveLegacy(LocalLivePreferences value) async {
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
      preferences.setInt(
        _maximumPositionsKey,
        value.maximumConcurrentPositions,
      ),
      preferences.setStringList(
        _strategiesKey,
        value.strategies.map((item) => item.name).toList(growable: false),
      ),
      preferences.setDouble(_tp1Key, value.targetAllocation.tp1Fraction),
      preferences.setDouble(_tp2Key, value.targetAllocation.tp2Fraction),
      preferences.setDouble(_tp3Key, value.targetAllocation.tp3Fraction),
    ]);
  }
}

int _integer(Object? value, {required int fallback}) => value is num
    ? value.toInt()
    : int.tryParse(value?.toString() ?? '') ?? fallback;

double _number(Object? value, {required double fallback}) => value is num
    ? value.toDouble()
    : double.tryParse(value?.toString() ?? '') ?? fallback;
