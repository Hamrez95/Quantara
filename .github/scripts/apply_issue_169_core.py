from pathlib import Path
import re

ROOT = Path('src/client/quantara_app')
MODELS = ROOT / 'lib/features/auto_trade/domain/local_live_trade_models.dart'
PREFS = ROOT / 'lib/features/auto_trade/data/local_live_preferences_store.dart'
SERVICE = ROOT / 'lib/features/auto_trade/application/local_live_trade_service.dart'
OWNER = ROOT / 'lib/features/owner_alpha/application/owner_alpha_controller.dart'
TEST = ROOT / 'test/local_live_issue_169_core_test.dart'


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f'{label}: expected one match, found {count}')
    return text.replace(old, new, 1)


def regex_once(text: str, pattern: str, replacement: str, label: str, flags=0) -> str:
    next_text, count = re.subn(pattern, replacement, text, count=1, flags=flags)
    if count != 1:
        raise RuntimeError(f'{label}: expected one match, found {count}')
    return next_text


# ---------------------------------------------------------------------------
# Local Live domain/config/status models
# ---------------------------------------------------------------------------
models = MODELS.read_text(encoding='utf-8')
models = replace_once(
    models,
    """    required this.languageCode,
    this.targetAllocation = ProfitProtectionTargetAllocation.standard,
    this.scanIntervalSeconds = 60,
""",
    """    required this.languageCode,
    this.strategies = const [],
    this.targetAllocation = ProfitProtectionTargetAllocation.standard,
    this.scanIntervalSeconds = 60,
""",
    'configuration constructor strategies',
)
models = replace_once(
    models,
    """  final AnalysisStrategy strategy;
  final SignalCadence cadence;
  final String languageCode;
""",
    """  final AnalysisStrategy strategy;
  final List<AnalysisStrategy> strategies;
  final SignalCadence cadence;
  final String languageCode;

  List<AnalysisStrategy> get enabledStrategies {
    final result = <AnalysisStrategy>{...strategies};
    if (result.isEmpty) result.add(strategy);
    return List.unmodifiable(result);
  }
""",
    'configuration strategy fields',
)
models = models.replace(
    "if (symbols.isEmpty || symbols.length > 12)",
    "if (symbols.isEmpty || symbols.length > 30)",
    1,
)
models = models.replace(
    "Select between 1 and 12 symbols.",
    "Select between 1 and 30 symbols.",
    1,
)
models = replace_once(
    models,
    """    'strategy': strategy.name,
    'cadence': cadence.name,
""",
    """    'strategy': strategy.name,
    'strategies': enabledStrategies.map((item) => item.name).toList(),
    'cadence': cadence.name,
""",
    'configuration json strategies',
)
models = replace_once(
    models,
    """      strategy: AnalysisStrategy.values.firstWhere(
        (item) => item.name == json['strategy'],
        orElse: () => AnalysisStrategy.structureZones,
      ),
      cadence: SignalCadence.values.firstWhere(
""",
    """      strategy: AnalysisStrategy.values.firstWhere(
        (item) => item.name == json['strategy'],
        orElse: () => AnalysisStrategy.structureZones,
      ),
      strategies: (json['strategies'] as List<Object?>? ?? const [])
          .map((item) => AnalysisStrategy.values.where(
                (strategy) => strategy.name == item.toString(),
              ).firstOrNull)
          .whereType<AnalysisStrategy>()
          .toSet()
          .toList(growable: false),
      cadence: SignalCadence.values.firstWhere(
""",
    'configuration parse strategies',
)

