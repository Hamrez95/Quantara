import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/owner_alpha/data/realtime_candidate_registry.dart';
import 'package:quantara_app/features/owner_alpha/domain/owner_alpha_models.dart';
import 'package:quantara_app/features/owner_alpha/domain/realtime_candidate_models.dart';
import 'package:quantara_app/features/owner_alpha/domain/realtime_market_event_models.dart';

void main() {
  group('reconciliation safety', () {
    test('cannot move a cursor for another market stream', () {
      final registry = RealtimeCandidateRegistry();
      final candidate = _candidate();
      registry.register(candidate);

      expect(
        () => registry.markReconciled(
          setupId: candidate.setupId,
          streamKey: RealtimeStreamKey(symbol: 'ETHUSDT', timeframe: '1h'),
          exchangeTimestampUtc: DateTime.utc(2026, 8, 2, 12, 2),
          sequence: 10,
        ),
        throwsArgumentError,
      );
      expect(
        () => registry.markReconciled(
          setupId: candidate.setupId,
          streamKey: RealtimeStreamKey(symbol: 'BTCUSDT', timeframe: '15m'),
          exchangeTimestampUtc: DateTime.utc(2026, 8, 2, 12, 2),
          sequence: 10,
        ),
        throwsArgumentError,
      );
    });

    test('cannot move sequence or timestamp backwards', () {
      final registry = RealtimeCandidateRegistry();
      final candidate = _candidate();
      final streamKey = RealtimeStreamKey(
        symbol: candidate.symbol,
        timeframe: candidate.timeframe,
      );
      registry.register(candidate);
      registry.markReconciled(
        setupId: candidate.setupId,
        streamKey: streamKey,
        exchangeTimestampUtc: DateTime.utc(2026, 8, 2, 12, 5),
        sequence: 10,
      );

      expect(
        () => registry.markReconciled(
          setupId: candidate.setupId,
          streamKey: streamKey,
          exchangeTimestampUtc: DateTime.utc(2026, 8, 2, 12, 4),
          sequence: 11,
        ),
        throwsArgumentError,
      );
      expect(
        () => registry.markReconciled(
          setupId: candidate.setupId,
          streamKey: streamKey,
          exchangeTimestampUtc: DateTime.utc(2026, 8, 2, 12, 6),
          sequence: 9,
        ),
        throwsArgumentError,
      );
    });
  });
}

RealtimeOpportunityCandidate _candidate() =>
    RealtimeOpportunityCandidate.fromIdea(
      TradeIdea(
        symbol: 'BTCUSDT',
        timeframe: '1h',
        direction: TradeDirection.long,
        confidencePercent: 60,
        entryLower: 100,
        entryUpper: 101,
        stopLoss: 98,
        targets: const [102, 104, 106],
        riskReward: 2,
        maximumLoss: 50,
        positionSize: 1,
        notionalValue: 100,
        recommendedLeverage: 2,
        maximumSafeLeverage: 5,
        requiredMargin: 50,
        estimatedRoundTripCosts: 0.2,
        setupId: 'BTCUSDT|1h|long|reconciliation-safety',
        candleClosedAt: DateTime.utc(2026, 8, 2, 12),
        summary: 'test setup',
        invalidation: 'test invalidation',
        reasons: const ['test'],
        strategy: AnalysisStrategy.structureZones,
        strategyVersion: 'candidate-registry/1.0',
      ),
      detectedAtUtc: DateTime.utc(2026, 8, 2, 12, 1),
    );
