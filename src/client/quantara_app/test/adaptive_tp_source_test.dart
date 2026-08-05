import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Local Live places only active target orders and persists inactive slots',
    () {
      final service = File(
        'lib/features/auto_trade/application/local_live_trade_service.dart',
      ).readAsStringSync();
      expect(service, contains('ProfitProtectionAllocation.allocateAdaptive'));
      expect(service, contains("final targetOrderIds = <String>['', '', ''];"));
      expect(service, contains('if (targetQuantities[index] <= 0) continue;'));
      expect(service, contains('targetAllocation: effectiveAllocation'));
      expect(
        service,
        isNot(contains('minimumQuantity / profitPlan.minimumTargetFraction')),
      );
    },
  );

  test('audit UI localizes normal status kinds instead of generic errors', () {
    final ui = File(
      'lib/features/owner_alpha/presentation/owner_alpha_auto_trade.dart',
    ).readAsStringSync();
    final localizer = File(
      'lib/core/localization/local_live_message_localizer.dart',
    ).readAsStringSync();
    expect(ui, contains('LocalLiveMessageLocalizer.localizeAudit'));
    expect(localizer, contains("'pnl_projection_pending_empty_account'"));
    expect(localizer, contains("'target_allocation_adapted'"));
  });

  test(
    'orphan recovery accepts one to three targets and pads inactive slots',
    () {
      final recovery = File(
        'lib/features/auto_trade/application/local_live_orphan_recovery.dart',
      ).readAsStringSync();
      expect(recovery, contains('targets.isEmpty || targets.length > 3'));
      expect(recovery, contains('paddedQuantities'));
      expect(recovery, contains("List<String>.filled(3 - targets.length, '')"));
    },
  );
}
