import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../domain/supervisor_connection.dart';

abstract interface class SupervisorSecureKeyValueStore {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}

final class FlutterSupervisorSecureKeyValueStore
    implements SupervisorSecureKeyValueStore {
  FlutterSupervisorSecureKeyValueStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) {
    return _storage.write(key: key, value: value);
  }

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

final class SupervisorStoredSetup {
  const SupervisorStoredSetup({required this.serverOrigin});

  final Uri serverOrigin;
}

final class SupervisorSecureSetupStore {
  SupervisorSecureSetupStore({SupervisorSecureKeyValueStore? secureStore})
    : _secureStore = secureStore ?? FlutterSupervisorSecureKeyValueStore();

  static const _serverOriginKey = 'quantara.supervisor.server_origin';
  static const _controlTokenKey = 'quantara.supervisor.control_token';

  final SupervisorSecureKeyValueStore _secureStore;

  Future<SupervisorStoredSetup?> load({required bool releaseBuild}) async {
    final rawOrigin = await _secureStore.read(_serverOriginKey);
    final token = await _secureStore.read(_controlTokenKey);
    if (rawOrigin == null ||
        rawOrigin.isEmpty ||
        token == null ||
        token.isEmpty) {
      return null;
    }

    final validation = SupervisorSetupValidation.validate(
      serverUrl: rawOrigin,
      controlToken: token,
      releaseBuild: releaseBuild,
    );
    final origin = validation.serverOrigin;
    if (!validation.isValid || origin == null) {
      return null;
    }

    return SupervisorStoredSetup(serverOrigin: origin);
  }

  Future<SupervisorSetupValidation> save({
    required String serverUrl,
    required String controlToken,
    required bool releaseBuild,
  }) async {
    final validation = SupervisorSetupValidation.validate(
      serverUrl: serverUrl,
      controlToken: controlToken,
      releaseBuild: releaseBuild,
    );
    final origin = validation.serverOrigin;
    if (!validation.isValid || origin == null) {
      return validation;
    }

    await _secureStore.write(_serverOriginKey, origin.toString());
    await _secureStore.write(_controlTokenKey, controlToken.trim());
    return validation;
  }

  Future<String?> readControlToken() async {
    final token = await _secureStore.read(_controlTokenKey);
    if (token == null || token.isEmpty) {
      return null;
    }
    return token;
  }

  Future<void> clear() async {
    await _secureStore.delete(_serverOriginKey);
    await _secureStore.delete(_controlTokenKey);
  }
}
