import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quantara_app/features/owner_alpha/data/opportunity_discovery_universe.dart';
import 'package:quantara_app/features/owner_alpha/domain/owner_alpha_models.dart';
import 'package:quantara_app/features/owner_alpha/domain/realtime_candidate_models.dart';

void main() {
  test(
    'eligible Bitunix universe selects 100 symbols across five timeframes',
    () async {
      final validSymbols = List.generate(
        105,
        (index) => 'COIN${index.toString().padLeft(3, '0')}USDT',
      );
      final pairs = <Map<String, Object?>>[
        for (final symbol in validSymbols)
          {
            'symbol': symbol,
            'quote': 'USDT',
            'symbolStatus': 'OPEN',
            'isApiSupported': true,
          },
        {
          'symbol': 'WIDEUSDT',
          'quote': 'USDT',
          'symbolStatus': 'OPEN',
          'isApiSupported': true,
        },
        {
          'symbol': 'CLOSEDUSDT',
          'quote': 'USDT',
          'symbolStatus': 'STOP',
          'isApiSupported': true,
        },
        {
          'symbol': 'NOAPIUSDT',
          'quote': 'USDT',
          'symbolStatus': 'OPEN',
          'isApiSupported': false,
        },
        {
          'symbol': 'LOWVOLUSDT',
          'quote': 'USDT',
          'symbolStatus': 'OPEN',
          'isApiSupported': true,
        },
        {
          'symbol': 'BTCUSD',
          'quote': 'USD',
          'symbolStatus': 'OPEN',
          'isApiSupported': true,
        },
      ];
      final tickers = <Map<String, Object?>>[
        for (var index = 0; index < validSymbols.length; index++)
          {
            'symbol': validSymbols[index],
            'lastPrice': '100',
            'quoteVol': '${2000000 - index * 1000}',
          },
        {'symbol': 'WIDEUSDT', 'lastPrice': '100', 'quoteVol': '9999999'},
        {'symbol': 'CLOSEDUSDT', 'lastPrice': '100', 'quoteVol': '9000000'},
        {'symbol': 'NOAPIUSDT', 'lastPrice': '100', 'quoteVol': '8000000'},
        {'symbol': 'LOWVOLUSDT', 'lastPrice': '100', 'quoteVol': '100'},
        {'symbol': 'BTCUSD', 'lastPrice': '100', 'quoteVol': '7000000'},
      ];
      var depthRequests = 0;
      final client = MockClient((request) async {
        switch (request.url.path) {
          case '/api/v1/futures/market/trading_pairs':
            return _jsonResponse({'code': 0, 'data': pairs});
          case '/api/v1/futures/market/tickers':
            return _jsonResponse({'code': 0, 'data': tickers});
          case '/api/v1/futures/market/depth':
            depthRequests++;
            final symbol = request.url.queryParameters['symbol'];
            return _jsonResponse({
              'code': 0,
              'data': {
                'bids': [
                  ['100', '10'],
                ],
                'asks': [
                  [symbol == 'WIDEUSDT' ? '101' : '100.01', '10'],
                ],
              },
            });
          default:
            return http.Response('not found', 404);
        }
      });
      final source = BitunixOpportunityDiscoveryUniverseSource(
        client: client,
        delay: (_) async {},
        now: () => DateTime.utc(2026, 8, 15, 8),
      );

      final snapshot = await source.load();
      final universe = OpportunityDiscoveryRealtimeUniverse.build(snapshot);

      expect(snapshot.symbols, hasLength(100));
      expect(snapshot.symbols, isNot(contains('WIDEUSDT')));
      expect(
        snapshot.rejections[OpportunityUniverseRejectionReason.marketClosed],
        1,
      );
      expect(
        snapshot.rejections[OpportunityUniverseRejectionReason.apiUnsupported],
        1,
      );
      expect(
        snapshot.rejections[OpportunityUniverseRejectionReason
            .insufficientLiquidity],
        1,
      );
      expect(
        snapshot.rejections[OpportunityUniverseRejectionReason.spreadTooWide],
        1,
      );
      expect(depthRequests, greaterThanOrEqualTo(101));
      expect(universe.streams, hasLength(500));
      expect(
        universe.streams.where((stream) => stream.timeframe == '1D'),
        hasLength(100),
      );
      expect(
        universe.streams.where((stream) => stream.timeframe == '30m'),
        isEmpty,
      );
    },
  );

  test('coverage tracker keeps lifecycle funnel counts distinct', () {
    final tracker = OpportunityDiscoveryCoverageTracker(
      OpportunityUniverseSnapshot(
        symbols: List.generate(
          100,
          (index) => 'A${index.toString().padLeft(3, '0')}USDT',
        ),
        rejections: const {OpportunityUniverseRejectionReason.marketClosed: 2},
        generatedAtUtc: DateTime.utc(2026, 8, 15, 8),
      ),
    );
    final idea = TradeIdea(
      symbol: 'BTCUSDT',
      timeframe: '5m',
      direction: TradeDirection.long,
      confidencePercent: 70,
      entryLower: 100,
      entryUpper: 101,
      stopLoss: 98,
      targets: const [104, 106, 108],
      riskReward: 1.8,
      maximumLoss: 10,
      positionSize: 1,
      notionalValue: 100,
      recommendedLeverage: 2,
      maximumSafeLeverage: 3,
      requiredMargin: 50,
      estimatedRoundTripCosts: 0.2,
      setupId: 'coverage-setup',
      candleClosedAt: DateTime.utc(2026, 8, 15, 8),
      summary: 'test',
      invalidation: 'test',
      reasons: const ['test'],
    );
    final detected = RealtimeOpportunityCandidate.fromIdea(
      idea,
      detectedAtUtc: DateTime.utc(2026, 8, 15, 8),
    );
    tracker.recordCandidate(detected);
    expect(tracker.value.forming, 1);
    expect(tracker.value.armed, 0);

    final armed = detected.transition(
      nextStage: OpportunityStage.armed,
      reason: OpportunityTransitionReason.entryApproaching,
      atUtc: DateTime.utc(2026, 8, 15, 8, 1),
      observedPrice: 102,
      observedQualityScore: 72,
    );
    tracker.recordCandidate(armed);
    expect(tracker.value.forming, 0);
    expect(tracker.value.armed, 1);
    expect(tracker.value.rejected, 2);
    expect(tracker.value.configuredStreams, 500);
  });

  test('broad discovery source remains public read-only infrastructure', () {
    final source = File(
      'lib/features/owner_alpha/data/opportunity_discovery_universe.dart',
    ).readAsStringSync();
    for (final forbidden in [
      'bitunix_private_api_client',
      'local_live_trade_service',
      'auto_trade_controller',
      'placeOrder',
      'withdraw',
      'transfer',
    ]) {
      expect(source, isNot(contains(forbidden)));
    }
    expect(source, contains('/api/v1/futures/market/trading_pairs'));
    expect(source, contains('/api/v1/futures/market/tickers'));
    expect(source, contains('/api/v1/futures/market/depth'));
  });
}

http.Response _jsonResponse(Object value) => http.Response(
  jsonEncode(value),
  200,
  headers: const {'content-type': 'application/json'},
);
