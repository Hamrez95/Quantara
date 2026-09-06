import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'a confirmed Local Live start retries an idempotent ephemeral credential handoff',
    () {
      final controller = File(
        'lib/features/auto_trade/application/local_live_trade_controller.dart',
      ).readAsStringSync();
      final service = File(
        'lib/features/auto_trade/application/local_live_trade_service.dart',
      ).readAsStringSync();

      expect(controller, contains('_credentialDeliveryAttempts = 4'));
      expect(controller, contains('Future<void> _deliverStartCommand'));
      expect(controller, contains("'commandId': commandId"));
      expect(controller, contains('for (var attempt = 0;'));
      expect(controller, contains('API credentials therefore remain confined'));
      expect(
        controller,
        isNot(contains('saveData(\n        key: localLiveCredentials')),
      );

      expect(service, contains('_acceptedStartCommandId'));
      expect(service, contains('commandId == _acceptedStartCommandId'));
      expect(service, contains('Do not recreate sockets'));
    },
  );

  test(
    'a credential-waiting foreground task leaves an explicit recovery path',
    () {
      final ui = File(
        'lib/features/owner_alpha/presentation/owner_alpha_auto_trade.dart',
      ).readAsStringSync();

      expect(
        ui,
        contains(
          'status.isRunning || status.state == LocalLiveTradeState.starting',
        ),
      );
      expect(ui, contains("'Complete secure start'"));
      expect(ui, isNot(contains('||\n                          starting ||')));
    },
  );
}
