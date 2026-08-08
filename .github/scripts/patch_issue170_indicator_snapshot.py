from pathlib import Path

ROOT = Path('src/client/quantara_app')


def replace_once(path: Path, old: str, new: str, label: str) -> None:
    text = path.read_text(encoding='utf-8')
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f'{label}: expected 1 match, found {count}')
    path.write_text(text.replace(old, new, 1), encoding='utf-8')


pagination = ROOT / 'lib/features/auto_trade/data/bitunix_private_api_client.dart'
replace_once(
    pagination,
    "final reachedReportedTotal = total != null && skip >= total!;",
    "final reachedReportedTotal = total != null && skip >= total;",
    'pagination unnecessary non-null assertion',
)

models = ROOT / 'lib/features/owner_alpha/domain/owner_alpha_models.dart'
replace_once(
    models,
    """    this.marketRegime = MarketRegime.transition,\n  });\n""",
    """    this.marketRegime = MarketRegime.transition,\n    this.indicatorSnapshot = const {},\n  });\n""",
    'TradeIdea constructor indicatorSnapshot',
)
replace_once(
    models,
    """  final MarketRegime marketRegime;\n\n  DateTime get createdAt => candleClosedAt;\n""",
    """  final MarketRegime marketRegime;\n  final Map<String, double> indicatorSnapshot;\n\n  DateTime get createdAt => candleClosedAt;\n""",
    'TradeIdea field indicatorSnapshot',
)

engine = ROOT / 'lib/features/owner_alpha/data/advanced_strategy_engine.dart'
text = engine.read_text(encoding='utf-8')
needle = "      atr: indicators.atr14,\n"
count = text.count(needle)
if count != 3:
    raise RuntimeError(f'advanced strategy build calls: expected 3 matches, found {count}')
text = text.replace(
    needle,
    "      atr: indicators.atr14,\n      indicators: indicators,\n",
)
engine.write_text(text, encoding='utf-8')
replace_once(
    engine,
    """    required double atr,\n    required List<double> targetMultiples,\n""",
    """    required double atr,\n    required TechnicalIndicatorSnapshot indicators,\n    required List<double> targetMultiples,\n""",
    'advanced strategy build signature',
)
replace_once(
    engine,
    """      marketRegime: marketRegime,\n    );\n  }\n\n  static Duration _durationFor(String timeframe) => switch (timeframe) {\n""",
    """      marketRegime: marketRegime,\n      indicatorSnapshot: _indicatorSnapshot(indicators),\n    );\n  }\n\n  static Map<String, double> _indicatorSnapshot(\n    TechnicalIndicatorSnapshot indicators,\n  ) => Map.unmodifiable({\n    'ema20': indicators.ema20,\n    'ema50': indicators.ema50,\n    'ema200': indicators.ema200,\n    'ema20SlopeAtr': indicators.ema20SlopeAtr,\n    'ema50SlopeAtr': indicators.ema50SlopeAtr,\n    'atr14': indicators.atr14,\n    'atrPercent': indicators.atrPercent,\n    'atrExpansionRatio': indicators.atrExpansionRatio,\n    'rsi14': indicators.rsi14,\n    'adx14': indicators.adx14,\n    'plusDi14': indicators.plusDi14,\n    'minusDi14': indicators.minusDi14,\n    'relativeVolume20': indicators.relativeVolume20,\n    'volumeZScore20': indicators.volumeZScore20,\n    'previousDonchianHigh20': indicators.previousDonchianHigh20,\n    'previousDonchianLow20': indicators.previousDonchianLow20,\n    'bollingerMiddle20': indicators.bollingerMiddle20,\n    'bollingerUpper20': indicators.bollingerUpper20,\n    'bollingerLower20': indicators.bollingerLower20,\n    'bollingerBandwidthPercent': indicators.bollingerBandwidthPercent,\n    'trendEfficiency20': indicators.trendEfficiency20,\n    'recentSwingHigh': indicators.recentSwingHigh,\n    'recentSwingLow': indicators.recentSwingLow,\n  });\n\n  static Duration _durationFor(String timeframe) => switch (timeframe) {\n""",
    'advanced strategy indicator snapshot helper',
)

journal_models = ROOT / 'lib/features/trading_journal/domain/trading_journal_models.dart'
replace_once(
    journal_models,
    """    this.clientId,\n    this.notes,\n  });\n""",
    """    this.clientId,\n    this.notes,\n    this.indicatorSnapshot = const {},\n  });\n""",
    'journal plan constructor indicator snapshot',
)
replace_once(
    journal_models,
    """  final String? clientId;\n  final String? notes;\n\n  Map<String, Object?> toJson() => {\n""",
    """  final String? clientId;\n  final String? notes;\n  final Map<String, double> indicatorSnapshot;\n\n  Map<String, Object?> toJson() => {\n""",
    'journal plan indicator snapshot field',
)
replace_once(
    journal_models,
    """    'clientId': clientId,\n    'notes': notes,\n  };\n""",
    """    'clientId': clientId,\n    'notes': notes,\n    'indicatorSnapshot': indicatorSnapshot,\n  };\n""",
    'journal plan indicator snapshot json',
)
replace_once(
    journal_models,
    """        clientId: _nullableString(json['clientId']),\n        notes: _nullableString(json['notes']),\n      );\n""",
    """        clientId: _nullableString(json['clientId']),\n        notes: _nullableString(json['notes']),\n        indicatorSnapshot: _doubleMap(json['indicatorSnapshot']),\n      );\n""",
    'journal plan indicator snapshot from json',
)
replace_once(
    journal_models,
    """List<String> _stringList(Object? value) => value is List<Object?>\n    ? value.map((item) => item.toString()).toList(growable: false)\n    : const [];\n\nMap<String, Object?> _objectMap(Object? value) {\n""",
    """List<String> _stringList(Object? value) => value is List<Object?>\n    ? value.map((item) => item.toString()).toList(growable: false)\n    : const [];\n\nMap<String, double> _doubleMap(Object? value) {\n  if (value is! Map<Object?, Object?>) return const {};\n  final result = <String, double>{};\n  for (final entry in value.entries) {\n    final parsed = _nullableDouble(entry.value);\n    if (parsed != null) result[entry.key.toString()] = parsed;\n  }\n  return Map.unmodifiable(result);\n}\n\nMap<String, Object?> _objectMap(Object? value) {\n""",
    'journal double map helper',
)

