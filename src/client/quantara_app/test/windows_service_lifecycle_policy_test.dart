import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/windows_desktop/domain/windows_service_lifecycle_policy.dart';

void main() {
  for (final event in <WindowsServiceLifecycleEvent>[
    WindowsServiceLifecycleEvent.sleep,
    WindowsServiceLifecycleEvent.hibernate,
    WindowsServiceLifecycleEvent.networkLost,
  ]) {
    test('$event immediately fails closed and requires recovery', () {
      final snapshot = WindowsServiceLifecyclePolicy.resolve(
        event: event,
        hasExchangeReportedOpenPositions: true,
      );

      expect(snapshot.mode, WindowsServiceLifecycleMode.interrupted);
      expect(snapshot.warningRequired, isTrue);
      expect(snapshot.blocksNewEntries, isTrue);
      expect(snapshot.canManageExistingPositions, isFalse);
      expect(snapshot.reconciliationRequired, isTrue);
      expect(snapshot.requiresExplicitStart, isTrue);
    });
  }

  for (final event in <WindowsServiceLifecycleEvent>[
    WindowsServiceLifecycleEvent.wake,
    WindowsServiceLifecycleEvent.networkRestored,
  ]) {
    test('$event with exchange positions is reconciliation-only', () {
      final snapshot = WindowsServiceLifecyclePolicy.resolve(
        event: event,
        hasExchangeReportedOpenPositions: true,
      );

      expect(snapshot.mode, WindowsServiceLifecycleMode.reconciliationOnly);
      expect(snapshot.warningRequired, isTrue);
      expect(snapshot.blocksNewEntries, isTrue);
      expect(snapshot.canManageExistingPositions, isFalse);
      expect(snapshot.reconciliationRequired, isTrue);
      expect(snapshot.requiresExplicitStart, isTrue);
    });

    test('$event without exchange positions remains disarmed', () {
      final snapshot = WindowsServiceLifecyclePolicy.resolve(
        event: event,
        hasExchangeReportedOpenPositions: false,
      );

      expect(snapshot.mode, WindowsServiceLifecycleMode.disarmed);
      expect(snapshot.warningRequired, isTrue);
      expect(snapshot.blocksNewEntries, isTrue);
      expect(snapshot.canManageExistingPositions, isFalse);
      expect(snapshot.reconciliationRequired, isTrue);
      expect(snapshot.requiresExplicitStart, isTrue);
    });
  }

  test('repeated recovery resolution never silently restores authority', () {
    final first = WindowsServiceLifecyclePolicy.resolve(
      event: WindowsServiceLifecycleEvent.networkRestored,
      hasExchangeReportedOpenPositions: true,
    );
    final repeated = WindowsServiceLifecyclePolicy.resolve(
      event: WindowsServiceLifecycleEvent.networkRestored,
      hasExchangeReportedOpenPositions: true,
    );

    expect(repeated.mode, first.mode);
    expect(repeated.blocksNewEntries, isTrue);
    expect(repeated.requiresExplicitStart, isTrue);
    expect(repeated.canManageExistingPositions, isFalse);
  });
}
