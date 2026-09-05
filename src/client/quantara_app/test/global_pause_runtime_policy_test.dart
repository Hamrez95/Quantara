import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/owner_alpha/application/global_pause_runtime_policy.dart';

void main() {
  const policy = GlobalPauseRuntimePolicy();

  test('flat pause is fully offline', () {
    const evidence = GlobalPauseRuntimeEvidence(
      openPositionCount: 0,
      openOrderCount: 0,
      protectionVerified: true,
      accountFresh: true,
      reconciliationHealthy: true,
    );
    final mode = policy.pause(evidence);

    expect(mode, GlobalPauseRuntimeMode.pausedOffline);
    expect(policy.mayStopScanning(mode), isTrue);
    expect(policy.mayStopNonEssentialNetwork(mode), isTrue);
    expect(policy.mustKeepPrivateManagement(mode), isFalse);
    expect(policy.mayStopBackgroundService(mode), isTrue);
  });

  test('exposure preserves private management', () {
    const evidence = GlobalPauseRuntimeEvidence(
      openPositionCount: 1,
      openOrderCount: 0,
      protectionVerified: true,
      accountFresh: true,
      reconciliationHealthy: true,
    );
    final mode = policy.pause(evidence);

    expect(mode, GlobalPauseRuntimeMode.safePausedManagingExisting);
    expect(policy.mustKeepPrivateManagement(mode), isTrue);
    expect(policy.mayStopBackgroundService(mode), isFalse);
  });

  test('stale account truth blocks resume', () {
    const stale = GlobalPauseRuntimeEvidence(
      openPositionCount: 0,
      openOrderCount: 0,
      protectionVerified: true,
      accountFresh: false,
      reconciliationHealthy: true,
    );
    const unreconciled = GlobalPauseRuntimeEvidence(
      openPositionCount: 0,
      openOrderCount: 0,
      protectionVerified: true,
      accountFresh: true,
      reconciliationHealthy: false,
    );

    expect(policy.beginResume(stale), isNull);
    expect(policy.beginResume(unreconciled), isNull);
  });

  test('unprotected exposure blocks resume', () {
    const evidence = GlobalPauseRuntimeEvidence(
      openPositionCount: 1,
      openOrderCount: 0,
      protectionVerified: false,
      accountFresh: true,
      reconciliationHealthy: true,
    );

    expect(policy.beginResume(evidence), isNull);
  });

  test('resume revalidates before running', () {
    const healthy = GlobalPauseRuntimeEvidence(
      openPositionCount: 1,
      openOrderCount: 0,
      protectionVerified: true,
      accountFresh: true,
      reconciliationHealthy: true,
    );
    const unsafe = GlobalPauseRuntimeEvidence(
      openPositionCount: 1,
      openOrderCount: 0,
      protectionVerified: false,
      accountFresh: true,
      reconciliationHealthy: true,
    );
    final started = policy.beginResume(healthy);

    expect(started, GlobalPauseRuntimeMode.resuming);
    expect(
      policy.finishResume(current: started!, evidence: healthy),
      GlobalPauseRuntimeMode.running,
    );
    expect(
      policy.finishResume(
        current: GlobalPauseRuntimeMode.resuming,
        evidence: unsafe,
      ),
      GlobalPauseRuntimeMode.safePausedManagingExisting,
    );
  });
}
