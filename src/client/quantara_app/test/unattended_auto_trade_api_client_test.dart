import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quantara_app/features/auto_trade/data/unattended_auto_trade_api_client.dart';
import 'package:quantara_app/features/auto_trade/domain/unattended_auto_trade_models.dart';

void main() {
  const token = '0123456789abcdef0123456789abcdef0123456789abcdef';
  final serverConfig = AutoTradeServerConfig(
    baseUrl: Uri.parse('https://trade.quantara.example'),
    controlToken: token,
  );

  test('status parses camel-case armed server state', () async {
    final client = UnattendedAutoTradeApiClient(
      client: MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/api/v1/auto-trade/status');
        expect(request.headers['X-Quantara-Control-Token'], token);
        return http.Response(
          jsonEncode({
            'runId': 'owner-default',
            'state': 'armed',
            'version': 4,
            'startedAt': '2026-07-30T12:00:00Z',
            'stoppedAt': null,
            'lastReason': 'Armed after preflight.',
            'updatedAt': '2026-07-30T12:00:01Z',
          }),
          200,
        );
      }),
    );

    final status = await client.fetchStatus(serverConfig);

    expect(status.state, UnattendedRunState.armed);
    expect(status.allowsNewEntries, isTrue);
    expect(status.version, 4);
  });

  test('start sends explicit limits and parses transition snapshot', () async {
    final client = UnattendedAutoTradeApiClient(
      client: MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/api/v1/auto-trade/start');
        final body = jsonDecode(request.body) as Map<String, Object?>;
        expect(body['requestId'], 'start-1');
        expect(body['allowedSymbols'], ['BTCUSDT', 'ETHUSDT']);
        expect(body['globalLeverage'], 10);
        expect(body['riskPerTradePercent'], 0.5);
        expect(body['maximumDailyLossPercent'], 2.0);
        expect(body['requireIsolatedMargin'], isTrue);
        expect(body['defaultStopPolicy'], 'protectAndManage');
        return http.Response(
          jsonEncode({
            'code': 'started',
            'snapshot': {
              'runId': 'owner-default',
              'state': 'armed',
              'version': 1,
              'startedAt': '2026-07-30T12:00:00Z',
              'stoppedAt': null,
              'lastReason': 'Armed.',
              'updatedAt': '2026-07-30T12:00:00Z',
            },
            'errors': <String>[],
          }),
          200,
        );
      }),
    );

    final snapshot = await client.start(
      serverConfig: serverConfig,
      requestId: 'start-1',
      configuration: const UnattendedRunConfiguration(
        allowedSymbols: ['BTCUSDT', 'ETHUSDT'],
        allowedStrategies: ['trendPullback'],
        allowedTimeframes: ['1h', '4h'],
        globalLeverage: 10,
        riskPerTradePercent: 0.5,
        maximumDailyLossPercent: 2,
        maximumWeeklyLossPercent: 5,
        maximumConcurrentPositions: 2,
        maximumMarginUsagePercent: 35,
        maximumCorrelatedExposurePercent: 50,
        maximumSlippagePercent: 0.2,
        maximumSignalAgeSeconds: 1200,
      ),
    );

    expect(snapshot.state, UnattendedRunState.armed);
  });

  test('server safety rejection exposes reasons without control token', () async {
    final client = UnattendedAutoTradeApiClient(
      client: MockClient(
        (request) async => http.Response(
          jsonEncode({
            'code': 'invalidConfiguration',
            'errors': [
              'Server live-execution feature flag is disabled.',
              'A reconciled live Bitunix execution cycle is not registered.',
            ],
          }),
          400,
        ),
      ),
    );

    await expectLater(
      () => client.start(
        serverConfig: serverConfig,
        requestId: 'start-1',
        configuration: const UnattendedRunConfiguration(
          allowedSymbols: ['BTCUSDT'],
          allowedStrategies: ['trendPullback'],
          allowedTimeframes: ['1h'],
          globalLeverage: 10,
          riskPerTradePercent: 0.5,
          maximumDailyLossPercent: 2,
          maximumWeeklyLossPercent: 5,
          maximumConcurrentPositions: 1,
          maximumMarginUsagePercent: 25,
          maximumCorrelatedExposurePercent: 25,
          maximumSlippagePercent: 0.2,
          maximumSignalAgeSeconds: 1200,
        ),
      ),
      throwsA(
        isA<UnattendedAutoTradeSafeException>().having(
          (error) => error.message,
          'message',
          contains('feature flag'),
        ),
      ),
    );
  });
}
