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
    clientId: 'q-local-1234abcd',
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
    expect(restored.clientId, 'q-local-1234abcd');
    expect(restored.direction, TradeDirection.long);
    expect(restored.openedAt.isUtc, isTrue);
  });

  test('restart rejects incomplete or non-Quantara ownership identity', () {
    for (final mutation in <void Function(Map<String, Object?>)>[
      (json) => json['setupId'] = ' ',
      (json) => json['positionId'] = '',
      (json) => json['entryOrderId'] = '',
      (json) => json['clientId'] = 'manual-order',
      (json) => json['clientId'] = 'q-local-not-hex',
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
      (json) => json['initialQuantity'] = double.nan,
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

  test('restart rejects invalid target geometry', () {
    for (final mutation in <void Function(Map<String, Object?>)>[
      (json) => json['targets'] = <double>[],
      (json) => json['targets'] = [105, double.nan],
      (json) => json['targets'] = [105, 99],
      (json) => json['targets'] = [105, 110, 115, 120],
    ]) {
      final json = persisted();
      mutation(json);
      expect(
        () => LocalLiveManagedPosition.fromJson(json),
        throwsFormatException,
      );
    }
  });

  test('short restart requires stop and targets on the protective sides', () {
    final json = persisted()
      ..['direction'] = TradeDirection.short.name
      ..['originalStopLoss'] = 105
      ..['targets'] = [95, 90, 85];

    final restored = LocalLiveManagedPosition.fromJson(json);
    expect(restored.direction, TradeDirection.short);

    json['originalStopLoss'] = 95;
    expect(
      () => LocalLiveManagedPosition.fromJson(json),
      throwsFormatException,
    );

    json['originalStopLoss'] = 105;
    json['targets'] = [95, 101];
    expect(
      () => LocalLiveManagedPosition.fromJson(json),
      throwsFormatException,
    );
  });
}