summary_class = r'''
final class LocalLiveManagedPositionSummary {
  const LocalLiveManagedPositionSummary({
    required this.positionId,
    required this.symbol,
    required this.timeframe,
    required this.direction,
    required this.openedAt,
  });

  factory LocalLiveManagedPositionSummary.fromManaged(
    LocalLiveManagedPosition managed,
  ) => LocalLiveManagedPositionSummary(
    positionId: managed.positionId,
    symbol: managed.symbol,
    timeframe: managed.timeframe,
    direction: managed.direction,
    openedAt: managed.openedAt,
  );

  final String positionId;
  final String symbol;
  final String timeframe;
  final TradeDirection direction;
  final DateTime openedAt;

  Map<String, Object?> toJson() => {
    'positionId': positionId,
    'symbol': symbol,
    'timeframe': timeframe,
    'direction': direction.name,
    'openedAt': openedAt.toUtc().toIso8601String(),
  };

  factory LocalLiveManagedPositionSummary.fromJson(
    Map<String, Object?> json,
  ) => LocalLiveManagedPositionSummary(
    positionId: json['positionId']?.toString() ?? '',
    symbol: json['symbol']?.toString() ?? '',
    timeframe: json['timeframe']?.toString() ?? '',
    direction: TradeDirection.values.firstWhere(
      (item) => item.name == json['direction'],
      orElse: () => TradeDirection.wait,
    ),
    openedAt:
        DateTime.tryParse(json['openedAt']?.toString() ?? '')?.toUtc() ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
  );
}

'''
models = replace_once(
    models,
    'final class LocalLiveTradeStatus {\n',
    summary_class + 'final class LocalLiveTradeStatus {\n',
    'managed summary class insertion',
)
models = replace_once(
    models,
    """    this.managedPositionCount = 0,
    this.unmanagedPositionCount = 0,
""",
    """    this.managedPositionCount = 0,
    this.managedPositions = const [],
    this.unmanagedPositionCount = 0,
""",
    'status constructor summaries',
)
models = replace_once(
    models,
    """  final int managedPositionCount;

  /// Exchange positions that consume slots but are not yet safely recovered.
""",
    """  final int managedPositionCount;
  final List<LocalLiveManagedPositionSummary> managedPositions;

  /// Exchange positions that consume slots but are not yet safely recovered.
""",
    'status summary field',
)
models = replace_once(
    models,
    """    'managedPositionCount': managedPositionCount,
    'unmanagedPositionCount': unmanagedPositionCount,
""",
    """    'managedPositionCount': managedPositionCount,
    'managedPositions': managedPositions.map((item) => item.toJson()).toList(),
    'unmanagedPositionCount': unmanagedPositionCount,
""",
    'status summary json',
)
models = replace_once(
    models,
    """    managedPositionCount:
        (json['managedPositionCount'] as num?)?.toInt() ??
        (json['openPositionCount'] as num?)?.toInt() ??
        0,
    unmanagedPositionCount:
""",
    """    managedPositionCount:
        (json['managedPositionCount'] as num?)?.toInt() ??
        (json['openPositionCount'] as num?)?.toInt() ??
        0,
    managedPositions: List.unmodifiable(
      (json['managedPositions'] as List<Object?>? ?? const [])
          .whereType<Map<Object?, Object?>>()
          .map(
            (item) => LocalLiveManagedPositionSummary.fromJson(
              item.map((key, value) => MapEntry(key.toString(), value)),
            ),
          ),
    ),
    unmanagedPositionCount:
""",
    'status summary parse',
)
MODELS.write_text(models, encoding='utf-8')

