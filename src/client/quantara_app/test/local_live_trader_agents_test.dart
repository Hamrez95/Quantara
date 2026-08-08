import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quantara_app/features/auto_trade/data/bitunix_local_live_api_client.dart';
import 'package:quantara_app/features/auto_trade/domain/auto_trade_models.dart';
import 'package:quantara_app/features/auto_trade/domain/local_live_trade_models.dart';
import 'package:quantara_app/features/owner_alpha/domain/owner_alpha_models.dart';

void main() {
  const credentials = BitunixApiCredentials(
    apiKey: 'agent-api-key',
    secretKey: 'agent-secret-key',
  );

  LocalLiveTradeConfiguration configuration({
    List<String> symbols = const ['BTCUSDT'],
    List<String> timeframes = const ['1h'],
    int leverage = 10,
    double risk = 0.10,
    double dailyLoss = 1,
    int positions = 1,
    AnalysisStrategy strategy = AnalysisStrategy.structureZones,
    SignalCadence cadence = SignalCadence.balanced,
  }) => LocalLiveTradeConfiguration(
    symbols: symbols,
    timeframes: timeframes,
    leverage: leverage,
    riskPercent: risk,
    dailyLossLimitPercent: dailyLoss,
    maximumConcurrentPositions: positions,
    strategy: strategy,
    cadence: cadence,
    languageCode: 'fa',
  );

  group('Trader Agent Lab · local live canary', () {
    test('Arman conservative swing accepts tiny-risk 1h/4h canary', () {
      expect(
        configuration(
          symbols: const ['BTCUSDT', 'ETHUSDT'],
          timeframes: const ['1h', '4h'],
          risk: 0.05,
          leverage: 5,
        ).validate,
        returnsNormally,
      );
    });

    test(
      'Nima active scalper can select 15m without silently expanding slots',
      () {
        final config = configuration(
          symbols: const ['BTCUSDT', 'XRPUSDT'],
          timeframes: const ['15m'],
          leverage: 10,
        );
        expect(config.validate, returnsNormally);
        expect(config.maximumConcurrentPositions, 1);
      },
    );

    test('Sara risk manager caps risk and concurrency at supported bounds', () {
      expect(() => configuration(risk: 2.01).validate(), throwsFormatException);
      for (final positions in [1, 2, 3]) {
        expect(configuration(positions: positions).validate, returnsNormally);
      }
      expect(
        () => configuration(positions: 4).validate(),
        throwsFormatException,
      );
    });

    test(
      'Kian Bitunix operator verifies signed entry and emergency close paths',
      () async {
        final observedPaths = <String>[];
        final api = BitunixLocalLiveApiClient(
          client: MockClient((request) async {
            observedPaths.add(request.url.path);
            expect(request.headers['api-key'], credentials.apiKey);
            expect(request.headers['sign'], isNotEmpty);
            if (request.url.path.endsWith('/place_order')) {
              final body = jsonDecode(request.body) as Map<String, Object?>;
              expect(body['slPrice'], isNotNull);
              expect(body['reduceOnly'], false);
              return http.Response(
                jsonEncode({
                  'code': 0,
                  'data': {'orderId': 'entry-1', 'clientId': 'agent-entry'},
                  'msg': 'Success',
                }),
                200,
              );
            }
            expect(
              request.url.path,
              '/api/v1/futures/trade/flash_close_position',
            );
            return http.Response(
              jsonEncode({
                'code': 0,
                'data': {'positionId': 'position-1'},
                'msg': 'Success',
              }),
              200,
            );
          }),
          utcNow: () => DateTime.utc(2026, 7, 30, 21),
          secureRandom: Random(69),
        );

        await api.placeMarketEntry(
          symbol: 'BTCUSDT',
          quantity: 0.01,
          long: true,
          clientId: 'agent-entry',
          stopLoss: 59000,
          credentials: credentials,
        );
        await api.closePositionReduceOnly(
          position: const BitunixLivePosition(
            positionId: 'position-1',
            symbol: 'BTCUSDT',
            quantity: 0.01,
            side: 'LONG',
            marginMode: 'ISOLATION',
            positionMode: 'HEDGE',
            leverage: 10,
            averageOpenPrice: 60000,
            realizedPnl: 0,
            unrealizedPnl: 0,
            fee: 0,
            funding: 0,
          ),
          clientId: 'agent-emergency-close',
          credentials: credentials,
        );

        expect(observedPaths, [
          '/api/v1/futures/trade/place_order',
          '/api/v1/futures/trade/flash_close_position',
        ]);
      },
    );

    test(
      'Mina accessibility auditor finds explicit Start, Stop, and locked server labels',
      () {
        final view = File(
          'lib/features/owner_alpha/presentation/owner_alpha_auto_trade.dart',
        ).readAsStringSync();
        expect(view, contains('شروع ترید'));
        expect(view, contains('قطع ترید'));
        expect(view, contains('ترید شبانه سروری · قفل'));
        expect(view, contains('Expanded'));
        expect(view, isNot(contains('DropdownButton')));
      },
    );

    test(
      'Reza chaos trader forces exchange failures into a safe exception',
      () async {
        final api = BitunixLocalLiveApiClient(
          client: MockClient(
            (_) async => http.Response(
              jsonEncode({'code': 10004, 'msg': 'Signature error'}),
              401,
            ),
          ),
          secureRandom: Random(13),
        );

        expect(
          () => api.fetchOrderDetail(
            orderId: 'missing',
            credentials: credentials,
          ),
          throwsA(isA<LocalLiveTradeSafeException>()),
        );
      },
    );

    test(
      'Leila strategy researcher preserves selected strategy and cadence',
      () {
        final original = configuration(
          strategy: AnalysisStrategy.trendPullback,
          cadence: SignalCadence.active,
          timeframes: const ['15m', '1h', '4h'],
          positions: 2,
        );
        final restored = LocalLiveTradeConfiguration.fromJson(
          original.toJson(),
        );
        expect(restored.strategy, AnalysisStrategy.trendPullback);
        expect(restored.cadence, SignalCadence.active);
        expect(restored.timeframes, const ['15m', '1h', '4h']);
        expect(restored.maximumConcurrentPositions, 2);
      },
    );

    test(
      'Omid execution auditor verifies portfolio slots and full protection gates',
      () {
        final clientSource = File(
          'lib/features/auto_trade/data/bitunix_local_live_api_client.dart',
        ).readAsStringSync();
        final serviceSource = File(
          'lib/features/auto_trade/application/local_live_trade_service.dart',
        ).readAsStringSync();
        final manifest = File(
          'android/app/src/main/AndroidManifest.xml',
        ).readAsStringSync();

        expect(clientSource, isNot(contains('/withdraw')));
        expect(clientSource, isNot(contains('/transfer')));
        expect(clientSource, contains('flash_close_position'));
        expect(serviceSource, contains('Protective stop was not confirmed'));
        expect(
          serviceSource,
          contains('The complete SL/TP ladder was not confirmed'),
        );
        expect(
          serviceSource,
          contains('LocalLivePortfolioAdmission.hasExecutionSlot'),
        );
        expect(serviceSource, contains('portfolioGuard.reserve('));
        expect(serviceSource, contains('portfolioGuard.confirmReduction('));
        expect(serviceSource, contains('occupiedSymbols'));
        expect(
          serviceSource,
          isNot(contains('_managed.isEmpty &&\n          positions.isEmpty')),
        );
        expect(manifest, contains('FOREGROUND_SERVICE_SPECIAL_USE'));
      },
    );
  });
}
