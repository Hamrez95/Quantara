enum BitunixKlineInterval {
  fiveMinutes('5m', 'market_kline_5min', Duration(minutes: 5)),
  fifteenMinutes('15m', 'market_kline_15min', Duration(minutes: 15)),
  thirtyMinutes('30m', 'market_kline_30min', Duration(minutes: 30)),
  oneHour('1h', 'market_kline_60min', Duration(hours: 1)),
  fourHours('4h', 'market_kline_4h', Duration(hours: 4)),
  oneDay('1D', 'market_kline_1day', Duration(days: 1));

  const BitunixKlineInterval(this.timeframe, this.channel, this.duration);

  final String timeframe;
  final String channel;
  final Duration duration;

  static BitunixKlineInterval fromChannel(String channel) {
    return values.firstWhere(
      (value) => value.channel == channel,
      orElse: () =>
          throw FormatException('Unsupported Bitunix kline channel: $channel'),
    );
  }
}

enum BitunixDepthLevel {
  one('depth_book1'),
  five('depth_book5'),
  fifteen('depth_book15'),
  full('depth_books');

  const BitunixDepthLevel(this.channel);

  final String channel;

  static BitunixDepthLevel fromChannel(String channel) {
    return values.firstWhere(
      (value) => value.channel == channel,
      orElse: () =>
          throw FormatException('Unsupported Bitunix depth channel: $channel'),
    );
  }
}

final class BitunixPublicSubscription {
  BitunixPublicSubscription({required String symbol, required String channel})
    : symbol = _normalizeSymbol(symbol),
      channel = _normalizeChannel(channel);

  factory BitunixPublicSubscription.kline({
    required String symbol,
    required BitunixKlineInterval interval,
  }) => BitunixPublicSubscription(symbol: symbol, channel: interval.channel);

  factory BitunixPublicSubscription.ticker(String symbol) =>
      BitunixPublicSubscription(symbol: symbol, channel: 'ticker');

  factory BitunixPublicSubscription.tickers(String symbol) =>
      BitunixPublicSubscription(symbol: symbol, channel: 'tickers');

  factory BitunixPublicSubscription.trade(String symbol) =>
      BitunixPublicSubscription(symbol: symbol, channel: 'trade');

  factory BitunixPublicSubscription.depth({
    required String symbol,
    BitunixDepthLevel level = BitunixDepthLevel.one,
  }) => BitunixPublicSubscription(symbol: symbol, channel: level.channel);

  final String symbol;
  final String channel;

  String get key => '$symbol|$channel';

  Map<String, String> toJson() => {'symbol': symbol, 'ch': channel};

  static String _normalizeSymbol(String value) {
    final normalized = value.trim().toUpperCase();
    if (!RegExp(r'^[A-Z0-9]{5,24}$').hasMatch(normalized)) {
      throw ArgumentError.value(value, 'symbol', 'Invalid futures symbol.');
    }
    return normalized;
  }

  static String _normalizeChannel(String value) {
    final normalized = value.trim();
    final supported =
        normalized == 'ticker' ||
        normalized == 'tickers' ||
        normalized == 'trade' ||
        BitunixKlineInterval.values.any(
          (interval) => interval.channel == normalized,
        ) ||
        BitunixDepthLevel.values.any((level) => level.channel == normalized);
    if (!supported) {
      throw ArgumentError.value(
        value,
        'channel',
        'Unsupported public channel.',
      );
    }
    return normalized;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BitunixPublicSubscription &&
          symbol == other.symbol &&
          channel == other.channel;

  @override
  int get hashCode => Object.hash(symbol, channel);
}

final class BitunixSubscriptionShard {
  BitunixSubscriptionShard({
    required this.index,
    required List<BitunixPublicSubscription> subscriptions,
  }) : subscriptions = List.unmodifiable(subscriptions) {
    if (index < 0) throw ArgumentError.value(index, 'index');
    if (subscriptions.isEmpty || subscriptions.length > 300) {
      throw ArgumentError.value(
        subscriptions.length,
        'subscriptions',
        'A shard must contain between 1 and 300 subscriptions.',
      );
    }
  }

  final int index;
  final List<BitunixPublicSubscription> subscriptions;
}

sealed class BitunixPublicStreamEvent {
  const BitunixPublicStreamEvent({
    required this.channel,
    required this.exchangeTimestampUtc,
    required this.receivedAtUtc,
  });

  final String channel;
  final DateTime exchangeTimestampUtc;
  final DateTime receivedAtUtc;

  Duration get transportLag => receivedAtUtc.difference(exchangeTimestampUtc);
}

final class BitunixPingEvent extends BitunixPublicStreamEvent {
  const BitunixPingEvent({
    required this.pong,
    required this.serverPing,
    required super.exchangeTimestampUtc,
    required super.receivedAtUtc,
  }) : super(channel: 'ping');

  final int pong;
  final int? serverPing;
}

final class BitunixKlineEvent extends BitunixPublicStreamEvent {
  BitunixKlineEvent({
    required this.symbol,
    required this.interval,
    required this.openTimeUtc,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    required this.baseVolume,
    required this.quoteVolume,
    required super.exchangeTimestampUtc,
    required super.receivedAtUtc,
  }) : super(channel: interval.channel);

  final String symbol;
  final BitunixKlineInterval interval;
  final DateTime openTimeUtc;
  final double open;
  final double high;
  final double low;
  final double close;
  final double baseVolume;
  final double quoteVolume;
}

final class BitunixTickerEvent extends BitunixPublicStreamEvent {
  const BitunixTickerEvent({
    required this.symbol,
    required this.open,
    required this.high,
    required this.low,
    required this.last,
    required this.baseVolume,
    required this.quoteVolume,
    required this.changePercent,
    required this.bestBid,
    required this.bestAsk,
    required super.channel,
    required super.exchangeTimestampUtc,
    required super.receivedAtUtc,
  });

  final String symbol;
  final double open;
  final double high;
  final double low;
  final double last;
  final double baseVolume;
  final double quoteVolume;
  final double changePercent;
  final double? bestBid;
  final double? bestAsk;
}

final class BitunixTradePrint {
  const BitunixTradePrint({
    required this.price,
    required this.quantity,
    required this.isBuyerInitiated,
    required this.executedAtUtc,
  });

  final double price;
  final double quantity;
  final bool isBuyerInitiated;
  final DateTime executedAtUtc;
}

final class BitunixTradeEvent extends BitunixPublicStreamEvent {
  BitunixTradeEvent({
    required this.symbol,
    required List<BitunixTradePrint> trades,
    required super.exchangeTimestampUtc,
    required super.receivedAtUtc,
  }) : trades = List.unmodifiable(trades),
       super(channel: 'trade');

  final String symbol;
  final List<BitunixTradePrint> trades;
}

final class BitunixDepthLevelEntry {
  const BitunixDepthLevelEntry({required this.price, required this.quantity});

  final double price;
  final double quantity;
}

final class BitunixDepthEvent extends BitunixPublicStreamEvent {
  BitunixDepthEvent({
    required this.symbol,
    required this.level,
    required List<BitunixDepthLevelEntry> bids,
    required List<BitunixDepthLevelEntry> asks,
    required super.exchangeTimestampUtc,
    required super.receivedAtUtc,
  }) : bids = List.unmodifiable(bids),
       asks = List.unmodifiable(asks),
       super(channel: level.channel);

  final String symbol;
  final BitunixDepthLevel level;
  final List<BitunixDepthLevelEntry> bids;
  final List<BitunixDepthLevelEntry> asks;
}
