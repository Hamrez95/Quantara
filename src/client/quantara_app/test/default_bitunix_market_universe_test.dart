import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/auto_trade/data/local_live_preferences_store.dart';
import 'package:quantara_app/features/owner_alpha/application/owner_alpha_controller.dart';
import 'package:quantara_app/features/owner_alpha/data/local_live_realtime_universe.dart';

void main() {
  test('fresh installs seed thirty curated Bitunix USDT markets', () {
    const symbols = OwnerAlphaController.defaultSymbols;

    expect(symbols, hasLength(30));
    expect(symbols.toSet(), hasLength(30));
    expect(symbols.every((symbol) => symbol.endsWith('USDT')), isTrue);
    expect(symbols, containsAll(['BTCUSDT', 'ETHUSDT', 'SOLUSDT', 'XRPUSDT']));
  });

  test('watchlist and Local Live normalization preserve more than thirty symbols', () {
    final symbols = List.generate(64, (index) => 'Q${index}USDT');
    final preferences = LocalLivePreferences(
      symbols: symbols,
      timeframes: const {'1h'},
      leverage: 5,
      riskPercent: 0.25,
      dailyLossLimitPercent: 1,
    ).normalized(symbols);

    expect(preferences.symbols, symbols);
    expect(LocalLiveRealtimeUniverse.build(preferences).streams, hasLength(64));
  });
}
