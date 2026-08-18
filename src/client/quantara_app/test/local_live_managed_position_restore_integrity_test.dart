import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/auto_trade/domain/local_live_trade_models.dart';
import 'package:quantara_app/features/owner_alpha/domain/owner_alpha_models.dart';

void main() {
  Map<String, Object?> persisted() => LocalLiveManagedPosition(
    setupId: 'setup-107',
    symbol: 'BTCUSDT',
    timeframe: '1h',
    direction: TradeDirection.long,
    positionId: 'position-107',
    entryOrderId: 'entry-107',
    clientId: 'q-local-107',
    initialQuantity: 0.01,
    entryPrice: 100,
    originalStopLoss: 95,
    targets: const [105, 110, 115],
    leverage: 3,
    openedAt: DateTime.utc(2026, 8, 18, 14),
  ).toJson();

  test('valid persisted managed ownership survives restart decoding', () {
    final restored = LocalLiveManagedPosition.fromJson(persisted());

    expect(restored.positionId, 'position-107');
    expect(restored.clientId, 'q-local-107');
    expect(restored.direction, TradeDirection.long);
  });

  test('restart rejects incomplete or non-Quantara ownership identity', () {
    for (final mutation in <void Function(Map<String, Object?>)>[
      (json) => json['setupId'] = ' ',
      (json) => json['positionId'] = '',
      (json) => json['entryOrderId'] = '',
      (json) => json['clientId'] = 'manual-order',
      (json) => json['symbol'] = '',
      (json) => json['timeframe'] = '',
    ]) {
      final json = persisted();
      mutation(json);
      expect(
        () => LocalLiveManagedPosition.fromJson(json),
        throwsFormatException,
      );
    }
  });

  test('restart rejects non-actionable or economically invalid exposure', () {
    for (final mutation in <void Function(Map<String, Object?>)>[
      (json) => json['direction'] = TradeDirection.wait.name,
      (json) => json['initialQuantity'] = 0,
      (json) => json['entryPrice'] = 0,
      (json) => json['originalStopLoss'] = 0,
      (json) => json['leverage'] = 0,
      (json) => json['openedAt'] = 'not-a-date',
      (json) => json['originalStopLoss'] = 105,
    ]) {
      final json = persisted();
      mutation(json);
      expect(
        () => LocalLiveManagedPosition.fromJson(json),
        throwsFormatException,
      );
    }
  });

  test('short restart requires stop to remain on the protective side', () {
    final json = persisted()
      ..['direction'] = TradeDirection.short.name
      ..['originalStopLoss'] = 105;

    expect(LocalLiveManagedPosition.fromJson(json), isA<LocalLiveManagedPosition>());

    json['originalStopLoss'] = 95;
    expect(
      () => LocalLiveManagedPosition.fromJson(json),
      throwsFormatException,
    );
  });
}