# ---------------------------------------------------------------------------
# Durable Local Live preferences
# ---------------------------------------------------------------------------
prefs = PREFS.read_text(encoding='utf-8')
prefs = replace_once(
    prefs,
    "import '../../owner_alpha/domain/profit_protection_policy.dart';\n",
    """import '../../owner_alpha/domain/owner_alpha_models.dart';
import '../../owner_alpha/domain/profit_protection_policy.dart';
""",
    'preferences strategy import',
)
prefs = replace_once(
    prefs,
    """    required this.dailyLossLimitPercent,
    this.maximumConcurrentPositions = 2,
    this.targetAllocation = ProfitProtectionTargetAllocation.standard,
""",
    """    required this.dailyLossLimitPercent,
    this.maximumConcurrentPositions = 2,
    this.strategies = recommendedStrategies,
    this.targetAllocation = ProfitProtectionTargetAllocation.standard,
""",
    'preferences constructor strategies',
)
prefs = replace_once(
    prefs,
    """  static const maximumConcurrentPositionCount = 3;

  final List<String> symbols;
""",
    """  static const maximumConcurrentPositionCount = 3;
  static const maximumSymbolCount = 30;
  static const recommendedStrategies = <AnalysisStrategy>[
    AnalysisStrategy.structureZones,
    AnalysisStrategy.trendPullback,
    AnalysisStrategy.momentumContinuation,
  ];

  final List<String> symbols;
""",
    'preferences constants',
)
prefs = replace_once(
    prefs,
    """  final int maximumConcurrentPositions;
  final ProfitProtectionTargetAllocation targetAllocation;
""",
    """  final int maximumConcurrentPositions;
  final List<AnalysisStrategy> strategies;
  final ProfitProtectionTargetAllocation targetAllocation;
""",
    'preferences strategy field',
)
prefs = replace_once(
    prefs,
    """        maximumConcurrentPositions: 2,
      );
""",
    """        maximumConcurrentPositions: 2,
        strategies: recommendedStrategies,
      );
""",
    'preferences defaults strategies',
)
prefs = replace_once(
    prefs,
    """    final keptSymbols = symbols
        .map((item) => item.trim().toUpperCase())
        .where(allowed.contains)
        .toSet()
        .toList(growable: false);
""",
    """    final keptSymbols = symbols
        .map((item) => item.trim().toUpperCase())
        .where(allowed.contains)
        .toSet()
        .take(maximumSymbolCount)
        .toList(growable: false);
""",
    'preferences symbol ceiling',
)
prefs = replace_once(
    prefs,
    """    final keptTimeframes = timeframes
        .where(supportedTimeframes.contains)
        .toSet();
    return LocalLivePreferences(
""",
    """    final keptTimeframes = timeframes
        .where(supportedTimeframes.contains)
        .toSet();
    final keptStrategies = strategies.toSet().toList(growable: false);
    return LocalLivePreferences(
""",
    'preferences normalize strategies local',
)
prefs = replace_once(
    prefs,
    """      maximumConcurrentPositions: maximumConcurrentPositions.clamp(
        minimumConcurrentPositionCount,
        maximumConcurrentPositionCount,
      ),
      targetAllocation: ProfitProtectionTargetAllocation.fromFractions(
""",
    """      maximumConcurrentPositions: maximumConcurrentPositions.clamp(
        minimumConcurrentPositionCount,
        maximumConcurrentPositionCount,
      ),
      strategies: keptStrategies.isEmpty
          ? recommendedStrategies
          : List.unmodifiable(keptStrategies),
      targetAllocation: ProfitProtectionTargetAllocation.fromFractions(
""",
    'preferences normalized strategy result',
)
prefs = replace_once(
    prefs,
    """  static const _maximumPositionsKey =
      'quantara.local-live.ui.maximum-positions.v4';
""",
    """  static const _maximumPositionsKey =
      'quantara.local-live.ui.maximum-positions.v4';
  static const _strategiesKey = 'quantara.local-live.ui.strategies.v1';
""",
    'preferences strategies key',
)
prefs = replace_once(
    prefs,
    """    final allocation = payload['targetAllocation'];
    return LocalLivePreferences(
""",
    """    final allocation = payload['targetAllocation'];
    final strategies = payload['strategies'];
    return LocalLivePreferences(
""",
    'preferences decode strategies variable',
)
prefs = replace_once(
    prefs,
    """      maximumConcurrentPositions: _integer(
        payload['maximumConcurrentPositions'],
        fallback: defaults.maximumConcurrentPositions,
      ),
      targetAllocation: ProfitProtectionTargetAllocation.fromFractions(
""",
    """      maximumConcurrentPositions: _integer(
        payload['maximumConcurrentPositions'],
        fallback: defaults.maximumConcurrentPositions,
      ),
      strategies: strategies is List<Object?>
          ? strategies
                .map((value) => AnalysisStrategy.values.where(
                      (item) => item.name == value.toString(),
                    ).firstOrNull)
                .whereType<AnalysisStrategy>()
                .toSet()
                .toList(growable: false)
          : defaults.strategies,
      targetAllocation: ProfitProtectionTargetAllocation.fromFractions(
""",
    'preferences decode strategies result',
)
prefs = replace_once(
    prefs,
    """      maximumConcurrentPositions:
          preferences.getInt(_maximumPositionsKey) ??
          defaults.maximumConcurrentPositions,
      targetAllocation: targetAllocation,
""",
    """      maximumConcurrentPositions:
          preferences.getInt(_maximumPositionsKey) ??
          defaults.maximumConcurrentPositions,
      strategies: (preferences.getStringList(_strategiesKey) ?? const [])
          .map((value) => AnalysisStrategy.values.where(
                (item) => item.name == value,
              ).firstOrNull)
          .whereType<AnalysisStrategy>()
          .toSet()
          .toList(growable: false),
      targetAllocation: targetAllocation,
""",
    'preferences legacy strategies load',
)
prefs = replace_once(
    prefs,
    """          'maximumConcurrentPositions': value.maximumConcurrentPositions,
          'targetAllocation': value.targetAllocation.fractions,
""",
    """          'maximumConcurrentPositions': value.maximumConcurrentPositions,
          'strategies': value.strategies.map((item) => item.name).toList(),
          'targetAllocation': value.targetAllocation.fractions,
""",
    'preferences database strategy save',
)
prefs = replace_once(
    prefs,
    """      preferences.setInt(
        _maximumPositionsKey,
        value.maximumConcurrentPositions,
      ),
      preferences.setDouble(_tp1Key, value.targetAllocation.tp1Fraction),
""",
    """      preferences.setInt(
        _maximumPositionsKey,
        value.maximumConcurrentPositions,
      ),
      preferences.setStringList(
        _strategiesKey,
        value.strategies.map((item) => item.name).toList(growable: false),
      ),
      preferences.setDouble(_tp1Key, value.targetAllocation.tp1Fraction),
""",
    'preferences legacy strategy save',
)
PREFS.write_text(prefs, encoding='utf-8')

