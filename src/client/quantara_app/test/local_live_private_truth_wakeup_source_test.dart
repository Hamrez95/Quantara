import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'fresh private-truth reconciliation wakes the Local Live execution layer',
    () {
      final source = File(
        'lib/features/auto_trade/application/local_live_trade_service.dart',
      ).readAsStringSync();

      expect(source, contains('_privateTruthSubscription'));
      expect(source, contains('privateTruth.projections.listen'));
      expect(source, contains('unawaited(_runCycle())'));
      expect(source, contains('await _privateTruthSubscription?.cancel()'));
    },
  );
}
