import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import '../../market_analysis/domain/market_chart_models.dart';
import '../domain/realtime_candle_pipeline_models.dart';

abstract interface class RealtimeCandleBackfillSource {
  Future<List<ChartCandle>> loadRecentClosed({
    required RealtimeCandleStreamKey key,
    required int limit,
    required DateTime nowUtc,
  });

  Future<List<ChartCandle>> loadClosedRange({
    required RealtimeCandleStreamKey key,
    required DateTime fromInclusiveUtc,
    required DateTime toExclusiveUtc,
  });
}

typedef CandleBackfillDelay = Future<void> Function(Duration duration);

final class BitunixCandleBackfillSource
    implements RealtimeCandleBackfillSource {
  BitunixCandleBackfillSource({
    required this.client,
    this.timeout = const Duration(seconds: 10),
    this.requestSpacing = const Duration(milliseconds: 120),
    this.maximumMalformedRecentRows = 8,
    String apiOrigin = 'https://fapi.bitunix.com',
    CandleBackfillDelay? delay,
  }) : apiOrigin = _validateOrigin(apiOrigin),
       delay = delay ?? _delay {
    if (timeout <= Duration.zero || timeout > const Duration(seconds: 30)) {
      throw ArgumentError.value(timeout, 'timeout');
    }
    if (requestSpacing < const Duration(milliseconds: 100)) {
      throw ArgumentError.value(
        requestSpacing,
        'requestSpacing',
        'Bitunix public market REST is limited to ten requests per second.',
      );
    }
    if (maximumMalformedRecentRows < 0 || maximumMalformedRecentRows > 20) {
      throw ArgumentError.value(
        maximumMalformedRecentRows,
        'maximumMalformedRecentRows',
        'Expected a bounded value from 0 to 20.',
      );
    }
  }

  static const int maximumPageSize = 200;
  static const int maximumResponseBytes = 2 * 1024 * 1024;

  final http.Client client;
  final Duration timeout;
  final Duration requestSpacing;
  final int maximumMalformedRecentRows;
  final Uri apiOrigin;
  final CandleBackfillDelay delay;

  @override
  Future<List<ChartCandle>> loadRecentClosed({
    required RealtimeCandleStreamKey key,
    required int limit,
    required DateTime nowUtc,
  }) async {
    _requireUtc(nowUtc, 'nowUtc');
    if (limit < 20 || limit > maximumPageSize) {
      throw ArgumentError.value(
        limit,
        'limit',
        'Expected a value from 20 to 200.',
      );
    }

    final candles = await _request(
      key: key,
      query: {
        'symbol': key.symbol,
        'interval': _restInterval(key),
        'limit': '$maximumPageSize',
        'type': 'LAST_PRICE',
      },
      allowedMalformedRows: maximumMalformedRecentRows,
    );
    final closed = candles
        .where(
          (candle) =>
              !candle.openTime.add(key.interval.duration).isAfter(nowUtc),
        )
        .toList(growable: false);
    if (closed.length < limit) {
      throw StateError(
        'Bitunix did not return enough closed candles for ${key.id}.',
      );
    }
    return List.unmodifiable(closed.sublist(closed.length - limit));
  }

  @override
  Future<List<ChartCandle>> loadClosedRange({
    required RealtimeCandleStreamKey key,
    required DateTime fromInclusiveUtc,
    required DateTime toExclusiveUtc,
  }) async {
    _requireUtc(fromInclusiveUtc, 'fromInclusiveUtc');
    _requireUtc(toExclusiveUtc, 'toExclusiveUtc');
    if (!toExclusiveUtc.isAfter(fromInclusiveUtc)) {
      throw ArgumentError('Backfill end must be after its start.');
    }
    final intervalMilliseconds = key.interval.duration.inMilliseconds;
    final rangeMilliseconds = toExclusiveUtc
        .difference(fromInclusiveUtc)
        .inMilliseconds;
    if (rangeMilliseconds % intervalMilliseconds != 0) {
      throw ArgumentError('Backfill boundaries must align to the timeframe.');
    }

    final expectedCount = rangeMilliseconds ~/ intervalMilliseconds;
    final byTime = <DateTime, ChartCandle>{};
    var cursor = fromInclusiveUtc;
    while (cursor.isBefore(toExclusiveUtc)) {
      final remaining =
          toExclusiveUtc.difference(cursor).inMilliseconds ~/
          intervalMilliseconds;
      final pageLimit = math.min(remaining, maximumPageSize);
      final page = await _request(
        key: key,
        query: {
          'symbol': key.symbol,
          'interval': _restInterval(key),
          'startTime': '${cursor.millisecondsSinceEpoch - 1}',
          'endTime': '${toExclusiveUtc.millisecondsSinceEpoch}',
          'limit': '$pageLimit',
          'type': 'LAST_PRICE',
        },
      );
      final inRange =
          page
              .where(
                (candle) =>
                    !candle.openTime.isBefore(cursor) &&
                    candle.openTime.isBefore(toExclusiveUtc),
              )
              .toList(growable: false)
            ..sort((left, right) => left.openTime.compareTo(right.openTime));
      if (inRange.isEmpty || inRange.first.openTime != cursor) {
        throw StateError(
          'Bitunix backfill left a gap at $cursor for ${key.id}.',
        );
      }
      for (final candle in inRange) {
        byTime[candle.openTime] = candle;
      }
      final next = inRange.last.openTime.add(key.interval.duration);
      if (!next.isAfter(cursor)) {
        throw StateError('Bitunix backfill did not advance its cursor.');
      }
      cursor = next;
      if (cursor.isBefore(toExclusiveUtc)) await delay(requestSpacing);
    }

    final result = byTime.values.toList(growable: false)
      ..sort((left, right) => left.openTime.compareTo(right.openTime));
    if (result.length != expectedCount) {
      throw StateError(
        'Bitunix backfill returned ${result.length} of $expectedCount candles.',
      );
    }
    for (var index = 0; index < result.length; index++) {
      final expectedOpen = fromInclusiveUtc.add(key.interval.duration * index);
      if (result[index].openTime != expectedOpen) {
        throw StateError('Bitunix backfill is not strictly contiguous.');
      }
    }
    return List.unmodifiable(result);
  }

  Future<List<ChartCandle>> _request({
    required RealtimeCandleStreamKey key,
    required Map<String, String> query,
    int allowedMalformedRows = 0,
  }) async {
    final uri = apiOrigin
        .resolve('/api/v1/futures/market/kline')
        .replace(queryParameters: query);
    final response = await client
        .get(uri, headers: const {'Accept': 'application/json'})
        .timeout(timeout);
    if (response.statusCode != 200) {
      throw http.ClientException(
        'Bitunix kline request failed with HTTP ${response.statusCode}.',
        uri,
      );
    }
    if (response.bodyBytes.length > maximumResponseBytes) {
      throw const FormatException('Bitunix kline response is too large.');
    }
    final root = _object(jsonDecode(utf8.decode(response.bodyBytes)));
    if (_integer(root['code'], 'code') != 0) {
      throw const FormatException(
        'Bitunix kline response code was not successful.',
      );
    }
    final rawData = root['data'];
    if (rawData is! List<Object?> || rawData.length > maximumPageSize) {
      throw const FormatException('Bitunix kline data must be a bounded list.');
    }

    final byTime = <DateTime, ChartCandle>{};
    var malformedRows = 0;
    for (final raw in rawData) {
      try {
        final item = _object(raw);
        final openTime = DateTime.fromMillisecondsSinceEpoch(
          _integer(item['time'], 'time'),
          isUtc: true,
        );
        if (openTime.isBefore(DateTime.utc(2020))) {
          throw const FormatException(
            'Bitunix returned an invalid candle time.',
          );
        }
        final open = _positive(item['open'], 'open');
        final high = _positive(item['high'], 'high');
        final low = _positive(item['low'], 'low');
        final close = _positive(item['close'], 'close');
        final candle = ChartCandle(
          openTime: openTime,
          open: open,
          high: high,
          low: low,
          close: close,
          volume: _nonNegative(
            item['baseVol'] ?? item['volume'] ?? item['quoteVol'],
            'baseVol',
          ),
        );
        if (!candle.isValid) {
          throw FormatException('Bitunix returned invalid OHLC for ${key.id}.');
        }
        byTime[openTime] = candle;
      } on FormatException {
        if (malformedRows >= allowedMalformedRows) rethrow;
        malformedRows++;
      }
    }
    final result = byTime.values.toList(growable: false)
      ..sort((left, right) => left.openTime.compareTo(right.openTime));
    return result;
  }

  static Uri _validateOrigin(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.query.isNotEmpty ||
        uri.fragment.isNotEmpty) {
      throw ArgumentError.value(
        value,
        'apiOrigin',
        'A secure origin is required.',
      );
    }
    return uri;
  }

  static String _restInterval(RealtimeCandleStreamKey key) =>
      key.interval.timeframe == '1D' ? '1d' : key.interval.timeframe;

  static Map<String, Object?> _object(Object? value) {
    if (value is! Map<Object?, Object?>) {
      throw const FormatException('Expected a JSON object.');
    }
    final result = <String, Object?>{};
    for (final entry in value.entries) {
      final key = entry.key;
      if (key is! String) {
        throw const FormatException('JSON keys must be strings.');
      }
      result[key] = entry.value;
    }
    return result;
  }

  static int _integer(Object? value, String name) {
    final parsed = switch (value) {
      int number => number,
      num number when number.isFinite && number == number.roundToDouble() =>
        number.toInt(),
      String text => int.tryParse(text),
      _ => null,
    };
    if (parsed == null) throw FormatException('$name must be an integer.');
    return parsed;
  }

  static double _finite(Object? value, String name) {
    final parsed = switch (value) {
      num number => number.toDouble(),
      String text => double.tryParse(text),
      _ => null,
    };
    if (parsed == null || !parsed.isFinite) {
      throw FormatException('$name must be finite.');
    }
    return parsed;
  }

  static double _positive(Object? value, String name) {
    final parsed = _finite(value, name);
    if (parsed <= 0) throw FormatException('$name must be positive.');
    return parsed;
  }

  static double _nonNegative(Object? value, String name) {
    final parsed = _finite(value, name);
    if (parsed < 0) throw FormatException('$name must be non-negative.');
    return parsed;
  }

  static void _requireUtc(DateTime value, String name) {
    if (!value.isUtc) {
      throw ArgumentError.value(value, name, 'UTC is required.');
    }
  }

  static Future<void> _delay(Duration duration) => Future.delayed(duration);
}
