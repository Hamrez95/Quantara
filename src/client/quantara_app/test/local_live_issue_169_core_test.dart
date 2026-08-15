import 'dart:io';

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

  test(
    'service evaluates all enabled strategies and economic adapter groups by strategy',
    () {
      final service = File(
        'lib/features/auto_trade/application/local_live_trade_service.dart',
      ).readAsStringSync();
      final ranking = File(
        'lib/features/auto_trade/application/local_live_economic_ranking.dart',
      ).readAsStringSync();

      expect(
        service,
        contains('for (final strategy in configuration.enabledStrategies)'),
      );
      expect(service, contains('ideasBySetupId[idea.setupId] = idea;'));
      expect(service, contains('LocalLiveEconomicRanking.rank('));
      expect(
        ranking,
        contains(
          r"final key = '${idea.symbol.trim().toUpperCase()}|${idea.strategy.name}'",
        ),
      );
      expect(ranking, contains('_resolveConflictAndPreferredTimeframe(ideas)'));
      expect(ranking, contains('EconomicOpportunityRanker.rank('));
      expect(
        service,
        contains('.map(LocalLiveManagedPositionSummary.fromManaged)'),
      );
    },
  );
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
