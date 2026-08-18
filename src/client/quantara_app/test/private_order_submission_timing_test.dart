import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/auto_trade/application/private_order_execution_tracker.dart';
import 'package:quantara_app/features/auto_trade/domain/private_truth_models.dart';

void main() {
  test(
    'submission timestamp is correlated into accepted private order truth',
    () {
      final tracker = PrivateOrderExecutionTracker();
      final submittedAt = DateTime.utc(2026, 8, 18, 7, 59, 59, 990);
      final acknowledgedAt = DateTime.utc(2026, 8, 18, 8);

      tracker.recordSubmission(
        correlationId: 'setup-1:attempt-1',
        submittedAtUtc: submittedAt,
      );
      tracker.recordAccepted(
        _orderEvent(
          clientId: 'setup-1:attempt-1',
          atUtc: acknowledgedAt,
        ),
      );

      final observation = tracker.observationFor('order-1')!;
      expect(observation.submitAtUtc, submittedAt);
      expect(observation.acknowledgedAtUtc, acknowledgedAt);
      expect(observation.ambiguous, isFalse);
    },
  );

  test(
    'acknowledgement earlier than recorded submit fails closed',
    () {
      final tracker = PrivateOrderExecutionTracker();
      final acknowledgedAt = DateTime.utc(2026, 8, 18, 8);

      tracker.recordSubmission(
        correlationId: 'setup-1:attempt-1',
        submittedAtUtc: acknowledgedAt.add(const Duration(milliseconds: 1)),
      );
      tracker.recordAccepted(
        _orderEvent(
          clientId: 'setup-1:attempt-1',
          atUtc: acknowledgedAt,
        ),
      );

      expect(tracker.observationFor('order-1')!.ambiguous, isTrue);
    },
  );
}

PrivateTruthEvent _orderEvent({
  required String clientId,
  required DateTime atUtc,
}) => PrivateTruthEvent(
  eventIdentity: 'order-1:new',
  channel: PrivateTruthChannel.order,
  exchangeTimestampUtc: atUtc,
  receivedAtUtc: atUtc.add(const Duration(milliseconds: 5)),
  processedAtUtc: atUtc.add(const Duration(milliseconds: 7)),
  payload: PrivateOrderUpdate(
    event: 'UPDATE',
    orderId: 'order-1',
    clientId: clientId,
    symbol: 'BTCUSDT',
    side: 'BUY',
    orderType: 'MARKET',
    orderStatus: 'NEW',
    quantity: 1,
    dealAmount: 0,
    averagePrice: 0,
    fee: 0,
    updatedAtUtc: atUtc,
  ),
);
