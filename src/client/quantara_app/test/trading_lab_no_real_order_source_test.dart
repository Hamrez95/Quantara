import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Trading Lab paper execution has no private exchange write dependency',
    () {
      final files = [
        File(
          'lib/features/trading_lab/application/trading_lab_paper_broker.dart',
        ),
        File(
          'lib/features/trading_lab/application/trading_lab_controller.dart',
        ),
        File('lib/features/trading_lab/domain/trading_lab_models.dart'),
      ];

      for (final file in files) {
        final source = file.readAsStringSync();
        expect(source, isNot(contains('BitunixPrivateApiClient')));
        expect(source, isNot(contains('placeOrder')));
        expect(source, isNot(contains('createOrder')));
        expect(source, isNot(contains('cancelOrder')));
        expect(source, isNot(contains('submitOrder')));
        expect(source, isNot(contains('apiSecret')));
        expect(source, isNot(contains('SecureAutoTradeCredentialsStore')));
      }
    },
  );

  test(
    'Trading Lab export source keeps explicit credential redaction keys',
    () {
      final source = File(
        'lib/features/trading_lab/application/trading_lab_review_bundle.dart',
      ).readAsStringSync();

      for (final marker in [
        'apikey',
        'secret',
        'signature',
        'authorization',
        'token',
        'credential',
        'password',
      ]) {
        expect(source, contains("'$marker'"));
      }
    },
  );
}
