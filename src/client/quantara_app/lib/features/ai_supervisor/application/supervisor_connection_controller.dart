import 'package:flutter/foundation.dart';

import '../domain/supervisor_connection.dart';
import 'supervisor_connection_health_coordinator.dart';
import 'supervisor_secure_setup_store.dart';
import 'supervisor_support_session_client.dart';

final class SupervisorConnectionController extends ChangeNotifier {
  factory SupervisorConnectionController({
    required SupervisorSecureSetupStore setupStore,
    required SupervisorConnectionHealthCoordinator healthCoordinator,
    required bool releaseBuild,
    SupervisorSupportSessionClient? supportSessionClient,
  }) => SupervisorConnectionController._(
    setupStore,
    healthCoordinator,
    releaseBuild,
    supportSessionClient ??
        SupervisorSupportSessionClient(setupStore: setupStore),
  );

  SupervisorConnectionController._(
    this._setupStore,
    this._healthCoordinator,
    this._releaseBuild,
    this._supportSessionClient,
  );

  final SupervisorSecureSetupStore _setupStore;
  final SupervisorConnectionHealthCoordinator _healthCoordinator;
  final bool _releaseBuild;
  final SupervisorSupportSessionClient _supportSessionClient;

  SupervisorConnectionSnapshot _snapshot =
      SupervisorConnectionSnapshot.notConfigured();
  int _revision = 0;

  SupervisorConnectionSnapshot get snapshot => _snapshot;

  Future<void> initialize() async {
    final revision = ++_revision;
    final setup = await _setupStore.load(releaseBuild: _releaseBuild);
    if (revision != _revision) return;
    if (setup == null) {
      _setSnapshot(SupervisorConnectionSnapshot.notConfigured());
      return;
    }
    await _checkConfigured(setup.serverOrigin, revision: revision);
  }

  Future<SupervisorSetupValidation> saveAndCheck({
    required String serverUrl,
    required String controlToken,
  }) async {
    final revision = ++_revision;
    final validation = await _setupStore.save(
      serverUrl: serverUrl,
      controlToken: controlToken,
      releaseBuild: _releaseBuild,
    );
    if (!validation.isValid || validation.serverOrigin == null) {
      return validation;
    }
    if (revision != _revision) return validation;
    await _checkConfigured(validation.serverOrigin!, revision: revision);
    return validation;
  }

  Future<void> checkNow() async {
    final revision = ++_revision;
    final setup = await _setupStore.load(releaseBuild: _releaseBuild);
    if (revision != _revision) return;
    if (setup == null) {
      _setSnapshot(SupervisorConnectionSnapshot.notConfigured());
      return;
    }
    await _checkConfigured(setup.serverOrigin, revision: revision);
  }

  Future<bool> startSupportSession(Duration duration) {
    return _supportSessionClient.start(
      connection: _snapshot,
      duration: duration,
      releaseBuild: _releaseBuild,
    );
  }

  Future<void> stopSupportSession() {
    return _supportSessionClient.stop(connection: _snapshot);
  }

  Future<void> clear() async {
    ++_revision;
    await stopSupportSession();
    await _setupStore.clear();
    _setSnapshot(SupervisorConnectionSnapshot.notConfigured());
  }

  Future<void> _checkConfigured(Uri origin, {required int revision}) async {
    _setSnapshot(
      SupervisorConnectionSnapshot(
        status: SupervisorConnectionStatus.connecting,
        serverOrigin: origin,
        lastSuccessfulHealthCheckAt: _snapshot.lastSuccessfulHealthCheckAt,
      ),
    );
    final result = await _healthCoordinator.checkNow();
    if (revision != _revision) return;
    _setSnapshot(result);
  }

  void _setSnapshot(SupervisorConnectionSnapshot value) {
    _snapshot = value;
    notifyListeners();
  }
}
