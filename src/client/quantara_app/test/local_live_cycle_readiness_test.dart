import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/auto_trade/domain/local_live_cycle_readiness.dart';

void main() {
  test('empty account does not disarm while fill history is pending', () {
    final readiness = LocalLiveCycleReadinessPolicy.evaluate(
      hasManagedExposure: false,
      hasUnmanagedExchangeExposure: false,
      pnlVerified: false,
      fillsAvailable: false,
    );

    expect(readiness, LocalLiveCycleReadiness.emptyAccountHistoryPending);
    expect(LocalLiveCycleReadinessPolicy.blocksNewEntries(readiness), isFalse);
  });

  test('managed exposure blocks entries when fill history is unavailable', () {
    final readiness = LocalLiveCycleReadinessPolicy.evaluate(
      hasManagedExposure: true,
      hasUnmanagedExchangeExposure: false,
      pnlVerified: false,
      fillsAvailable: false,
    );

    expect(readiness, LocalLiveCycleReadiness.managedExposureHistoryBlocked);
    expect(LocalLiveCycleReadinessPolicy.blocksNewEntries(readiness), isTrue);
  });

  test('unmanaged exchange exposure always blocks new entries', () {
    final readiness = LocalLiveCycleReadinessPolicy.evaluate(
      hasManagedExposure: false,
      hasUnmanagedExchangeExposure: true,
      pnlVerified: true,
      fillsAvailable: true,
    );

    expect(readiness, LocalLiveCycleReadiness.unmanagedExposureBlocked);
    expect(LocalLiveCycleReadinessPolicy.blocksNewEntries(readiness), isTrue);
  });

  test('verified managed exposure remains eligible for reconciliation', () {
    final readiness = LocalLiveCycleReadinessPolicy.evaluate(
      hasManagedExposure: true,
      hasUnmanagedExchangeExposure: false,
      pnlVerified: true,
      fillsAvailable: true,
    );

    expect(readiness, LocalLiveCycleReadiness.ready);
    expect(LocalLiveCycleReadinessPolicy.blocksNewEntries(readiness), isFalse);
  });
}
