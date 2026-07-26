import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quantara_app/features/owner_alpha/data/bitunix_owner_alpha_repository.dart';

void main() {
  test('loads a bounded live radar and four selected timeframes', () async {
    var requestCount = 0;
    final client = MockClient((request) async {
      requestCount++;
      if (request.url.path.endsWith('/tickers')) {
        return _jsonResponse({
          'code': 0,
          'msg': 'Success',
          'data': [_ticker('BTCUSDT', 60000), _ticker('ETHUSDT', 3000)],
        });
      }
      final symbol = request.url.queryParameters['symbol']!;
      final base = symbol == 'BTCUSDT' ? 60000.0 : 3000.0;
      return _jsonResponse({
        'code': 0,
        'msg': 'Success',
        'data': _candles(base, request.url.queryParameters['interval']!),
      });
    });
    final repository = BitunixOwnerAlphaRepository(
      client: client,
      requestSpacing: Duration.zero,
      now: () => DateTime.utc(2026, 7, 21, 8),
    );

    final snapshot = await repository.scan(
      symbols: const ['BTCUSDT', 'ETHUSDT'],
      selectedSymbol: 'BTCUSDT',
      selectedTimeframe: '4h',
      capital: 10000,
      riskPercent: 1,
      languageCode: 'fa',
    );

    expect(requestCount, 6);
    expect(snapshot.radar, hasLength(2));
    expect(
      snapshot.timeframeDirections.keys,
      containsAll(['15m', '1h', '4h', '1D']),
    );
    expect(snapshot.selectedAnalysis.timeframe, '4h');
    expect(snapshot.selectedAnalysis.candles, hasLength(60));
    expect(snapshot.generatedAt.isUtc, isTrue);
  });

  test(
    'rejects a watchlist symbol missing from the exchange response',
    () async {
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/tickers')) {
          return _jsonResponse({
            'code': 0,
            'msg': 'Success',
            'data': [_ticker('BTCUSDT', 60000)],
          });
        }
        return _jsonResponse({
          'code': 0,
          'msg': 'Success',
          'data': _candles(60000, '1h'),
        });
      });
      final repository = BitunixOwnerAlphaRepository(
        client: client,
        requestSpacing: Duration.zero,
      );

      expect(
        () => repository.scan(
          symbols: const ['BTCUSDT', 'ETHUSDT'],
          selectedSymbol: 'BTCUSDT',
          selectedTimeframe: '1h',
          capital: 10000,
          riskPercent: 1,
          languageCode: 'fa',
        ),
        throwsA(isA<OwnerAlphaDataException>()),
      );
    },
  );

  test('repairs sub-basis-point Bitunix candle rounding drift', () async {
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/tickers')) {
        return _jsonResponse({
          'code': 0,
          'msg': 'Success',
          'data': [_ticker('BTCUSDT', 60000)],
        });
      }
      final candles = _candles(60000, request.url.queryParameters['interval']!);
      final open = double.parse(candles[1]['open']! as String);
      candles[1]['high'] = (open * 0.99995).toString();
      return _jsonResponse({
        'code': 0,
        'msg': 'Success',
        'data': candles,
      });
    });
    final repository = BitunixOwnerAlphaRepository(
      client: client,
      requestSpacing: Duration.zero,
      now: () => DateTime.utc(2026, 7, 21, 8),
    );

    final snapshot = await repository.scan(
      symbols: const ['BTCUSDT'],
      selectedSymbol: 'BTCUSDT',
      selectedTimeframe: '1h',
      capital: 10000,
      riskPercent: 1,
      languageCode: 'fa',
    );

    final repaired = snapshot.selectedAnalysis.candles[1];
    expect(repaired.high, repaired.open);
    expect(repaired.isValid, isTrue);
  });

  test('still rejects materially inconsistent candle ranges', () async {
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/tickers')) {
        return _jsonResponse({
          'code': 0,
          'msg': 'Success',
          'data': [_ticker('BTCUSDT', 60000)],
        });
      }
      final candles = _candles(60000, request.url.queryParameters['interval']!);
      final open = double.parse(candles[1]['open']! as String);
      candles[1]['high'] = (open * 0.99).toString();
      return _jsonResponse({
        'code': 0,
        'msg': 'Success',
        'data': candles,
      });
    });
    final repository = BitunixOwnerAlphaRepository(
      client: client,
      requestSpacing: Duration.zero,
      now: () => DateTime.utc(2026, 7, 21, 8),
    );

    expect(
      () => repository.scan(
        symbols: const ['BTCUSDT'],
        selectedSymbol: 'BTCUSDT',
        selectedTimeframe: '1h',
        capital: 10000,
        riskPercent: 1,
        languageCode: 'fa',
      ),
      throwsA(isA<OwnerAlphaDataException>()),
    );
  });
}

Map<String, Object> _ticker(String symbol, double price) {
  return {
    'symbol': symbol,
    'lastPrice': price.toString(),
    'last': price.toString(),
    'open': (price * 0.99).toString(),
    'high': (price * 1.02).toString(),
    'low': (price * 0.97).toString(),
    'quoteVol': '1000',
    'baseVol': '100',
  };
}

List<Map<String, Object>> _candles(double base, String timeframe) {
  final interval = switch (timeframe) {
    '15m' => const Duration(minutes: 15),
    '4h' => const Duration(hours: 4),
    '1d' => const Duration(days: 1),
    _ => const Duration(hours: 1),
  };
  final end = DateTime.utc(2026, 7, 21, 8);
  final start = end.subtract(interval * 60);
  return List.generate(60, (index) {
    final center = base * (1 + index * 0.0004);
    final wave = index.isEven ? 0.0008 : -0.0006;
    final open = center;
    final close = center * (1 + wave);
    return {
      'time': start.add(interval * index).millisecondsSinceEpoch,
      'open': open.toString(),
      'high': (center * 1.003).toString(),
      'low': (center * 0.997).toString(),
      'close': close.toString(),
      'quoteVol': (1000 + index).toString(),
      'baseVol': (100 + index).toString(),
    };
  });
}

http.Response _jsonResponse(Object body) {
  return http.Response(
    jsonEncode(body),
    200,
    headers: const {'content-type': 'application/json'},
  );
}
