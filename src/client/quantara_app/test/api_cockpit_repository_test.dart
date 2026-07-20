import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quantara_app/features/cockpit/data/api_cockpit_repository.dart';
import 'package:quantara_app/features/cockpit/data/cockpit_repository_factory.dart';
import 'package:quantara_app/features/cockpit/data/mock_cockpit_repository.dart';
import 'package:quantara_app/features/cockpit/domain/cockpit_models.dart';

void main() {
  final now = DateTime.utc(2026, 7, 20, 18);

  test('parses a valid locked demo response', () async {
    final repository = ApiCockpitRepository(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode(_payload(now)),
          200,
          headers: const {'content-type': 'application/json; charset=utf-8'},
        ),
      ),
      endpoint: Uri.parse('https://api.example.com/api/v1/cockpit'),
      now: () => now,
    );

    final snapshot = await repository.load();

    expect(snapshot.environment, AppEnvironment.demo);
    expect(snapshot.marketStatus, contains('بدون اتصال'));
    expect(snapshot.watchlist.single.symbol, 'BTCUSDT');
    expect(snapshot.analysis.decision, AnalysisDecision.noTrade);
    expect(snapshot.paperAccount.equity, 100000);
  });

  test('rejects a response that enables a protected capability', () async {
    final payload = _payload(now);
    (payload['safety']! as Map<String, Object?>)['realMoneyEnabled'] = true;
    final repository = ApiCockpitRepository(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode(payload),
          200,
          headers: const {'content-type': 'application/json'},
        ),
      ),
      endpoint: Uri.parse('https://api.example.com/api/v1/cockpit'),
      now: () => now,
    );

    await expectLater(
      repository.load(),
      throwsA(isA<CockpitContractException>()),
    );
  });

  test('uses explicit demo data only for transport failure', () async {
    final primary = ApiCockpitRepository(
      client: MockClient((_) async => throw http.ClientException('offline')),
      endpoint: Uri.parse('https://api.example.com/api/v1/cockpit'),
      now: () => now,
    );
    final repository = FallbackCockpitRepository(
      primary: primary,
      fallback: const MockCockpitRepository(),
    );

    final snapshot = await repository.load();

    expect(snapshot.environment, AppEnvironment.demo);
    expect(snapshot.marketStatus, contains('داده نمایشی'));
  });

  test('does not hide malformed API data behind demo fallback', () async {
    final primary = ApiCockpitRepository(
      client: MockClient(
        (_) async => http.Response(
          '{}',
          200,
          headers: const {'content-type': 'application/json'},
        ),
      ),
      endpoint: Uri.parse('https://api.example.com/api/v1/cockpit'),
      now: () => now,
    );
    final repository = FallbackCockpitRepository(
      primary: primary,
      fallback: const MockCockpitRepository(),
    );

    await expectLater(
      repository.load(),
      throwsA(isA<CockpitContractException>()),
    );
  });

  test('rejects insecure non-local API configuration', () {
    expect(
      () => CockpitRepositoryFactory.create(
        apiBaseUrl: 'http://api.example.com',
        client: MockClient((_) async => http.Response('', 500)),
      ),
      throwsA(isA<CockpitContractException>()),
    );
  });
}

Map<String, Object?> _payload(DateTime now) {
  return <String, Object?>{
    'schemaVersion': 'cockpit-v1',
    'language': 'fa',
    'generatedAt': now.toIso8601String(),
    'environment': 'demo',
    'dataSourceMode': 'deterministic_demo',
    'marketStatusCode': 'demo_not_connected',
    'marketStatus': 'داده نمایشی · بدون اتصال به بازار زنده',
    'safety': <String, Object?>{
      'executionAuthority': 'none',
      'realMoneyEnabled': false,
      'orderSubmissionEnabled': false,
      'withdrawalEnabled': false,
    },
    'watchlist': <Object?>[
      <String, Object?>{
        'symbol': 'BTCUSDT',
        'displayName': 'Bitcoin',
        'price': 118420.5,
        'changePercent': 1.82,
        'spreadBps': 1.4,
        'observedAt': now
            .subtract(const Duration(seconds: 12))
            .toIso8601String(),
        'sparkline': <num>[117000, 117500, 118420.5],
      },
    ],
    'analysis': <String, Object?>{
      'symbol': 'BTCUSDT',
      'decision': 'no_trade',
      'confidencePercent': 71,
      'regime': 'uncertain',
      'summary': 'شرایط برای اقدام تازه مناسب نیست.',
      'reconsiderationCondition': 'پس از تأیید ساختار دوباره بررسی شود.',
      'generatedAt': now.subtract(const Duration(minutes: 2)).toIso8601String(),
      'factors': <Object?>[
        <String, Object?>{
          'code': 'distance_to_resistance',
          'title': 'فاصله تا مقاومت',
          'detail': 'فضای حرکت محدود است.',
          'impact': 'caution',
        },
      ],
    },
    'paperAccount': <String, Object?>{
      'currency': 'USDT',
      'isSimulated': true,
      'equity': 100000,
      'availableBalance': 96840,
      'usedMargin': 3160,
      'dailyPnl': 420.75,
      'openPositions': 2,
      'maximumDailyRiskPercent': 2,
      'currentDailyRiskPercent': 0.64,
    },
  };
}
