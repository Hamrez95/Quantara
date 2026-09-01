import '../domain/supervisor_connection.dart';
import 'supervisor_health_client.dart';
import 'supervisor_secure_setup_store.dart';

final class SupervisorConnectionHealthCoordinator {
  factory SupervisorConnectionHealthCoordinator({
    required SupervisorSecureSetupStore setupStore,
    required SupervisorHealthClient healthClient,
    required bool releaseBuild,
  }) {
    return SupervisorConnectionHealthCoordinator._(
      setupStore,
      healthClient,
      releaseBuild,
    );
  }

  SupervisorConnectionHealthCoordinator._(
    this._setupStore,
    this._healthClient,
    this._releaseBuild,
  );

  final SupervisorSecureSetupStore _setupStore;
  final SupervisorHealthClient _healthClient;
  final bool _releaseBuild;

  DateTime? _lastSuccessfulHealthCheckAt;

  Future<SupervisorConnectionSnapshot> checkNow() async {
    final setup = await _setupStore.load(releaseBuild: _releaseBuild);
    if (setup == null) {
      return SupervisorConnectionSnapshot.notConfigured();
    }

    final token = await _setupStore.readControlToken();
    if (token == null || token.isEmpty) {
      return SupervisorConnectionSnapshot.notConfigured();
    }

    final result = await _healthClient.check(
      serverOrigin: setup.serverOrigin,
      controlToken: token,
    );

    switch (result.status) {
      case SupervisorHealthTransportStatus.reachable:
        if (result.supervisorEnabled != true) {
          return SupervisorConnectionSnapshot(
            status: SupervisorConnectionStatus.incompatibleServer,
            serverOrigin: setup.serverOrigin,
            lastSuccessfulHealthCheckAt: _lastSuccessfulHealthCheckAt,
            diagnosticCode: result.diagnosticCode ?? 'supervisor_not_enabled',
          );
        }
        _lastSuccessfulHealthCheckAt = result.checkedAt.toUtc();
        return SupervisorConnectionSnapshot(
          status: SupervisorConnectionStatus.connected,
          serverOrigin: setup.serverOrigin,
          lastSuccessfulHealthCheckAt: _lastSuccessfulHealthCheckAt,
        );
      case SupervisorHealthTransportStatus.tokenExpired:
        return SupervisorConnectionSnapshot(
          status: SupervisorConnectionStatus.expired,
          serverOrigin: setup.serverOrigin,
          lastSuccessfulHealthCheckAt: _lastSuccessfulHealthCheckAt,
          diagnosticCode: result.diagnosticCode,
        );
      case SupervisorHealthTransportStatus.tokenRevoked:
        return SupervisorConnectionSnapshot(
          status: SupervisorConnectionStatus.revoked,
          serverOrigin: setup.serverOrigin,
          lastSuccessfulHealthCheckAt: _lastSuccessfulHealthCheckAt,
          diagnosticCode: result.diagnosticCode,
        );
      case SupervisorHealthTransportStatus.serverUnreachable:
        return SupervisorConnectionSnapshot(
          status: SupervisorConnectionStatus.serverUnreachable,
          serverOrigin: setup.serverOrigin,
          lastSuccessfulHealthCheckAt: _lastSuccessfulHealthCheckAt,
          diagnosticCode: result.diagnosticCode,
        );
      case SupervisorHealthTransportStatus.incompatibleServer:
        return SupervisorConnectionSnapshot(
          status: SupervisorConnectionStatus.incompatibleServer,
          serverOrigin: setup.serverOrigin,
          lastSuccessfulHealthCheckAt: _lastSuccessfulHealthCheckAt,
          diagnosticCode: result.diagnosticCode,
        );
    }
  }
}
