import 'dart:convert';
import 'dart:math' as math;

import '../domain/bitunix_public_stream_models.dart';

abstract final class BitunixPublicStreamCodec {
  static const int maximumPayloadCharacters = 1024 * 1024;
  static const int maximumBatchItems = 1000;

  static String encodeSubscribe(
    Iterable<BitunixPublicSubscription> subscriptions,
  ) => _encodeSubscriptionOperation('subscribe', subscriptions);

  static String encodeUnsubscribe(
    Iterable<BitunixPublicSubscription> subscriptions,
  ) => _encodeSubscriptionOperation('unsubscribe', subscriptions);

  static String encodePing(int unixSeconds) {
    if (unixSeconds <= 0) {
      throw ArgumentError.value(unixSeconds, 'unixSeconds');
    }
    return jsonEncode({'op': 'ping', 'ping': unixSeconds});
  }

  static List<BitunixPublicStreamEvent> decode(
    String payload, {
    required DateTime receivedAtUtc,
  }) {
    if (!receivedAtUtc.isUtc) {
      throw ArgumentError.value(
        receivedAtUtc,
        'receivedAtUtc',
        'UTC is required.',
      );
    }
    if (payload.isEmpty || payload.length > maximumPayloadCharacters) {
      throw const FormatException('Invalid Bitunix WebSocket payload size.');
    }

    final root = _object(jsonDecode(payload));
    final operation = root['op'];
    if (operation == 'ping' && root.containsKey('pong')) {
      final pong = _integer(root['pong'], 'pong');
      final serverPing = root['ping'] == null
          ? null
          : _integer(root['ping'], 'ping');
      final exchangeTimestamp = serverPing == null
          ? receivedAtUtc
          : DateTime.fromMillisecondsSinceEpoch(serverPing * 1000, isUtc: true);
      return [
        BitunixPingEvent(
          pong: pong,
          serverPing: serverPing,
          exchangeTimestampUtc: exchangeTimestamp,
          receivedAtUtc: receivedAtUtc,
        ),
      ];
    }
    if (operation == 'subscribe' || operation == 'unsubscribe') {
      return const [];
    }

    final channel = _requiredString(root['ch'], 'ch');
    final exchangeTimestamp = _exchangeTimestamp(
      root['ts'],
      receivedAtUtc: receivedAtUtc,
    );

    if (channel.startsWith('market_kline_')) {
      return [
        _decodeKline(
          root,
          channel: channel,
          exchangeTimestampUtc: exchangeTimestamp,
          receivedAtUtc: receivedAtUtc,
        ),
      ];
    }
    if (channel == 'ticker') {
      return [
        _decodeTicker(
          root,
          data: _object(root['data']),
          channel: channel,
          exchangeTimestampUtc: exchangeTimestamp,
          receivedAtUtc: receivedAtUtc,
        ),
      ];
    }
    if (channel == 'tickers') {
      final data = _list(root['data'], 'data');
      if (data.length > maximumBatchItems) {
        throw const FormatException('Bitunix ticker batch is too large.');
      }
      return List.unmodifiable([
        for (final item in data)
          _decodeTicker(
            root,
            data: _object(item),
            channel: channel,
            exchangeTimestampUtc: exchangeTimestamp,
            receivedAtUtc: receivedAtUtc,
          ),
      ]);
    }
    if (channel == 'trade') {
      return [
        _decodeTrades(
          root,
          exchangeTimestampUtc: exchangeTimestamp,
          receivedAtUtc: receivedAtUtc,
        ),
      ];
    }
    if (channel.startsWith('depth_')) {
      return [
        _decodeDepth(
          root,
          channel: channel,
          exchangeTimestampUtc: exchangeTimestamp,
          receivedAtUtc: receivedAtUtc,
        ),
      ];
    }

    throw FormatException('Unsupported Bitunix public channel: $channel');
  }

