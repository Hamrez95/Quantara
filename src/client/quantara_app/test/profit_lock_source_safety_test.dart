import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Local Live promotion is fill-ID based and never quantity-ratio based',
    () {
      final source = File(
        'lib/features/auto_trade/application/local_live_trade_service.dart',
      ).readAsStringSync();

      expect(source, contains('ConfirmedTargetFillProgress.reconcile'));
      expect(source, contains('positionPnl.exitFills'));
      expect(source, contains('targetOrderIds'));
      expect(source, contains('pendingProposedStop'));
      expect(
        source,
        isNot(contains('position.quantity / managed.initialQuantity')),
      );
      expect(source, isNot(contains('tp1Trigger')));
      expect(source, isNot(contains('tp2Trigger')));
    },
  );

  test('promotion executor sends at most one mutation and only polls reads', () {
    final source = File(
      'lib/features/auto_trade/application/profit_lock_promotion_executor.dart',
    ).readAsStringSync();

    expect(
      RegExp(r'requestMutation\(decision\.proposedStop\)').allMatches(source),
      hasLength(1),
    );
    expect(source, contains('readConfirmedStop'));
    expect(source, contains('Never resend mutation'));
    expect(source.toLowerCase(), isNot(contains('cancel')));
    expect(source.toLowerCase(), isNot(contains('withdraw')));
    expect(source.toLowerCase(), isNot(contains('transfer')));
  });

  test(
    'Bitunix stop modification never removes the previous protection first',
    () {
      final source = File(
        'lib/features/auto_trade/data/bitunix_local_live_api_client.dart',
      ).readAsStringSync();
      final start = source.indexOf('Future<String> modifyPositionStop');
      final end = source.indexOf(
        'Future<String> placePartialTakeProfit',
        start,
      );
      final method = source.substring(start, end);

      expect(method, contains('/api/v1/futures/tpsl/position/modify_order'));
      expect(method.toLowerCase(), isNot(contains('cancel')));
      expect(method.toLowerCase(), isNot(contains('delete')));
    },
  );
}
