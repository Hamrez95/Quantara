import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/auto_trade/application/profit_lock_promotion_executor.dart';
import 'package:quantara_app/features/auto_trade/domain/trading_pnl_projection.dart';
import 'package:quantara_app/features/owner_alpha/domain/owner_alpha_models.dart';
import 'package:quantara_app/features/owner_alpha/domain/profit_lock_stop_policy.dart';

void main() {
  ExchangePnlFill fill({
    required String tradeId,
    required String orderId,
    required double quantity,
    double price = 1.0603,
  }) => ExchangePnlFill(
    tradeId: tradeId,
    orderId: orderId,
    positionId: 'position-xrp',
    symbol: 'XRPUSDT',
    quantity: quantity,
    price: price,
    realizedPnl: 0.05,
    fee: 0.001,
    reduceOnly: true,
    occurredAt: DateTime.utc(2026, 8, 3, 12),
  );

  test('remaining quantity alone never confirms TP1', () {
    final progress = ConfirmedTargetFillProgress.reconcile(
      targetOrderIds: const ['tp1-order', 'tp2-order', 'tp3-order'],
      targetQuantities: const [14.0, 4.2, 3.2],
      exchangeExitFills: const [],
      processedTradeIds: const {},
      quantityTolerance: 0.05,
      observedRemainingQuantity: 7.4,
    );

    expect(progress.tp1Confirmed, isFalse);
    expect(progress.tp2Confirmed, isFalse);
    expect(progress.newTradeIds, isEmpty);
  });

  test(
    'partial TP1 does not promote until exchange-confirmed target quantity',
    () {
      final partial = ConfirmedTargetFillProgress.reconcile(
        targetOrderIds: const ['tp1-order', 'tp2-order', 'tp3-order'],
        targetQuantities: const [14.0, 4.2, 3.2],
        exchangeExitFills: [
          fill(tradeId: 'tp1-partial-a', orderId: 'tp1-order', quantity: 8),
        ],
        processedTradeIds: const {},
        quantityTolerance: 0.05,
      );
      expect(partial.tp1Confirmed, isFalse);
      expect(partial.tp1FilledQuantity, closeTo(8, 0.0000001));

      final complete = ConfirmedTargetFillProgress.reconcile(
        targetOrderIds: const ['tp1-order', 'tp2-order', 'tp3-order'],
        targetQuantities: const [14.0, 4.2, 3.2],
        exchangeExitFills: [
          fill(tradeId: 'tp1-partial-a', orderId: 'tp1-order', quantity: 8),
          fill(tradeId: 'tp1-partial-b', orderId: 'tp1-order', quantity: 6),
          fill(tradeId: 'tp1-partial-b', orderId: 'tp1-order', quantity: 6),
        ],
        processedTradeIds: const {},
        quantityTolerance: 0.05,
      );

      expect(complete.tp1Confirmed, isTrue);
      expect(complete.tp1FilledQuantity, closeTo(14, 0.0000001));
      expect(complete.newTradeIds, {'tp1-partial-a', 'tp1-partial-b'});
    },
  );

  test('TP2 requires its own exchange order fills', () {
    final progress = ConfirmedTargetFillProgress.reconcile(
      targetOrderIds: const ['tp1-order', 'tp2-order', 'tp3-order'],
      targetQuantities: const [14.0, 4.2, 3.2],
      exchangeExitFills: [
        fill(tradeId: 'tp1', orderId: 'tp1-order', quantity: 14),
        fill(
          tradeId: 'manual-reduction',
          orderId: 'manual-close',
          quantity: 4.2,
        ),
      ],
      processedTradeIds: const {},
      quantityTolerance: 0.05,
    );

    expect(progress.tp1Confirmed, isTrue);
    expect(progress.tp2Confirmed, isFalse);
  });

  test(
    'SHORT TP1 stop is cost-aware, profitable and never worsens a better stop',
    () {
      final decision = ProfitLockStopPolicy.afterTp1(
        direction: TradeDirection.short,
        entryPrice: 1.0665,
        currentConfirmedStop: 1.0691,
        costBufferRate: 0.0017,
        pricePrecision: 4,
      );

      expect(decision.requiresMutation, isTrue);
      expect(decision.proposedStop, closeTo(1.0646, 0.0000001));
      expect(decision.proposedStop, lessThan(1.0665));

      final alreadyBetter = ProfitLockStopPolicy.afterTp1(
        direction: TradeDirection.short,
        entryPrice: 1.0665,
        currentConfirmedStop: 1.0630,
        costBufferRate: 0.0017,
        pricePrecision: 4,
      );
      expect(alreadyBetter.requiresMutation, isFalse);
      expect(alreadyBetter.proposedStop, 1.0630);
    },
  );

  test('LONG TP1 stop moves only upward beyond cost-aware break-even', () {
    final decision = ProfitLockStopPolicy.afterTp1(
      direction: TradeDirection.long,
      entryPrice: 100,
      currentConfirmedStop: 98,
      costBufferRate: 0.0017,
      pricePrecision: 2,
    );

    expect(decision.requiresMutation, isTrue);
    expect(decision.proposedStop, 100.17);
    expect(decision.proposedStop, greaterThan(100));
  });

  test('TP2 promotes SHORT stop to TP1 but never backward', () {
    final decision = ProfitLockStopPolicy.afterTp2(
      direction: TradeDirection.short,
      tp1Price: 1.0603,
      currentConfirmedStop: 1.0646,
      pricePrecision: 4,
    );
    expect(decision.requiresMutation, isTrue);
    expect(decision.proposedStop, 1.0603);

    final alreadyBetter = ProfitLockStopPolicy.afterTp2(
      direction: TradeDirection.short,
      tp1Price: 1.0603,
      currentConfirmedStop: 1.0590,
      pricePrecision: 4,
    );
    expect(alreadyBetter.requiresMutation, isFalse);
    expect(alreadyBetter.proposedStop, 1.0590);
  });

  test('promotion state persists pending request and processed trade IDs', () {
    const state = ProfitLockProgress(
      confirmedStage: 0,
      pendingStage: 1,
      pendingProposedStop: 1.0646,
      processedTradeIds: {'tp1-a', 'tp1-b'},
      warning: 'Awaiting exchange stop confirmation.',
    );

    expect(ProfitLockProgress.fromJson(state.toJson()), state);
  });

  test(
    'executor submits one mutation and confirms by bounded protection reads',
    () async {
      var mutationCalls = 0;
      var readCalls = 0;
      final executor = ProfitLockPromotionExecutor(
        confirmationAttempts: 3,
        confirmationDelay: Duration.zero,
        delay: (_) async {},
      );
      const decision = ProfitLockStopDecision(
        proposedStop: 1.0646,
        requiresMutation: true,
        reason: 'TP1 confirmed',
      );

      final result = await executor.execute(
        direction: TradeDirection.short,
        decision: decision,
        priceTolerance: 0.00005,
        requestMutation: (stop) async {
          mutationCalls++;
          expect(stop, 1.0646);
          return 'modified-stop-order';
        },
        readConfirmedStop: () async {
          readCalls++;
          return readCalls < 2 ? 1.0691 : 1.0646;
        },
      );

      expect(result.confirmed, isTrue);
      expect(result.orderId, 'modified-stop-order');
      expect(mutationCalls, 1);
      expect(readCalls, 2);
    },
  );

  test(
    'ambiguous mutation is never resent and old stop remains authoritative',
    () async {
      var mutationCalls = 0;
      var readCalls = 0;
      final executor = ProfitLockPromotionExecutor(
        confirmationAttempts: 3,
        confirmationDelay: Duration.zero,
        delay: (_) async {},
      );
      const decision = ProfitLockStopDecision(
        proposedStop: 1.0646,
        requiresMutation: true,
        reason: 'TP1 confirmed',
      );

      final result = await executor.execute(
        direction: TradeDirection.short,
        decision: decision,
        priceTolerance: 0.00005,
        requestMutation: (_) async {
          mutationCalls++;
          throw StateError('timeout after submit');
        },
        readConfirmedStop: () async {
          readCalls++;
          return 1.0691;
        },
      );

      expect(result.confirmed, isFalse);
      expect(result.warning, contains('ambiguous'));
      expect(mutationCalls, 1);
      expect(readCalls, 3);
    },
  );
}
