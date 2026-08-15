import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/auto_trade/data/local_live_preferences_store.dart';
import 'package:quantara_app/features/owner_alpha/data/local_live_realtime_universe.dart';
import 'package:quantara_app/features/owner_alpha/domain/bitunix_public_stream_models.dart';

void main() {
  group('LocalLiveRealtimeUniverse', () {
    test('maps nine symbols by three timeframes to exactly 27 streams', () {
      const symbols = <String>[
        'BTCUSDT',
        'ETHUSDT',
        'SOLUSDT',
        'XRPUSDT',
        'DOGEUSDT',
        'ADAUSDT',
        'AVAXUSDT',
        'LINKUSDT',
        'SUIUSDT',
      ];
      const preferences = LocalLivePreferences(
        symbols: symbols,
        timeframes: {'5m', '15m', '1h'},
        leverage: 5,
        riskPercent: 0.25,
        dailyLossLimitPercent: 1,
      );

      final universe = LocalLiveRealtimeUniverse.build(preferences);

      expect(universe.streams, hasLength(27));
      expect(
        universe.streams.map((stream) => stream.symbol).toSet(),
        symbols.toSet(),
      );
      expect(
        universe.streams.map((stream) => stream.interval).toSet(),
        {
          BitunixKlineInterval.fiveMinutes,
          BitunixKlineInterval.fifteenMinutes,
          BitunixKlineInterval.oneHour,
        },
      );
      expect(
        universe.streams
            .where((stream) => stream.interval == BitunixKlineInterval.thirtyMinutes),
        isEmpty,
      );
    });

    test('fingerprint ignores ordering but changes with the monitored universe', () {
      const first = LocalLivePreferences(
        symbols: ['BTCUSDT', 'ETHUSDT'],
        timeframes: {'15m', '1h'},
        leverage: 5,
        riskPercent: 0.25,
        dailyLossLimitPercent: 1,
      );
      const reordered = LocalLivePreferences(
        symbols: ['ETHUSDT', 'BTCUSDT'],
        timeframes: {'1h', '15m'},
        leverage: 25,
        riskPercent: 0.5,
        dailyLossLimitPercent: 2,
      );
      const changed = LocalLivePreferences(
        symbols: ['ETHUSDT', 'BTCUSDT', 'SOLUSDT'],
        timeframes: {'1h', '15m'},
        leverage: 25,
        riskPercent: 0.5,
        dailyLossLimitPercent: 2,
      );

      expect(
        LocalLiveRealtimeUniverse.fingerprint(first),
        LocalLiveRealtimeUniverse.fingerprint(reordered),
      );
      expect(
        LocalLiveRealtimeUniverse.fingerprint(first),
        isNot(LocalLiveRealtimeUniverse.fingerprint(changed)),
      );
    });

    test('rejects a universe with no supported timeframe', () {
      const preferences = LocalLivePreferences(
        symbols: ['BTCUSDT'],
        timeframes: {'30m'},
        leverage: 5,
        riskPercent: 0.25,
        dailyLossLimitPercent: 1,
      );

      expect(
        () => LocalLiveRealtimeUniverse.build(preferences),
        throwsStateError,
      );
    });
  });
}
