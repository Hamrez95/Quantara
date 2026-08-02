import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/owner_alpha/data/bitunix_public_stream_codec.dart';
import 'package:quantara_app/features/owner_alpha/domain/bitunix_public_stream_models.dart';

void main() {
  final receivedAt = DateTime.utc(2026, 8, 2, 12, 7, 1);
  final exchangeMilliseconds = DateTime.utc(
    2026,
    8,
    2,
    12,
    7,
  ).millisecondsSinceEpoch;

  group('BitunixPublicStreamCodec encoding', () {
    test('encodes sorted deduplicated subscription arguments', () {
      final encoded = BitunixPublicStreamCodec.encodeSubscribe([
        BitunixPublicSubscription.ticker('ETHUSDT'),
        BitunixPublicSubscription.kline(
          symbol: 'BTCUSDT',
          interval: BitunixKlineInterval.fiveMinutes,
        ),
        BitunixPublicSubscription.ticker('ETHUSDT'),
      ]);
      final decoded = jsonDecode(encoded) as Map<String, Object?>;
      final args = decoded['args'] as List<Object?>;

      expect(decoded['op'], 'subscribe');
      expect(args, hasLength(2));
      expect((args.first as Map<String, Object?>)['symbol'], 'BTCUSDT');
    });

    test('encodes Unix-second ping and rejects empty subscriptions', () {
      expect(
        BitunixPublicStreamCodec.encodePing(1732519687),
        '{"op":"ping","ping":1732519687}',
      );
      expect(
        () => BitunixPublicStreamCodec.encodeSubscribe(const []),
        throwsArgumentError,
      );
    });
  });

  group('BitunixPublicStreamCodec decoding', () {
    test('decodes a 5m kline and derives its UTC open time', () {
      final events = BitunixPublicStreamCodec.decode(
        jsonEncode({
          'ch': 'market_kline_5min',
          'symbol': 'BTCUSDT',
          'ts': exchangeMilliseconds,
          'data': {
            'o': '100',
            'h': '103',
            'l': '99',
            'c': '102',
            'b': '12.5',
            'q': '1262.5',
          },
        }),
        receivedAtUtc: receivedAt,
      );

      final event = events.single as BitunixKlineEvent;
      expect(event.interval, BitunixKlineInterval.fiveMinutes);
      expect(event.openTimeUtc, DateTime.utc(2026, 8, 2, 12, 5));
      expect(event.close, 102);
      expect(event.transportLag, const Duration(seconds: 1));
    });

    test('decodes individual and aggregated ticker messages', () {
      final ticker = BitunixPublicStreamCodec.decode(
        jsonEncode({
          'ch': 'ticker',
          'symbol': 'BTCUSDT',
          'ts': exchangeMilliseconds,
          'data': {
            's': 'BTCUSDT',
            'o': '100',
            'h': '110',
            'l': '95',
            'la': '105',
            'b': '10',
            'q': '1020',
            'r': '5',
          },
        }),
        receivedAtUtc: receivedAt,
      ).single as BitunixTickerEvent;
      expect(ticker.symbol, 'BTCUSDT');
      expect(ticker.bestBid, isNull);

      final tickers = BitunixPublicStreamCodec.decode(
        jsonEncode({
          'ch': 'tickers',
          'ts': exchangeMilliseconds,
          'data': [
            {
              's': 'BTCUSDT',
              'o': '100',
              'h': '110',
              'l': '95',
              'la': '105',
              'b': '10',
              'q': '1020',
              'r': '5',
              'bd': '104.9',
              'ak': '105.1',
            },
            {
              's': 'ETHUSDT',
              'o': '50',
              'h': '55',
              'l': '48',
              'la': '52',
              'b': '20',
              'q': '1010',
              'r': '4',
              'bd': '51.9',
              'ak': '52.1',
            },
          ],
        }),
        receivedAtUtc: receivedAt,
      );
      expect(tickers, hasLength(2));
      expect((tickers.last as BitunixTickerEvent).symbol, 'ETHUSDT');
    });

    test('decodes trade and depth batches', () {
      final trade = BitunixPublicStreamCodec.decode(
        jsonEncode({
          'ch': 'trade',
          'symbol': 'BTCUSDT',
          'ts': exchangeMilliseconds,
          'data': [
            {'t': '2026-08-02T12:07:00Z', 'p': '101', 'v': '0.5', 's': 'buy'},
            {'t': '2026-08-02T12:07:00Z', 'p': '100.9', 'v': '0.2', 's': 'sell'},
          ],
        }),
        receivedAtUtc: receivedAt,
      ).single as BitunixTradeEvent;
      expect(trade.trades, hasLength(2));
      expect(trade.trades.first.isBuyerInitiated, isTrue);

      final depth = BitunixPublicStreamCodec.decode(
        jsonEncode({
          'ch': 'depth_book1',
          'symbol': 'BTCUSDT',
          'ts': exchangeMilliseconds,
          'data': {
            'b': [
              ['100', '2'],
            ],
            'a': [
              ['101', '3'],
            ],
          },
        }),
        receivedAtUtc: receivedAt,
      ).single as BitunixDepthEvent;
      expect(depth.bids.single.price, 100);
      expect(depth.asks.single.quantity, 3);
    });

    test('accepts control acknowledgements and decodes ping response', () {
      expect(
        BitunixPublicStreamCodec.decode(
          '{"op":"subscribe","code":0}',
          receivedAtUtc: receivedAt,
        ),
        isEmpty,
      );
      final ping = BitunixPublicStreamCodec.decode(
        '{"op":"ping","pong":1732519687,"ping":1732519690}',
        receivedAtUtc: receivedAt,
      ).single as BitunixPingEvent;
      expect(ping.pong, 1732519687);
      expect(ping.serverPing, 1732519690);
    });

    test('rejects malformed, crossed or untrusted payloads', () {
      expect(
        () => BitunixPublicStreamCodec.decode(
          jsonEncode({
            'ch': 'market_kline_5min',
            'symbol': 'BTCUSDT',
            'ts': exchangeMilliseconds,
            'data': {
              'o': '100',
              'h': '99',
              'l': '98',
              'c': '101',
              'b': '1',
              'q': '1',
            },
          }),
          receivedAtUtc: receivedAt,
        ),
        throwsFormatException,
      );
      expect(
        () => BitunixPublicStreamCodec.decode(
          jsonEncode({
            'ch': 'depth_book1',
            'symbol': 'BTCUSDT',
            'ts': exchangeMilliseconds,
            'data': {
              'b': [
                ['102', '1'],
              ],
              'a': [
                ['101', '1'],
              ],
            },
          }),
          receivedAtUtc: receivedAt,
        ),
        throwsFormatException,
      );
      expect(
        () => BitunixPublicStreamCodec.decode(
          jsonEncode({
            'ch': 'unknown',
            'ts': exchangeMilliseconds,
            'data': const {},
          }),
          receivedAtUtc: receivedAt,
        ),
        throwsFormatException,
      );
      final oversized = List.filled(
        BitunixPublicStreamCodec.maximumPayloadCharacters + 1,
        'x',
      ).join();
      expect(
        () => BitunixPublicStreamCodec.decode(
          oversized,
          receivedAtUtc: receivedAt,
        ),
        throwsFormatException,
      );
    });
  });
}
