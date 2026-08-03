import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/auto_trade/domain/local_live_trade_models.dart';
import 'package:quantara_app/features/owner_alpha/domain/owner_alpha_models.dart';

void main() {
  LocalLiveTradeConfiguration validConfiguration({
    int leverage = 10,
    double riskPercent = 0.10,
    double dailyLossLimitPercent = 1,
    int maximumConcurrentPositions = 1,
    List<String> symbols = const ['BTCUSDT'],
    List<String> timeframes = const ['1h', '4h'],
  }) => LocalLiveTradeConfiguration(
    symbols: symbols,
    timeframes: timeframes,
    leverage: leverage,
    riskPercent: riskPercent,
    dailyLossLimitPercent: dailyLossLimitPercent,
    maximumConcurrentPositions: maximumConcurrentPositions,
    strategy: AnalysisStrategy.structureZones,
    cadence: SignalCadence.balanced,
    languageCode: 'fa',
  );

  test('accepts a one-position tiny-risk Android canary configuration', () {
    expect(validConfiguration().validate, returnsNormally);
  });

  test('accepts bounded advanced risk and rejects values above 2 percent', () {
    expect(
      validConfiguration(riskPercent: 2, dailyLossLimitPercent: 10).validate,
      returnsNormally,
    );
    expect(
      () => validConfiguration(riskPercent: 2.01).validate(),
      throwsFormatException,
    );
    expect(
      () => validConfiguration(dailyLossLimitPercent: 10.01).validate(),
      throwsFormatException,
    );
  });

  test('rejects more than one concurrent position', () {
    expect(
      () => validConfiguration(maximumConcurrentPositions: 2).validate(),
      throwsFormatException,
    );
  });

  test('accepts 5m and rejects unsupported execution timeframes', () {
    expect(
      validConfiguration(timeframes: const ['5m']).validate,
      returnsNormally,
    );
    expect(
      () => validConfiguration(timeframes: const ['2m']).validate(),
      throwsFormatException,
    );
  });

  test('round-trips non-secret configuration without expanding authority', () {
    final original = validConfiguration(
      leverage: 20,
      riskPercent: 0.20,
      dailyLossLimitPercent: 1.5,
      symbols: const ['BTCUSDT', 'ETHUSDT'],
    );

    final restored = LocalLiveTradeConfiguration.fromJson(original.toJson());

    expect(restored.symbols, const ['BTCUSDT', 'ETHUSDT']);
    expect(restored.timeframes, const ['1h', '4h']);
    expect(restored.leverage, 20);
    expect(restored.riskPercent, 0.20);
    expect(restored.dailyLossLimitPercent, 1.5);
    expect(restored.maximumConcurrentPositions, 1);
  });

  test('status reports running only for active or managing-only states', () {
    LocalLiveTradeStatus status(LocalLiveTradeState state) =>
        LocalLiveTradeStatus(
          state: state,
          updatedAt: DateTime.utc(2026, 7, 30),
          message: state.name,
        );

    expect(status(LocalLiveTradeState.running).isRunning, isTrue);
    expect(status(LocalLiveTradeState.managingOnly).isRunning, isTrue);
    expect(status(LocalLiveTradeState.starting).isRunning, isFalse);
    expect(status(LocalLiveTradeState.circuitBreaker).isRunning, isFalse);
    expect(status(LocalLiveTradeState.stopped).isRunning, isFalse);
  });
}
