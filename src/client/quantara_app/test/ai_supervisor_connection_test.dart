import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/ai_supervisor/domain/supervisor_connection.dart';

void main() {
  group('SupervisorSetupValidation', () {
    test('accepts HTTPS origin without retaining token', () {
      const token = 'device-bound-control-token-123456789';
      final result = SupervisorSetupValidation.validate(
        serverUrl: 'https://supervisor.example.com/path',
        controlToken: token,
        releaseBuild: true,
      );

      expect(result.isValid, isTrue);
      expect(result.serverOrigin, Uri.parse('https://supervisor.example.com'));
      expect(result.toString(), isNot(contains(token)));
    });

    test('release rejects non-HTTPS server', () {
      final result = SupervisorSetupValidation.validate(
        serverUrl: 'http://supervisor.example.com',
        controlToken: 'device-bound-control-token-123456789',
        releaseBuild: true,
      );

      expect(result.isValid, isFalse);
      expect(
        result.failures,
        contains(SupervisorSetupFailure.insecureServerUrl),
      );
    });

    test('development HTTP is loopback-only', () {
      final loopback = SupervisorSetupValidation.validate(
        serverUrl: 'http://127.0.0.1:8080',
        controlToken: 'device-bound-control-token-123456789',
        releaseBuild: false,
      );
      final remote = SupervisorSetupValidation.validate(
        serverUrl: 'http://192.0.2.10:8080',
        controlToken: 'device-bound-control-token-123456789',
        releaseBuild: false,
      );

      expect(loopback.isValid, isTrue);
      expect(loopback.serverOrigin, Uri.parse('http://127.0.0.1:8080'));
      expect(remote.isValid, isFalse);
      expect(
        remote.failures,
        contains(SupervisorSetupFailure.insecureServerUrl),
      );
    });

    test('rejects URL credentials', () {
      final result = SupervisorSetupValidation.validate(
        serverUrl: 'https://user:secret@supervisor.example.com',
        controlToken: 'device-bound-control-token-123456789',
        releaseBuild: true,
      );

      expect(result.isValid, isFalse);
      expect(
        result.failures,
        contains(SupervisorSetupFailure.invalidServerUrl),
      );
    });

    test('rejects blank and unsafe tokens', () {
      final missing = SupervisorSetupValidation.validate(
        serverUrl: 'https://supervisor.example.com',
        controlToken: '   ',
        releaseBuild: true,
      );
      final unsafe = SupervisorSetupValidation.validate(
        serverUrl: 'https://supervisor.example.com',
        controlToken: 'device-bound-token with-space-123456789',
        releaseBuild: true,
      );

      expect(
        missing.failures,
        contains(SupervisorSetupFailure.missingControlToken),
      );
      expect(
        unsafe.failures,
        contains(SupervisorSetupFailure.invalidControlToken),
      );
    });
  });

  group('SupervisorConnectionSnapshot', () {
    test('not configured is unhealthy', () {
      final snapshot = SupervisorConnectionSnapshot.notConfigured();

      expect(snapshot.status, SupervisorConnectionStatus.notConfigured);
      expect(snapshot.serverOrigin, isNull);
      expect(snapshot.isHealthy, isFalse);
    });

    test('connected state records UTC health time', () {
      final configured = SupervisorConnectionSnapshot(
        status: SupervisorConnectionStatus.connecting,
        serverOrigin: Uri.parse('https://supervisor.example.com'),
      );
      final connected = configured.connectedAt(
        DateTime.parse('2026-08-31T22:10:00+03:30'),
      );

      expect(connected.status, SupervisorConnectionStatus.connected);
      expect(connected.isHealthy, isTrue);
      expect(
        connected.lastSuccessfulHealthCheckAt,
        DateTime.parse('2026-08-31T18:40:00Z'),
      );
      expect(connected.diagnosticCode, isNull);
    });

    test('connected health requires configured origin', () {
      const snapshot = SupervisorConnectionSnapshot(
        status: SupervisorConnectionStatus.connecting,
      );

      expect(
        () => snapshot.connectedAt(DateTime.utc(2026, 8, 31)),
        throwsStateError,
      );
    });
  });
}
