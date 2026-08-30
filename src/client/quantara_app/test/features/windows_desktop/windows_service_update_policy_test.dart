import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/windows_desktop/domain/windows_service_update_policy.dart';

void main() {
  group('WindowsServiceUpdatePolicy', () {
    test('update request never advertises local management authority', () {
      final snapshot = WindowsServiceUpdatePolicy.resolve(
        event: WindowsServiceUpdateEvent.updateRequested,
        hasExchangeReportedOpenPositions: true,
        hasVerifiedQuantaraManagedOpenPositions: true,
        managementExecutorAvailable: true,
      );

      expect(snapshot.mode, WindowsServiceUpdateMode.preparing);
      expect(snapshot.blocksNewEntries, isTrue);
      expect(snapshot.localManagementAvailable, isFalse);
      expect(snapshot.exchangeProtectionAuthoritative, isTrue);
      expect(snapshot.requiresExplicitStart, isTrue);
    });

    test('reconciliation with no positions stays disarmed', () {
      final snapshot = WindowsServiceUpdatePolicy.resolve(
        event: WindowsServiceUpdateEvent.reconciliationSucceeded,
        hasExchangeReportedOpenPositions: false,
        hasVerifiedQuantaraManagedOpenPositions: false,
        managementExecutorAvailable: true,
      );

      expect(snapshot.mode, WindowsServiceUpdateMode.disarmed);
      expect(snapshot.localManagementAvailable, isFalse);
      expect(snapshot.blocksNewEntries, isTrue);
    });

    test('unverified exchange position remains blocked', () {
      final snapshot = WindowsServiceUpdatePolicy.resolve(
        event: WindowsServiceUpdateEvent.reconciliationSucceeded,
        hasExchangeReportedOpenPositions: true,
        hasVerifiedQuantaraManagedOpenPositions: false,
        managementExecutorAvailable: true,
      );

      expect(snapshot.mode, WindowsServiceUpdateMode.blocked);
      expect(snapshot.localManagementAvailable, isFalse);
      expect(snapshot.reconciliationRequired, isTrue);
    });

    test('verified position without executor remains blocked', () {
      final snapshot = WindowsServiceUpdatePolicy.resolve(
        event: WindowsServiceUpdateEvent.reconciliationSucceeded,
        hasExchangeReportedOpenPositions: true,
        hasVerifiedQuantaraManagedOpenPositions: true,
        managementExecutorAvailable: false,
      );

      expect(snapshot.mode, WindowsServiceUpdateMode.blocked);
      expect(snapshot.localManagementAvailable, isFalse);
      expect(snapshot.reconciliationRequired, isTrue);
    });

    test('contradictory durable ownership and exchange truth remains blocked', () {
      final snapshot = WindowsServiceUpdatePolicy.resolve(
        event: WindowsServiceUpdateEvent.reconciliationSucceeded,
        hasExchangeReportedOpenPositions: false,
        hasVerifiedQuantaraManagedOpenPositions: true,
        managementExecutorAvailable: true,
      );

      expect(snapshot.mode, WindowsServiceUpdateMode.blocked);
      expect(snapshot.localManagementAvailable, isFalse);
      expect(snapshot.reconciliationRequired, isTrue);
    });

    test('verified existing position with executor permits management only', () {
      final snapshot = WindowsServiceUpdatePolicy.resolve(
        event: WindowsServiceUpdateEvent.reconciliationSucceeded,
        hasExchangeReportedOpenPositions: true,
        hasVerifiedQuantaraManagedOpenPositions: true,
        managementExecutorAvailable: true,
      );

      expect(snapshot.mode, WindowsServiceUpdateMode.managingExisting);
      expect(snapshot.localManagementAvailable, isTrue);
      expect(snapshot.blocksNewEntries, isTrue);
      expect(snapshot.requiresExplicitStart, isTrue);
    });

    test('failed reconciliation remains fail closed', () {
      final snapshot = WindowsServiceUpdatePolicy.resolve(
        event: WindowsServiceUpdateEvent.reconciliationFailed,
        hasExchangeReportedOpenPositions: true,
        hasVerifiedQuantaraManagedOpenPositions: true,
        managementExecutorAvailable: true,
      );

      expect(snapshot.mode, WindowsServiceUpdateMode.blocked);
      expect(snapshot.localManagementAvailable, isFalse);
      expect(snapshot.reconciliationRequired, isTrue);
      expect(snapshot.blocksNewEntries, isTrue);
    });
  });
}