  static String _encodeSubscriptionOperation(
    String operation,
    Iterable<BitunixPublicSubscription> subscriptions,
  ) {
    final unique = <String, BitunixPublicSubscription>{};
    for (final subscription in subscriptions) {
      unique[subscription.key] = subscription;
    }
    final ordered = unique.values.toList(growable: false)
      ..sort((left, right) => left.key.compareTo(right.key));
    if (ordered.isEmpty || ordered.length > 300) {
      throw ArgumentError.value(
        ordered.length,
        'subscriptions',
        'A WebSocket operation must contain between 1 and 300 channels.',
      );
    }
    return jsonEncode({
      'op': operation,
      'args': [for (final subscription in ordered) subscription.toJson()],
    });
  }

  static BitunixKlineEvent _decodeKline(
    Map<String, Object?> root, {
    required String channel,
    required DateTime exchangeTimestampUtc,
    required DateTime receivedAtUtc,
  }) {
    final symbol = _symbol(root['symbol']);
    final interval = BitunixKlineInterval.fromChannel(channel);
    final data = _object(root['data']);
    final open = _positive(data['o'], 'data.o');
    final high = _positive(data['h'], 'data.h');
    final low = _positive(data['l'], 'data.l');
    final close = _positive(data['c'], 'data.c');
    if (high < math.max(open, close) || low > math.min(open, close)) {
      throw const FormatException('Invalid Bitunix kline OHLC range.');
    }
    final intervalMilliseconds = interval.duration.inMilliseconds;
    final timestampMilliseconds = exchangeTimestampUtc.millisecondsSinceEpoch;
    final openTimestamp =
        timestampMilliseconds - (timestampMilliseconds % intervalMilliseconds);

    return BitunixKlineEvent(
      symbol: symbol,
      interval: interval,
      openTimeUtc: DateTime.fromMillisecondsSinceEpoch(
        openTimestamp,
        isUtc: true,
      ),
      open: open,
      high: high,
      low: low,
      close: close,
      baseVolume: _nonNegative(data['b'], 'data.b'),
      quoteVolume: _nonNegative(data['q'], 'data.q'),
      exchangeTimestampUtc: exchangeTimestampUtc,
      receivedAtUtc: receivedAtUtc,
    );
  }

  static BitunixTickerEvent _decodeTicker(
    Map<String, Object?> root, {
    required Map<String, Object?> data,
    required String channel,
    required DateTime exchangeTimestampUtc,
    required DateTime receivedAtUtc,
  }) {
    final symbol = _symbol(data['s'] ?? root['symbol']);
    final open = _positive(data['o'], 'data.o');
    final high = _positive(data['h'], 'data.h');
    final low = _positive(data['l'], 'data.l');
    final last = _positive(data['la'], 'data.la');
    if (high < low || last > high || last < low) {
      throw const FormatException('Invalid Bitunix ticker price range.');
    }
    final bestBid = data['bd'] == null
        ? null
        : _positive(data['bd'], 'data.bd');
    final bestAsk = data['ak'] == null
        ? null
        : _positive(data['ak'], 'data.ak');
    if (bestBid != null && bestAsk != null && bestBid > bestAsk) {
      throw const FormatException('Bitunix ticker bid exceeds ask.');
    }

    return BitunixTickerEvent(
      symbol: symbol,
      open: open,
      high: high,
      low: low,
      last: last,
      baseVolume: _nonNegative(data['b'], 'data.b'),
      quoteVolume: _nonNegative(data['q'], 'data.q'),
      changePercent: _finite(data['r'], 'data.r'),
      bestBid: bestBid,
      bestAsk: bestAsk,
      channel: channel,
      exchangeTimestampUtc: exchangeTimestampUtc,
      receivedAtUtc: receivedAtUtc,
    );
  }

