import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/ai_supervisor/domain/supervisor_read_only_session.dart';

void main() {
  final startedAt = DateTime.utc(2026, 9, 1, 0);

  test('session is active only inside its explicit time window', () {
    final session = SupervisorReadOnlySession(
      startedAt: startedAt,
      duration: const Duration(minutes: 15),
    );

    expect(
      session.statusAt(startedAt.add(const Duration(minutes: 14))),
      SupervisorSessionStatus.active,
    );
    expect(
      session.remainingAt(startedAt.add(const Duration(minutes: 14))),
      const Duration(minutes: 1),
    );
    expect(
      session.statusAt(startedAt.add(const Duration(minutes: 15))),
      SupervisorSessionStatus.expired,
    );
    expect(
      session.remainingAt(startedAt.add(const Duration(minutes: 15))),
      Duration.zero,
    );
  });

  test('stop revokes access immediately and is idempotent', () {
    final session = SupervisorReadOnlySession(
      startedAt: startedAt,
      duration: const Duration(minutes: 30),
    );

    session.stop();
    session.stop();

    expect(session.isStopped, isTrue);
    expect(session.statusAt(startedAt), SupervisorSessionStatus.stopped);
    expect(session.remainingAt(startedAt), Duration.zero);
    expect(
      () => session.evidenceForGateway(
        now: startedAt,
        evidence: const <String, Object?>{'platform': 'android'},
      ),
      throwsStateError,
    );
  });

  test('session duration is bounded to one hour', () {
    expect(
      () => SupervisorReadOnlySession(
        startedAt: startedAt,
        duration: Duration.zero,
      ),
      throwsArgumentError,
    );
    expect(
      () => SupervisorReadOnlySession(
        startedAt: startedAt,
        duration: const Duration(hours: 1, seconds: 1),
      ),
      throwsArgumentError,
    );
  });

  test('gateway evidence is exact allow-list only', () {
    final session = SupervisorReadOnlySession(
      startedAt: startedAt,
      duration: const Duration(minutes: 15),
    );

    final evidence = session.evidenceForGateway(
      now: startedAt,
      evidence: <String, Object?>{
        'connectionStatus': 'connected',
        'lastSuccessfulHealthCheckAt': '2026-09-01T00:00:00Z',
        'diagnosticCode': 'healthy',
        'appVersion': '1.2.3',
        'platform': 'android',
        'apiKey': 'must-not-cross',
        'apiSecret': 'must-not-cross',
        'signature': 'must-not-cross',
        'authorization': 'Bearer must-not-cross',
        'controlToken': 'must-not-cross',
        'exchangeCredentials': 'must-not-cross',
        'order': <String, Object?>{'symbol': 'BTCUSDT'},
        'cancelOrder': true,
        'stopLoss': 100,
        'takeProfit': 200,
        'leverage': 20,
        'riskLimit': 10,
        'transferFunds': true,
        'autoTrade': true,
        'unknownFutureField': 'must-not-cross',
      },
    );

    expect(evidence.keys.toSet(), supervisorDiagnosticAllowList);
    expect(evidence.values.join(' '), isNot(contains('must-not-cross')));
  });

  test('gateway drops non-scalar values even for allowed keys', () {
    final session = SupervisorReadOnlySession(
      startedAt: startedAt,
      duration: const Duration(minutes: 15),
    );

    final evidence = session.evidenceForGateway(
      now: startedAt,
      evidence: <String, Object?>{
        'platform': <String>['android'],
        'diagnosticCode': <String, String>{'raw': 'unsafe'},
        'connectionStatus': 'connected',
      },
    );

    expect(evidence, const <String, Object?>{'connectionStatus': 'connected'});
  });

  test('expired session cannot send diagnostics', () {
    final session = SupervisorReadOnlySession(
      startedAt: startedAt,
      duration: const Duration(minutes: 1),
    );

    expect(
      () => session.evidenceForGateway(
        now: startedAt.add(const Duration(minutes: 1)),
        evidence: const <String, Object?>{'platform': 'android'},
      ),
      throwsStateError,
    );
  });
}
