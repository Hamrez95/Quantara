import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quantara_app/features/owner_alpha/data/bitunix_candle_backfill_source.dart';
import 'package:quantara_app/features/owner_alpha/domain/bitunix_public_stream_models.dart';
import 'package:quantara_app/features/owner_alpha/domain/realtime_candle_pipeline_models.dart';

void main() {
  final key = RealtimeCandleStreamKey(
    symbol: 'BTCUSDT',
    interval: BitunixKlineInterval.fiveMinutes,
  );

  group('BitunixCandleBackfillSource', () {
    test('loads recent closed candles and excludes the open candle', () async {
      final start = DateTime.utc(2026, 8, 2, 10);
      final now = start.add(const Duration(minutes: 100));
      final client = MockClient((request) async {
        expect(request.url.path, '/api/v1/futures/market/kline');
        expect(request.url.queryParameters['interval'], '5m');
        return http.Response(
          jsonEncode({
            'code': 0,
            'data': [
              for (var index = 0; index < 22; index++)
                _jsonCandle(start.add(Duration(minutes: index * 5)), index),
            ],
          }),
          200,
        );
      });
      final source = BitunixCandleBackfillSource(client: client);

      final candles = await source.loadRecentClosed(
        key: key,
        limit: 20,
        nowUtc: now,
      );

      expect(candles, hasLength(20));
      expect(candles.first.openTime, start);
      expect(candles.last.openTime, start.add(const Duration(minutes: 95)));
    });

    test('skips a bounded malformed row in recent history', () async {
      final start = DateTime.utc(2026, 8, 2, 10);
      final now = start.add(const Duration(minutes: 150));
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'code': 0,
            'data': [
              for (var index = 0; index < 30; index++)
                index == 3
                    ? {
                        ..._jsonCandle(
                          start.add(Duration(minutes: index * 5)),
                          index,
                        ),
                        'high': '99',
                        'close': '101',
                      }
                    : _jsonCandle(
                        start.add(Duration(minutes: index * 5)),
                        index,
                      ),
            ],
          }),
          200,
        );
      });
      final source = BitunixCandleBackfillSource(client: client);

      final candles = await source.loadRecentClosed(
        key: key,
        limit: 20,
        nowUtc: now,
      );

      expect(candles, hasLength(20));
      expect(candles.every((candle) => candle.isValid), isTrue);
      expect(candles.any((candle) => candle.openTime == start), isFalse);
    });

    test(
      'fails recent history after the malformed-row budget is exceeded',
      () async {
        final start = DateTime.utc(2026, 8, 2, 10);
        final client = MockClient((request) async {
          return http.Response(
            jsonEncode({
              'code': 0,
              'data': [
                for (var index = 0; index < 24; index++)
                  index < 2
                      ? {
                          ..._jsonCandle(
                            start.add(Duration(minutes: index * 5)),
                            index,
                          ),
                          'high': '99',
                          'close': '101',
                        }
                      : _jsonCandle(
                          start.add(Duration(minutes: index * 5)),
                          index,
                        ),
              ],
            }),
            200,
          );
        });
        final source = BitunixCandleBackfillSource(
          client: client,
          maximumMalformedRecentRows: 1,
        );

        await expectLater(
          source.loadRecentClosed(
            key: key,
            limit: 20,
            nowUtc: start.add(const Duration(minutes: 120)),
          ),
          throwsFormatException,
        );
      },
    );

    test('paginates an exact range beyond the 200-candle API limit', () async {
      final start = DateTime.utc(2026, 8, 1);
      final end = start.add(const Duration(minutes: 5 * 201));
      var requests = 0;
      final client = MockClient((request) async {
        requests++;
        final cursorMilliseconds =
            int.parse(request.url.queryParameters['startTime']!) + 1;
        final cursor = DateTime.fromMillisecondsSinceEpoch(
          cursorMilliseconds,
          isUtc: true,
        );
        final limit = int.parse(request.url.queryParameters['limit']!);
        final remaining = end.difference(cursor).inMinutes ~/ 5;
        final count = remaining < limit ? remaining : limit;
        return http.Response(
          jsonEncode({
            'code': 0,
            'data': [
              for (var index = 0; index < count; index++)
                _jsonCandle(cursor.add(Duration(minutes: index * 5)), index),
            ],
          }),
          200,
        );
      });
      final delays = <Duration>[];
      final source = BitunixCandleBackfillSource(
        client: client,
        delay: (duration) async => delays.add(duration),
      );

      final candles = await source.loadClosedRange(
        key: key,
        fromInclusiveUtc: start,
        toExclusiveUtc: end,
      );

      expect(candles, hasLength(201));
      expect(candles.first.openTime, start);
      expect(candles.last.openTime, end.subtract(const Duration(minutes: 5)));
      expect(requests, 2);
      expect(delays, [const Duration(milliseconds: 120)]);
    });

    test(
      'fails closed when a REST page does not start at the cursor',
      () async {
        final start = DateTime.utc(2026, 8, 2, 10);
        final client = MockClient((request) async {
          return http.Response(
            jsonEncode({
              'code': 0,
              'data': [_jsonCandle(start.add(const Duration(minutes: 5)), 0)],
            }),
            200,
          );
        });
        final source = BitunixCandleBackfillSource(client: client);

        await expectLater(
          source.loadClosedRange(
            key: key,
            fromInclusiveUtc: start,
            toExclusiveUtc: start.add(const Duration(minutes: 10)),
          ),
          throwsStateError,
        );
      },
    );

    test('rejects malformed OHLC and unsuccessful response codes', () async {
      final start = DateTime.utc(2026, 8, 2, 10);
      final invalidOhlc = BitunixCandleBackfillSource(
        client: MockClient((request) async {
          return http.Response(
            jsonEncode({
              'code': 0,
              'data': [
                {..._jsonCandle(start, 0), 'high': '99', 'close': '101'},
              ],
            }),
            200,
          );
        }),
      );
      await expectLater(
        invalidOhlc.loadClosedRange(
          key: key,
          fromInclusiveUtc: start,
          toExclusiveUtc: start.add(const Duration(minutes: 5)),
        ),
        throwsFormatException,
      );

      final rejected = BitunixCandleBackfillSource(
        client: MockClient((request) async {
          return http.Response('{"code":1001,"data":[]}', 200);
        }),
      );
      await expectLater(
        rejected.loadClosedRange(
          key: key,
          fromInclusiveUtc: start,
          toExclusiveUtc: start.add(const Duration(minutes: 5)),
        ),
        throwsFormatException,
      );
    });

    test(
      'rejects insecure origins and request pacing above ten per second',
      () {
        expect(
          () => BitunixCandleBackfillSource(
            client: MockClient((request) async => http.Response('{}', 200)),
            apiOrigin: 'http://example.test',
          ),
          throwsArgumentError,
        );
        expect(
          () => BitunixCandleBackfillSource(
            client: MockClient((request) async => http.Response('{}', 200)),
            requestSpacing: const Duration(milliseconds: 99),
          ),
          throwsArgumentError,
        );
        expect(
          () => BitunixCandleBackfillSource(
            client: MockClient((request) async => http.Response('{}', 200)),
            maximumMalformedRecentRows: 21,
          ),
          throwsArgumentError,
        );
      },
    );
  });
}

Map<String, Object> _jsonCandle(DateTime openTime, int index) => {
  'time': openTime.millisecondsSinceEpoch,
  'open': '${100 + index}',
  'high': '${102 + index}',
  'low': '${99 + index}',
  'close': '${101 + index}',
  'baseVol': '${10 + index}',
  'quoteVol': '${1000 + index}',
};