  static BitunixTradeEvent _decodeTrades(
    Map<String, Object?> root, {
    required DateTime exchangeTimestampUtc,
    required DateTime receivedAtUtc,
  }) {
    final symbol = _symbol(root['symbol']);
    final data = _list(root['data'], 'data');
    if (data.isEmpty || data.length > maximumBatchItems) {
      throw const FormatException('Invalid Bitunix trade batch size.');
    }
    final trades = <BitunixTradePrint>[];
    for (final item in data) {
      final trade = _object(item);
      final side = _requiredString(trade['s'], 'data.s').toLowerCase();
      if (side != 'buy' && side != 'sell') {
        throw FormatException('Invalid Bitunix trade side: $side');
      }
      final executedAt = DateTime.tryParse(
        _requiredString(trade['t'], 'data.t'),
      )?.toUtc();
      if (executedAt == null ||
          executedAt.isBefore(DateTime.utc(2020)) ||
          executedAt.isAfter(receivedAtUtc.add(const Duration(days: 1)))) {
        throw const FormatException('Invalid Bitunix trade timestamp.');
      }
      trades.add(
        BitunixTradePrint(
          price: _positive(trade['p'], 'data.p'),
          quantity: _positive(trade['v'], 'data.v'),
          isBuyerInitiated: side == 'buy',
          executedAtUtc: executedAt,
        ),
      );
    }
    return BitunixTradeEvent(
      symbol: symbol,
      trades: trades,
      exchangeTimestampUtc: exchangeTimestampUtc,
      receivedAtUtc: receivedAtUtc,
    );
  }

  static BitunixDepthEvent _decodeDepth(
    Map<String, Object?> root, {
    required String channel,
    required DateTime exchangeTimestampUtc,
    required DateTime receivedAtUtc,
  }) {
    final symbol = _symbol(root['symbol']);
    final level = BitunixDepthLevel.fromChannel(channel);
    final data = _object(root['data']);
    final bids = _depthEntries(data['b'], 'data.b');
    final asks = _depthEntries(data['a'], 'data.a');
    if (bids.isEmpty && asks.isEmpty) {
      throw const FormatException('Bitunix depth update is empty.');
    }
    if (bids.isNotEmpty &&
        asks.isNotEmpty &&
        bids.first.price > asks.first.price) {
      throw const FormatException('Bitunix depth book is crossed.');
    }
    return BitunixDepthEvent(
      symbol: symbol,
      level: level,
      bids: bids,
      asks: asks,
      exchangeTimestampUtc: exchangeTimestampUtc,
      receivedAtUtc: receivedAtUtc,
    );
  }

  static List<BitunixDepthLevelEntry> _depthEntries(
    Object? value,
    String name,
  ) {
    final levels = _list(value, name);
    if (levels.length > maximumBatchItems) {
      throw FormatException('$name contains too many levels.');
    }
    return List.unmodifiable([
      for (final item in levels)
        () {
          final pair = _list(item, name);
          if (pair.length != 2) {
            throw FormatException('$name level must contain price and size.');
          }
          return BitunixDepthLevelEntry(
            price: _positive(pair[0], '$name.price'),
            quantity: _nonNegative(pair[1], '$name.quantity'),
          );
        }(),
    ]);
  }

  static DateTime _exchangeTimestamp(
    Object? value, {
    required DateTime receivedAtUtc,
  }) {
    final milliseconds = _integer(value, 'ts');
    final timestamp = DateTime.fromMillisecondsSinceEpoch(
      milliseconds,
      isUtc: true,
    );
    if (timestamp.isBefore(DateTime.utc(2020)) ||
        timestamp.isAfter(receivedAtUtc.add(const Duration(days: 1)))) {
      throw const FormatException('Invalid Bitunix exchange timestamp.');
    }
    return timestamp;
  }

  static String _symbol(Object? value) {
    final symbol = _requiredString(value, 'symbol').toUpperCase();
    if (!RegExp(r'^[A-Z0-9]{5,24}$').hasMatch(symbol)) {
      throw FormatException('Invalid Bitunix symbol: $symbol');
    }
    return symbol;
  }

  static Map<String, Object?> _object(Object? value) {
    if (value is! Map<Object?, Object?>) {
      throw const FormatException('Expected a JSON object.');
    }
    final result = <String, Object?>{};
    for (final entry in value.entries) {
      final key = entry.key;
      if (key is! String) {
        throw const FormatException('JSON object keys must be strings.');
      }
      result[key] = entry.value;
    }
    return result;
  }

  static List<Object?> _list(Object? value, String name) {
    if (value is! List<Object?>) {
      throw FormatException('$name must be a JSON array.');
    }
    return value;
  }

  static String _requiredString(Object? value, String name) {
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('$name must be a non-empty string.');
    }
    return value.trim();
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
}