# ---------------------------------------------------------------------------
# Multi-strategy scanning and managed timeframe status projection
# ---------------------------------------------------------------------------
service = SERVICE.read_text(encoding='utf-8')
old_ideas = """      final ideas =
          <TradeIdea>[
                for (final result in snapshot.radar)
                  for (final entry in result.analysesByTimeframe.entries)
                    if (configuration.timeframes.contains(entry.key))
                      TradeIdeaFactory.create(
                        analysis: entry.value,
                        capital: account.estimatedEquity,
                        riskPercent: configuration.riskPercent,
                        languageCode: configuration.languageCode,
                        strategy: configuration.strategy,
                        cadence: configuration.cadence,
                        confluence: {
                          for (final direction
                              in result.analysesByTimeframe.entries)
                            direction.key: direction.value.direction,
                        },
                      ),
              ]
              .where(
                (idea) =>
                    idea.isActionable &&
                    !occupiedSymbols.contains(idea.symbol.trim().toUpperCase()),
              )
              .toList(growable: false);
"""
new_ideas = """      final ideasBySetupId = <String, TradeIdea>{};
      for (final result in snapshot.radar) {
        final confluence = {
          for (final direction in result.analysesByTimeframe.entries)
            direction.key: direction.value.direction,
        };
        for (final entry in result.analysesByTimeframe.entries) {
          if (!configuration.timeframes.contains(entry.key)) continue;
          for (final strategy in configuration.enabledStrategies) {
            final idea = TradeIdeaFactory.create(
              analysis: entry.value,
              capital: account.estimatedEquity,
              riskPercent: configuration.riskPercent,
              languageCode: configuration.languageCode,
              strategy: strategy,
              cadence: configuration.cadence,
              confluence: confluence,
            );
            if (!idea.isActionable ||
                occupiedSymbols.contains(idea.symbol.trim().toUpperCase())) {
              continue;
            }
            ideasBySetupId[idea.setupId] = idea;
          }
        }
      }
      final ideas = ideasBySetupId.values.toList(growable: false);
"""
service = replace_once(service, old_ideas, new_ideas, 'multi-strategy candidate generation')
service = replace_once(
    service,
    """    for (final idea in ideas) {
      grouped.putIfAbsent(idea.symbol, () => []).add(idea);
    }
""",
    """    for (final idea in ideas) {
      final key = '${idea.symbol}|${idea.strategy.name}';
      grouped.putIfAbsent(key, () => []).add(idea);
    }
""",
    'strategy-aware candidate grouping',
)
service = replace_once(
    service,
    """      managedPositionCount: _managed.length,
      unmanagedPositionCount: _unmanagedSymbols.length,
""",
    """      managedPositionCount: _managed.length,
      managedPositions: _managed
          .map(LocalLiveManagedPositionSummary.fromManaged)
          .toList(growable: false),
      unmanagedPositionCount: _unmanagedSymbols.length,
""",
    'publish managed timeframe summaries',
)
SERVICE.write_text(service, encoding='utf-8')

# ---------------------------------------------------------------------------
# Wider watchlist ceiling
# ---------------------------------------------------------------------------
owner = OWNER.read_text(encoding='utf-8')
owner = replace_once(
    owner,
    """  static const defaultSymbols = ['BTCUSDT', 'ETHUSDT', 'SOLUSDT', 'AVAXUSDT'];
  static final _symbolPattern = RegExp(r'^[A-Z0-9]{2,20}$');
""",
    """  static const defaultSymbols = ['BTCUSDT', 'ETHUSDT', 'SOLUSDT', 'AVAXUSDT'];
  static const maximumSymbols = 30;
  static final _symbolPattern = RegExp(r'^[A-Z0-9]{2,20}$');
""",
    'owner maximum symbol constant',
)
owner = owner.replace('.take(12)', '.take(maximumSymbols)')
owner = replace_once(
    owner,
    """    if (_symbols.length >= 12) {
      return _t(
        'حداکثر ۱۲ نماد قابل پایش است.',
        'You can monitor up to 12 symbols.',
      );
    }
""",
    """    if (_symbols.length >= maximumSymbols) {
      return _t(
        'حداکثر ۳۰ نماد قابل پایش است.',
        'You can monitor up to 30 symbols.',
      );
    }
""",
    'owner add symbol ceiling',
)
OWNER.write_text(owner, encoding='utf-8')

