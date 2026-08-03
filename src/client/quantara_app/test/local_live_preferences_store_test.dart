import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/auto_trade/data/local_live_preferences_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'persists every Local Live user control across reconstruction',
    () async {
      const store = SharedPreferencesLocalLivePreferencesStore();
      const value = LocalLivePreferences(
        symbols: ['BTCUSDT', 'ETHUSDT', 'XRPUSDT'],
        timeframes: {'5m', '15m'},
        leverage: 37,
        riskPercent: 1.25,
        dailyLossLimitPercent: 6,
      );

      await store.save(value);
      final restored = await store.load(
        availableSymbols: const ['BTCUSDT', 'ETHUSDT', 'XRPUSDT', 'SOLUSDT'],
      );

      expect(restored.symbols, value.symbols);
      expect(restored.timeframes, value.timeframes);
      expect(restored.leverage, 37);
      expect(restored.riskPercent, 1.25);
      expect(restored.dailyLossLimitPercent, 6);
    },
  );

  test('normalizes stale symbols and out-of-range legacy values', () async {
    SharedPreferences.setMockInitialValues({
      'quantara.local-live.ui.symbols.v2': ['OLDUSDT', 'BTCUSDT'],
      'quantara.local-live.ui.timeframes.v2': ['2m', '5m'],
      'quantara.local-live.ui.leverage.v2': 500,
      'quantara.local-live.ui.risk.v2': 20.0,
      'quantara.local-live.ui.daily-loss.v2': 50.0,
    });
    const store = SharedPreferencesLocalLivePreferencesStore();

    final restored = await store.load(
      availableSymbols: const ['BTCUSDT', 'ETHUSDT'],
    );

    expect(restored.symbols, const ['BTCUSDT']);
    expect(restored.timeframes, const {'5m'});
    expect(restored.leverage, 125);
    expect(restored.riskPercent, 2);
    expect(restored.dailyLossLimitPercent, 10);
  });
}
