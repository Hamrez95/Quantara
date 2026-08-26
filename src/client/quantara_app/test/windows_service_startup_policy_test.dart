import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/windows_desktop/domain/windows_service_startup_policy.dart';

void main() {
  for (final reason in WindowsServiceStartupReason.values) {
    test('$reason never restores new-entry authority', () {
      final snapshot = WindowsServiceStartupPolicy.resolve(
        reason: reason,
        hasExchangeReportedOpenPositions: false,
      );

      expect(snapshot.authority, WindowsServiceAuthorityState.disarmed);
      expect(snapshot.requiresExplicitStart, isTrue);
    });
  }

  test('reboot requires reconciliation even without open positions', () {
    final snapshot = WindowsServiceStartupPolicy.resolve(
      reason: WindowsServiceStartupReason.reboot,
      hasExchangeReportedOpenPositions: false,
    );

    expect(snapshot.reconciliationRequired, isTrue);
  });

  test('cold launch remains disarmed without forcing recovery reconciliation', () {
    final snapshot = WindowsServiceStartupPolicy.resolve(
      reason: WindowsServiceStartupReason.coldLaunch,
      hasExchangeReportedOpenPositions: false,
    );

    expect(snapshot.authority, WindowsServiceAuthorityState.disarmed);
    expect(snapshot.reconciliationRequired, isFalse);
  });

  for (final reason in WindowsServiceStartupReason.values) {
    test('$reason with exchange positions is manage-only and reconciles', () {
      final snapshot = WindowsServiceStartupPolicy.resolve(
        reason: reason,
        hasExchangeReportedOpenPositions: true,
      );

      expect(
        snapshot.authority,
        WindowsServiceAuthorityState.managingProtectedPositions,
      );
      expect(snapshot.requiresExplicitStart, isTrue);
      expect(snapshot.reconciliationRequired, isTrue);
    });
  }
}