# ---------------------------------------------------------------------------
# Focused regression tests
# ---------------------------------------------------------------------------
TEST.write_text(r'''import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/auto_trade/data/local_live_preferences_store.dart';
import 'package:quantara_app/features/auto_trade/domain/local_live_trade_models.dart';
import 'package:quantara_app/features/owner_alpha/domain/owner_alpha_models.dart';
import 'package:quantara_app/features/owner_alpha/domain/profit_protection_policy.dart';

void main() {
  test('Local Live accepts a mobile-safe universe larger than twelve', () {
    final symbols = List.generate(20, (index) => 'Q${index}USDT');
    expect(() => _configuration(symbols: symbols).validate(), returnsNormally);
    expect(
      () => _configuration(
        symbols: List.generate(31, (index) => 'Q${index}USDT'),
      ).validate(),
      throwsFormatException,
    );
  });

  test('legacy single strategy configuration remains compatible', () {
    final legacy = _configuration().toJson()..remove('strategies');
    legacy['strategy'] = AnalysisStrategy.trendPullback.name;
    final restored = LocalLiveTradeConfiguration.fromJson(legacy);
    expect(restored.enabledStrategies, [AnalysisStrategy.trendPullback]);
  });

  test('multiple strategy configuration round-trips without duplicates', () {
    final original = _configuration(
      strategies: const [
        AnalysisStrategy.structureZones,
        AnalysisStrategy.trendPullback,
        AnalysisStrategy.structureZones,
      ],
    );
    final restored = LocalLiveTradeConfiguration.fromJson(original.toJson());
    expect(restored.enabledStrategies, [
      AnalysisStrategy.structureZones,
      AnalysisStrategy.trendPullback,
    ]);
  });

  test('empty preference strategies normalize to recommended preset', () {
    final normalized = LocalLivePreferences(
      symbols: const ['BTCUSDT'],
      timeframes: const {'1h'},
      leverage: 3,
      riskPercent: 0.25,
      dailyLossLimitPercent: 2,
      strategies: const [],
    ).normalized(const ['BTCUSDT', 'ETHUSDT']);

    expect(normalized.strategies, LocalLivePreferences.recommendedStrategies);
  });

  test('managed position timeframe survives status serialization', () {
    final status = LocalLiveTradeStatus(
      state: LocalLiveTradeState.running,
      updatedAt: DateTime.utc(2026, 8, 6),
      message: 'ok',
      managedPositionCount: 1,
      managedPositions: [
        LocalLiveManagedPositionSummary(
          positionId: 'p-1',
          symbol: 'GRAMUSDT',
          timeframe: '15m',
          direction: TradeDirection.short,
          openedAt: DateTime.utc(2026, 8, 6, 5),
        ),
      ],
    );
    final restored = LocalLiveTradeStatus.fromJson(status.toJson());
    expect(restored.managedPositions.single.timeframe, '15m');
    expect(restored.managedPositions.single.direction, TradeDirection.short);
  });

  test('service evaluates all enabled strategies and groups by strategy', () {
    final source = File(
      'lib/features/auto_trade/application/local_live_trade_service.dart',
    ).readAsStringSync();
    expect(
      source,
      contains('for (final strategy in configuration.enabledStrategies)'),
    );
    expect(source, contains("final key = '${idea.symbol}|${idea.strategy.name}'"));
    expect(source, contains('ideasBySetupId[idea.setupId] = idea;'));
    expect(
      source,
      contains('.map(LocalLiveManagedPositionSummary.fromManaged)'),
    );
  });
}

LocalLiveTradeConfiguration _configuration({
  List<String> symbols = const ['BTCUSDT'],
  List<AnalysisStrategy> strategies = const [],
}) => LocalLiveTradeConfiguration(
  symbols: symbols,
  timeframes: const ['15m', '1h'],
  leverage: 3,
  riskPercent: 0.25,
  dailyLossLimitPercent: 3,
  maximumConcurrentPositions: 3,
  strategy: AnalysisStrategy.structureZones,
  strategies: strategies,
  cadence: SignalCadence.balanced,
  languageCode: 'fa',
  targetAllocation: ProfitProtectionTargetAllocation.standard,
);
''', encoding='utf-8')
