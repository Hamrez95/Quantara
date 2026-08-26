import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/windows_desktop/domain/windows_service_update_policy.dart';

void main() {
  test(
    'every update transition blocks entries and requires explicit restart',
    () {
      for (final event in WindowsServiceUpdateEvent.values) {
        final snapshot = WindowsServiceUpdatePolicy.resolve(
          event: event,
          hasExchangeReportedOpenPositions: false,
        );

        expect(snapshot.blocksNewEntries, isTrue, reason: event.name);
        expect(snapshot.requiresExplicitStart, isTrue, reason: event.name);
        expect(
          snapshot.exchangeProtectionAuthoritative,
          isTrue,
          reason: event.name,
        );
      }
    },
  );

  test(
    'update request stops entries but keeps existing management available',
    () {
      final snapshot = WindowsServiceUpdatePolicy.resolve(
        event: WindowsServiceUpdateEvent.updateRequested,
        hasExchangeReportedOpenPositions: true,
      );

      expect(snapshot.mode, WindowsServiceUpdateMode.preparing);
      expect(snapshot.blocksNewEntries, isTrue);
      expect(snapshot.localManagementAvailable, isTrue);
    },
  );

  test('service stop hands authority back to exchange-native protection', () {
    final snapshot = WindowsServiceUpdatePolicy.resolve(
      event: WindowsServiceUpdateEvent.serviceStoppedForInstall,
      hasExchangeReportedOpenPositions: true,
    );

    expect(snapshot.mode, WindowsServiceUpdateMode.installing);
    expect(snapshot.localManagementAvailable, isFalse);
    expect(snapshot.exchangeProtectionAuthoritative, isTrue);
  });

  test('successful install requires reconciliation before any recovery', () {
    final snapshot = WindowsServiceUpdatePolicy.resolve(
      event: WindowsServiceUpdateEvent.installSucceeded,
      hasExchangeReportedOpenPositions: false,
    );

    expect(snapshot.mode, WindowsServiceUpdateMode.reconciliationOnly);
    expect(snapshot.reconciliationRequired, isTrue);
    expect(snapshot.rollbackRequired, isFalse);
  });

  test('failed install requires rollback and fresh reconciliation', () {
    final snapshot = WindowsServiceUpdatePolicy.resolve(
      event: WindowsServiceUpdateEvent.installFailed,
      hasExchangeReportedOpenPositions: true,
    );

    expect(snapshot.mode, WindowsServiceUpdateMode.rollbackRequired);
    expect(snapshot.rollbackRequired, isTrue);
    expect(snapshot.reconciliationRequired, isTrue);
    expect(snapshot.blocksNewEntries, isTrue);
  });

  test(
    'reconciled open positions resume management without re-arming entries',
    () {
      final snapshot = WindowsServiceUpdatePolicy.resolve(
        event: WindowsServiceUpdateEvent.reconciliationSucceeded,
        hasExchangeReportedOpenPositions: true,
      );

      expect(snapshot.mode, WindowsServiceUpdateMode.managingExisting);
      expect(snapshot.reconciliationRequired, isFalse);
      expect(snapshot.localManagementAvailable, isTrue);
      expect(snapshot.blocksNewEntries, isTrue);
      expect(snapshot.requiresExplicitStart, isTrue);
    },
  );

  test('successful reconciliation without positions ends disarmed', () {
    final snapshot = WindowsServiceUpdatePolicy.resolve(
      event: WindowsServiceUpdateEvent.reconciliationSucceeded,
      hasExchangeReportedOpenPositions: false,
    );

    expect(snapshot.mode, WindowsServiceUpdateMode.disarmed);
    expect(snapshot.reconciliationRequired, isFalse);
    expect(snapshot.localManagementAvailable, isFalse);
    expect(snapshot.blocksNewEntries, isTrue);
    expect(snapshot.requiresExplicitStart, isTrue);
  });

  test('failed reconciliation remains blocked', () {
    final snapshot = WindowsServiceUpdatePolicy.resolve(
      event: WindowsServiceUpdateEvent.reconciliationFailed,
      hasExchangeReportedOpenPositions: true,
    );

    expect(snapshot.mode, WindowsServiceUpdateMode.blocked);
    expect(snapshot.reconciliationRequired, isTrue);
    expect(snapshot.localManagementAvailable, isFalse);
    expect(snapshot.blocksNewEntries, isTrue);
  });
}
