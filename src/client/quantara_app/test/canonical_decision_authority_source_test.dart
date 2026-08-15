import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('canonical decision core has no real-order authority', () {
    final source = [
      File(
        'lib/features/decision_core/domain/canonical_decision_models.dart',
      ).readAsStringSync(),
      File(
        'lib/features/decision_core/application/canonical_decision_pipeline.dart',
      ).readAsStringSync(),
    ].join('\n');

    for (final forbidden in const [
      'BitunixApiCredentials',
      'BitunixLocalLiveApiClient',
      'placeMarketEntry',
      'placeOrder',
      'cancelEntryOrder',
      'closePositionReduceOnly',
      'package:http',
      'dart:io',
    ]) {
      expect(source, isNot(contains(forbidden)), reason: forbidden);
    }
  });
}
