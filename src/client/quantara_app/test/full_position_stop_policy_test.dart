import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/auto_trade/domain/full_position_stop_policy.dart';

void main() {
  const expectedPositionId = 'position-1';

  bool confirmed({
    String evidencePositionId = expectedPositionId,
    double price = 100,
    double stopQuantity = 1,
    double remainingQuantity = 1,
    double tolerance = 0.001,
  }) => FullPositionStopPolicy.isConfirmed(
    evidencePositionId: evidencePositionId,
    expectedPositionId: expectedPositionId,
    stopLossPrice: price,
    stopLossQuantity: stopQuantity,
    remainingQuantity: remainingQuantity,
    quantityTolerance: tolerance,
  );

  test('rejects stop belonging to another position', () {
    expect(confirmed(evidencePositionId: 'position-2'), isFalse);
  });

  test(
    'rejects positive stop that protects only part of remaining quantity',
    () {
      expect(confirmed(stopQuantity: 0.4), isFalse);
    },
  );

  test('accepts Bitunix whole-position stop convention', () {
    expect(confirmed(stopQuantity: 0), isTrue);
  });

  test('accepts full remaining quantity within precision tolerance', () {
    expect(confirmed(stopQuantity: 0.9995), isTrue);
  });

  test('rejects missing or invalid stop price', () {
    expect(confirmed(price: 0), isFalse);
    expect(confirmed(price: double.nan), isFalse);
  });

  test('fails closed for invalid quantity evidence', () {
    expect(confirmed(remainingQuantity: 0), isFalse);
    expect(confirmed(stopQuantity: double.nan), isFalse);
    expect(confirmed(tolerance: -0.001), isFalse);
  });
}
