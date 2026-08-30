import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/auto_trade/application/private_execution_quality_adapter.dart';
import 'package:quantara_app/features/auto_trade/application/private_order_execution_tracker.dart';
import 'package:quantara_app/features/auto_trade/domain/execution_quality_models.dart';

void main() {
  final decisionAt = DateTime.utc(2026, 8, 18, 8);

  PrivateOrderExecutionObservation observation({
    String correlationId = 'setup-1:attempt-1',
    String symbol = 'BTCUSDT',
    String status = 'FILLED',
    double filledQuantity = 2,
    double orderQuantity = 2,
    double? weightedAverageFillPrice = 101,
    bool ambiguous = false,
    DateTime? submitAtUtc,
    DateTime? acknowledgedAtUtc,
    DateTime? firstFillAtUtc,
    DateTime? finalFillAtUtc,
  }) {
    return PrivateOrderExecutionObservation(
      correlationId: correlationId,
      orderId: 'order-1',
      clientId: correlationId,
      symbol: symbol,
      orderStatus: status,
      submitAtUtc: submitAtUtc,
      acknowledgedAtUtc:
          acknowledgedAtUtc ?? decisionAt.add(const Duration(milliseconds: 20)),
      firstFillAtUtc:
          firstFillAtUtc ??
          (filledQuantity > 0
              ? decisionAt.add(const Duration(milliseconds: 40))
              : null),
      finalFillAtUtc:
          finalFillAtUtc ??
          (status == 'FILLED'
              ? decisionAt.add(const Duration(milliseconds: 60))
              : null),
      filledQuantity: filledQuantity,
      orderQuantity: orderQuantity,
      weightedAverageFillPrice: weightedAverageFillPrice,
      ambiguous: ambiguous,
    );
  }

  PrivateExecutionQualitySnapshot adapt(
    PrivateOrderExecutionObservation value, {
    ExecutionSide side = ExecutionSide.long,
  }) {
    return PrivateExecutionQualityAdapter.fromObservation(
      observation: value,
      expectedCorrelationId: 'setup-1:attempt-1',
      expectedSymbol: 'BTCUSDT',
      side: side,
      decisionAtUtc: decisionAt,
      referencePrice: 100,
    );
  }

  test('trusted filled private truth becomes observed execution evidence', () {
    final submitAt = decisionAt.add(const Duration(milliseconds: 10));
    final snapshot = adapt(observation(submitAtUtc: submitAt));

    expect(snapshot.outcome, ExecutionOutcome.filled);
    expect(snapshot.evidenceQuality, ExecutionEvidenceQuality.observed);
    expect(snapshot.fillRatio, 1);
    expect(snapshot.signedSlippageBps, closeTo(100, 1e-9));
    expect(snapshot.lifecycle, isNotNull);
    expect(snapshot.lifecycle!.submitAtUtc, submitAt);
    expect(
      snapshot.lifecycle!.firstFillAtUtc,
      decisionAt.add(const Duration(milliseconds: 40)),
    );
    expect(snapshot.isTrusted, isTrue);
  });

  test('short slippage keeps adverse-positive sign convention', () {
    final snapshot = adapt(
      observation(weightedAverageFillPrice: 99),
      side: ExecutionSide.short,
    );

    expect(snapshot.signedSlippageBps, closeTo(100, 1e-9));
    expect(snapshot.isTrusted, isTrue);
  });

  test('partial cancel preserves the fill instead of pretending no-fill', () {
    final snapshot = adapt(
      observation(
        status: 'CANCELED',
        filledQuantity: 0.5,
        weightedAverageFillPrice: 100.5,
        finalFillAtUtc: null,
      ),
    );

    expect(snapshot.outcome, ExecutionOutcome.partialFill);
    expect(snapshot.fillRatio, 0.25);
    expect(snapshot.signedSlippageBps, closeTo(50, 1e-9));
    expect(snapshot.isTrusted, isTrue);
  });

  test('zero-fill cancel remains an explicit no-fill outcome', () {
    final snapshot = adapt(
      observation(
        status: 'CANCELED',
        filledQuantity: 0,
        weightedAverageFillPrice: null,
        firstFillAtUtc: null,
        finalFillAtUtc: null,
      ),
    );

    expect(snapshot.outcome, ExecutionOutcome.noFill);
    expect(snapshot.fillRatio, 0);
    expect(snapshot.signedSlippageBps, isNull);
    expect(snapshot.isTrusted, isTrue);
  });

  test('correlation mismatch fails closed and suppresses slippage', () {
    final snapshot = adapt(observation(correlationId: 'other-attempt'));

    expect(snapshot.evidenceQuality, ExecutionEvidenceQuality.insufficient);
    expect(snapshot.signedSlippageBps, isNull);
    expect(snapshot.ambiguous, isTrue);
    expect(snapshot.isTrusted, isFalse);
  });

  test('tracker ambiguity is never upgraded into confirmed quality', () {
    final snapshot = adapt(observation(ambiguous: true));

    expect(snapshot.evidenceQuality, ExecutionEvidenceQuality.insufficient);
    expect(snapshot.signedSlippageBps, isNull);
    expect(snapshot.isTrusted, isFalse);
  });

  test('FILLED with incomplete quantity is treated as inconsistent truth', () {
    final snapshot = adapt(
      observation(filledQuantity: 1, weightedAverageFillPrice: 101),
    );

    expect(snapshot.outcome, ExecutionOutcome.filled);
    expect(snapshot.fillRatio, 0.5);
    expect(snapshot.evidenceQuality, ExecutionEvidenceQuality.insufficient);
    expect(snapshot.signedSlippageBps, isNull);
    expect(snapshot.ambiguous, isTrue);
  });

  test('exchange timestamps before decision are rejected as ambiguous', () {
    final snapshot = adapt(
      observation(
        acknowledgedAtUtc: decisionAt.subtract(const Duration(seconds: 1)),
        firstFillAtUtc: decisionAt.add(const Duration(milliseconds: 10)),
        finalFillAtUtc: decisionAt.add(const Duration(milliseconds: 20)),
      ),
    );

    expect(snapshot.lifecycle, isNull);
    expect(snapshot.evidenceQuality, ExecutionEvidenceQuality.insufficient);
    expect(snapshot.signedSlippageBps, isNull);
  });

  test('submit timestamp after acknowledgement is rejected as ambiguous', () {
    final snapshot = adapt(
      observation(
        submitAtUtc: decisionAt.add(const Duration(milliseconds: 30)),
        acknowledgedAtUtc: decisionAt.add(const Duration(milliseconds: 20)),
      ),
    );

    expect(snapshot.lifecycle, isNull);
    expect(snapshot.evidenceQuality, ExecutionEvidenceQuality.insufficient);
    expect(snapshot.signedSlippageBps, isNull);
    expect(snapshot.isTrusted, isFalse);
  });
}