observer = ROOT / 'lib/features/trading_journal/application/local_live_journal_observer.dart'
replace_once(
    observer,
    """      clientId: managed.clientId,\n    );\n    if (!await _appendPlan(plan)) return;\n""",
    """      clientId: managed.clientId,\n      indicatorSnapshot: idea.indicatorSnapshot,\n    );\n    if (!await _appendPlan(plan)) return;\n""",
    'local live plan indicator snapshot',
)
replace_once(
    observer,
    """          'strategy': idea.strategy.name,\n        },\n""",
    """          'strategy': idea.strategy.name,\n          'indicatorSnapshot': idea.indicatorSnapshot,\n        },\n""",
    'signal created indicator snapshot evidence',
)

evidence = ROOT / 'lib/features/trading_journal/domain/trading_journal_evidence_packet.dart'
replace_once(
    evidence,
    """      'indicatorSnapshot': {\n        'captured': false,\n        'values': <String, Object?>{},\n        'note':\n            'Indicator values were not persisted at this journal boundary; no values were fabricated.',\n      },\n""",
    """      'indicatorSnapshot': {\n        'captured': plan.indicatorSnapshot.isNotEmpty,\n        'values': plan.indicatorSnapshot,\n        'note': plan.indicatorSnapshot.isEmpty\n            ? 'Indicator values were not persisted at this journal boundary; no values were fabricated.'\n            : 'Technical indicators captured from the closed-candle decision snapshot.',\n      },\n""",
    'evidence packet indicator snapshot',
)

new_test = ROOT / 'test/decision_indicator_snapshot_test.dart'
new_test.write_text(r'''import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/trading_journal/domain/trading_journal_models.dart';

void main() {
  test('journal plan persists immutable decision indicator snapshot', () {
    final plan = TradingJournalPlan(
      journalTradeId: 'indicator-test',
      setupId: 'setup',
      analysisVersion: '2.1',
      symbol: 'BTCUSDT',
      market: 'USDT_PERPETUAL',
      timeframe: '5m',
      direction: TradingJournalDirection.long,
      strategy: 'trendPullback',
      cadence: 'local-live',
      source: TradingJournalSource.localLive,
      decidedAt: DateTime.utc(2026, 8, 8),
      decisionPrice: 100,
      entryLower: 99.9,
      entryUpper: 100.1,
      plannedEntry: 100.1,
      originalStopLoss: 99,
      targets: const [102],
      expectedRMultiples: const [1.5],
      confidencePercent: 82,
      confluence: const ['trend'],
      regime: 'directionalTrend',
      rationale: 'test',
      invalidation: 'stop',
      accountEquity: 1000,
      riskPercent: 1,
      riskBudget: 10,
      leverage: 5,
      expectedMargin: 20,
      passedGates: const ['isolated-margin'],
      blockedGates: const [],
      appVersion: 'test',
      strategyRulesVersion: '2.1',
      indicatorSnapshot: const {
        'ema20': 100.2,
        'ema50': 99.8,
        'ema200': 95.0,
        'atr14': 1.1,
        'atrPercent': 1.1,
        'rsi14': 58.0,
        'adx14': 27.0,
        'plusDi14': 31.0,
        'minusDi14': 14.0,
        'relativeVolume20': 1.25,
        'trendEfficiency20': 0.62,
      },
    );

    final restored = TradingJournalPlan.fromJson(plan.toJson());
    expect(restored.indicatorSnapshot, plan.indicatorSnapshot);
    expect(restored.indicatorSnapshot['adx14'], 27.0);
    expect(restored.indicatorSnapshot['relativeVolume20'], 1.25);
  });

  test('legacy plan without indicators remains explicitly empty', () {
    final json = <String, Object?>{
      'journalTradeId': 'legacy',
      'setupId': 'legacy',
      'analysisVersion': '1',
      'symbol': 'SOLUSDT',
      'market': 'USDT_PERPETUAL',
      'timeframe': '5m',
      'direction': 'long',
      'strategy': 'trendPullback',
      'cadence': 'local-live',
      'source': 'localLive',
      'decidedAt': '2026-08-07T00:00:00Z',
      'decisionPrice': 74.0,
      'entryLower': 73.9,
      'entryUpper': 74.1,
      'plannedEntry': 74.0,
      'originalStopLoss': 73.69,
      'targets': <double>[74.9],
      'expectedRMultiples': <double>[1.5],
      'confidencePercent': 80.0,
      'confluence': <String>['legacy'],
      'regime': 'directionalTrend',
      'rationale': 'legacy',
      'invalidation': 'stop',
      'accountEquity': 1000.0,
      'riskPercent': 1.0,
      'riskBudget': 10.0,
      'leverage': 10,
      'expectedMargin': 2.0,
      'passedGates': <String>[],
      'blockedGates': <String>[],
      'appVersion': 'legacy',
      'strategyRulesVersion': 'legacy',
    };
    final restored = TradingJournalPlan.fromJson(json);
    expect(restored.indicatorSnapshot, isEmpty);
  });
}
''', encoding='utf-8')
