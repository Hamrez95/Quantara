import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../owner_alpha/domain/profit_protection_policy.dart';

@immutable
class LocalLivePreferences {
  const LocalLivePreferences({
    required this.symbols,
    required this.timeframes,
    required this.leverage,
    required this.riskPercent,
    required this.dailyLossLimitPercent,
    this.targetAllocation = ProfitProtectionTargetAllocation.standard,
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
  final ProfitProtectionTargetAllocation targetAllocation;

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

  static const _symbolsKey = 'quantara.local-live.ui.symbols.v2';
  static const _timeframesKey = 'quantara.local-live.ui.timeframes.v2';
  static const _leverageKey = 'quantara.local-live.ui.leverage.v2';
  static const _riskKey = 'quantara.local-live.ui.risk.v2';
  static const _dailyLossKey = 'quantara.local-live.ui.daily-loss.v2';
  static const _tp1Key = 'quantara.local-live.ui.tp1-fraction.v3';
  static const _tp2Key = 'quantara.local-live.ui.tp2-fraction.v3';
  static const _tp3Key = 'quantara.local-live.ui.tp3-fraction.v3';

  @override
  Future<LocalLivePreferences> load({
    required List<String> availableSymbols,
  }) async {
    final defaults = LocalLivePreferences.defaults(availableSymbols);
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
      targetAllocation: targetAllocation,
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
      preferences.setDouble(_tp1Key, value.targetAllocation.tp1Fraction),
      preferences.setDouble(_tp2Key, value.targetAllocation.tp2Fraction),
      preferences.setDouble(_tp3Key, value.targetAllocation.tp3Fraction),
    ]);
  }
}
