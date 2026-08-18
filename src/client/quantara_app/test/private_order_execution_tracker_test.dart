import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/auto_trade/application/private_order_execution_tracker.dart';
import 'package:quantara_app/features/auto_trade/domain/private_truth_models.dart';

void main() {
  PrivateTruthEvent orderEvent({
    required String identity,
    required String orderId,
    required String clientId,
    required String status,
    required double quantity,
    required double dealAmount,
    required double averagePrice,
    required DateTime atUtc,
  }) => PrivateTruthEvent(
    eventIdentity: identity,
    channel: PrivateTruthChannel.order,
    exchangeTimestampUtc: atUtc,
    receivedAtUtc: atUtc.add(const Duration(milliseconds: 5)),
    processedAtUtc: atUtc.add(const Duration(milliseconds: 7)),
    payload: PrivateOrderUpdate(
      event: 'UPDATE',
      orderId: orderId,
      clientId: clientId,
      symbol: 'BTCUSDT',
      side: 'BUY',
      orderType: 'MARKET',
      orderStatus: status,
      quantity: quantity,
      dealAmount: dealAmount,
      averagePrice: averagePrice,
      fee: 0,
      updatedAtUtc: atUtc,
    ),
  );

  test(
    'captures submit, acknowledgement, fills and weighted price',
    () {
      final tracker = PrivateOrderExecutionTracker();
      final submitAt = DateTime.utc(2026, 8, 18, 0, 59, 59, 990);
      final acknowledgedAt = DateTime.utc(2026, 8, 18, 1);
      final firstFillAt = acknowledgedAt.add(const Duration(milliseconds: 25));
      final finalFillAt = acknowledgedAt.add(const Duration(milliseconds: 60));

      tracker.recordSubmission(
        correlationId: 'q-local-1',
        submittedAtUtc: submitAt,
      );
      tracker.recordAccepted(
        orderEvent(
          identity: 'ack',
          orderId: 'ord-1',
          clientId: 'q-local-1',
          status: 'NEW',
          quantity: 1,
          dealAmount: 0,
          averagePrice: 0,
          atUtc: acknowledgedAt,
        ),
      );
      tracker.recordAccepted(
        orderEvent(
          identity: 'partial',
          orderId: 'ord-1',
          clientId: 'q-local-1',
          status: 'PARTIALLY_FILLED',
          quantity: 1,
          dealAmount: 0.4,
          averagePrice: 100.1,
          atUtc: firstFillAt,
        ),
      );
      tracker.recordAccepted(
        orderEvent(
          identity: 'filled',
          orderId: 'ord-1',
          clientId: 'q-local-1',
          status: 'FILLED',
          quantity: 1,
          dealAmount: 1,
          averagePrice: 100.25,
          atUtc: finalFillAt,
        ),
      );

      final observation = tracker.observationFor('ord-1');
      expect(observation, isNotNull);
      expect(observation!.correlationId, 'q-local-1');
      expect(observation.submitAtUtc, submitAt);
      expect(observation.acknowledgedAtUtc, acknowledgedAt);
      expect(observation.firstFillAtUtc, firstFillAt);
      expect(observation.finalFillAtUtc, finalFillAt);
      expect(observation.filledQuantity, 1);
      expect(observation.fillRatio, 1);
      expect(observation.weightedAverageFillPrice, 100.25);
      expect(observation.ambiguous, isFalse);
    },
  );

  test('acknowledgement before local submit timing fails closed', () {
    final tracker = PrivateOrderExecutionTracker();
    final acknowledgedAt = DateTime.utc(2026, 8, 18, 1);

    tracker.recordSubmission(
      correlationId: 'q-local-1',
      submittedAtUtc: acknowledgedAt.add(const Duration(milliseconds: 1)),
    );
    tracker.recordAccepted(
      orderEvent(
        identity: 'ack-before-submit',
        orderId: 'ord-1',
        clientId: 'q-local-1',
        status: 'NEW',
        quantity: 1,
        dealAmount: 0,
        averagePrice: 0,
        atUtc: acknowledgedAt,
      ),
    );

    final observation = tracker.observationFor('ord-1')!;
    expect(observation.submitAtUtc, isNotNull);
    expect(observation.ambiguous, isTrue);
  });

  test(
    'regressive cumulative fill is flagged and never reduces known fill',
    () {
      final tracker = PrivateOrderExecutionTracker();
      final first = DateTime.utc(2026, 8, 18, 1);

      tracker.recordAccepted(
        orderEvent(
          identity: 'partial-a',
          orderId: 'ord-1',
          clientId: 'q-local-1',
          status: 'PARTIALLY_FILLED',
          quantity: 1,
          dealAmount: 0.6,
          averagePrice: 100.2,
          atUtc: first,
        ),
      );
      tracker.recordAccepted(
        orderEvent(
          identity: 'filled-regression',
          orderId: 'ord-1',
          clientId: 'q-local-1',
          status: 'FILLED',
          quantity: 1,
          dealAmount: 0.4,
          averagePrice: 99.5,
          atUtc: first.add(const Duration(milliseconds: 10)),
        ),
      );

      final observation = tracker.observationFor('ord-1')!;
      expect(observation.filledQuantity, 0.6);
      expect(observation.weightedAverageFillPrice, 100.2);
      expect(observation.finalFillAtUtc, isNull);
      expect(observation.ambiguous, isTrue);
    },
  );

  test('retention is strictly bounded and evicts oldest order evidence', () {
    final tracker = PrivateOrderExecutionTracker(maximumEntries: 2);
    final now = DateTime.utc(2026, 8, 18, 1);

    for (var index = 1; index <= 3; index++) {
      tracker.recordAccepted(
        orderEvent(
          identity: 'order-$index',
          orderId: 'ord-$index',
          clientId: 'q-local-$index',
          status: 'NEW',
          quantity: 1,
          dealAmount: 0,
          averagePrice: 0,
          atUtc: now.add(Duration(milliseconds: index)),
        ),
      );
    }

    expect(tracker.length, 2);
    expect(tracker.observationFor('ord-1'), isNull);
    expect(tracker.observationFor('ord-2'), isNotNull);
    expect(tracker.observationFor('ord-3'), isNotNull);
  });

  test('invalid retention capacity and submit identity fail closed', () {
    expect(
      () => PrivateOrderExecutionTracker(maximumEntries: 0),
      throwsFormatException,
    );
    final tracker = PrivateOrderExecutionTracker();
    expect(
      () => tracker.recordSubmission(
        correlationId: ' ',
        submittedAtUtc: DateTime.utc(2026, 8, 18),
      ),
      throwsFormatException,
    );
  });
}
