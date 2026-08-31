import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/ai_supervisor/application/supervisor_secure_setup_store.dart';
import 'package:quantara_app/features/ai_supervisor/domain/supervisor_connection.dart';

void main() {
  group('SupervisorSecureSetupStore', () {
    test(
      'stores only normalized HTTPS origin plus token in secure storage',
      () async {
        final secureStore = _FakeSecureStore();
        final store = SupervisorSecureSetupStore(secureStore: secureStore);

        final result = await store.save(
          serverUrl: 'https://supervisor.example.com:8443/path?ignored=no',
          controlToken: 'abcdefghijklmnopqrstuvwxyz123456',
          releaseBuild: true,
        );

        expect(result.isValid, isFalse);
        expect(secureStore.values, isEmpty);

        final validResult = await store.save(
          serverUrl: 'https://supervisor.example.com:8443',
          controlToken: 'abcdefghijklmnopqrstuvwxyz123456',
          releaseBuild: true,
        );

        expect(validResult.isValid, isTrue);
        expect(
          secureStore.values.values,
          contains('https://supervisor.example.com:8443'),
        );
        expect(
          secureStore.values.values,
          contains('abcdefghijklmnopqrstuvwxyz123456'),
        );
      },
    );

    test('load exposes origin but never returns the control token', () async {
      final secureStore = _FakeSecureStore();
      final store = SupervisorSecureSetupStore(secureStore: secureStore);
      await store.save(
        serverUrl: 'https://supervisor.example.com',
        controlToken: 'abcdefghijklmnopqrstuvwxyz123456',
        releaseBuild: true,
      );

      final setup = await store.load(releaseBuild: true);

      expect(setup, isNotNull);
      expect(setup!.serverOrigin, Uri.parse('https://supervisor.example.com'));
      expect(
        setup.toString(),
        isNot(contains('abcdefghijklmnopqrstuvwxyz123456')),
      );
    });

    test('invalid or incomplete stored setup fails closed', () async {
      final secureStore = _FakeSecureStore();
      final store = SupervisorSecureSetupStore(secureStore: secureStore);

      secureStore.values.addAll({
        'quantara.supervisor.server_origin': 'http://supervisor.example.com',
        'quantara.supervisor.control_token': 'abcdefghijklmnopqrstuvwxyz123456',
      });

      expect(await store.load(releaseBuild: true), isNull);

      secureStore.values.remove('quantara.supervisor.control_token');
      expect(await store.load(releaseBuild: true), isNull);
    });

    test(
      'interrupted replacement cannot pair a new origin with an old token',
      () async {
        final secureStore = _FakeSecureStore();
        final store = SupervisorSecureSetupStore(secureStore: secureStore);
        await store.save(
          serverUrl: 'https://old-supervisor.example.com',
          controlToken: 'old-control-token-abcdefghijklmnopqrstuvwxyz',
          releaseBuild: true,
        );

        secureStore.failWriteKey = 'quantara.supervisor.control_token';

        await expectLater(
          store.save(
            serverUrl: 'https://new-supervisor.example.com',
            controlToken: 'new-control-token-abcdefghijklmnopqrstuvwxyz',
            releaseBuild: true,
          ),
          throwsStateError,
        );

        expect(await store.load(releaseBuild: true), isNull);
        expect(
          secureStore.values['quantara.supervisor.server_origin'],
          'https://new-supervisor.example.com',
        );
        expect(
          secureStore.values.containsKey('quantara.supervisor.control_token'),
          isFalse,
        );
      },
    );

    test('clear removes both protected setup values', () async {
      final secureStore = _FakeSecureStore();
      final store = SupervisorSecureSetupStore(secureStore: secureStore);
      await store.save(
        serverUrl: 'https://supervisor.example.com',
        controlToken: 'abcdefghijklmnopqrstuvwxyz123456',
        releaseBuild: true,
      );

      await store.clear();

      expect(secureStore.values, isEmpty);
      expect(await store.load(releaseBuild: true), isNull);
    });

    test('save queued after clear cannot be erased by stale clear', () async {
      final secureStore = _FakeSecureStore();
      final store = SupervisorSecureSetupStore(secureStore: secureStore);
      await store.save(
        serverUrl: 'https://old-supervisor.example.com',
        controlToken: 'old-control-token-abcdefghijklmnopqrstuvwxyz',
        releaseBuild: true,
      );

      final deleteGate = Completer<void>();
      secureStore.blockNextDeleteWith(deleteGate.future);

      final clearFuture = store.clear();
      await Future<void>.delayed(Duration.zero);
      final saveFuture = store.save(
        serverUrl: 'https://new-supervisor.example.com',
        controlToken: 'new-control-token-abcdefghijklmnopqrstuvwxyz',
        releaseBuild: true,
      );
      await Future<void>.delayed(Duration.zero);

      deleteGate.complete();
      await clearFuture;
      final validation = await saveFuture;

      expect(validation.isValid, isTrue);
      expect(
        (await store.load(releaseBuild: true))?.serverOrigin,
        Uri.parse('https://new-supervisor.example.com'),
      );
      expect(
        await store.readControlToken(),
        'new-control-token-abcdefghijklmnopqrstuvwxyz',
      );
    });

    test('development HTTP remains loopback-only across reload', () async {
      final secureStore = _FakeSecureStore();
      final store = SupervisorSecureSetupStore(secureStore: secureStore);

      final loopback = await store.save(
        serverUrl: 'http://127.0.0.1:8787',
        controlToken: 'abcdefghijklmnopqrstuvwxyz123456',
        releaseBuild: false,
      );
      final reloaded = await store.load(releaseBuild: false);
      final releaseReload = await store.load(releaseBuild: true);
      final remote = await store.save(
        serverUrl: 'http://192.168.1.50:8787',
        controlToken: 'abcdefghijklmnopqrstuvwxyz123456',
        releaseBuild: false,
      );

      expect(loopback.isValid, isTrue);
      expect(reloaded?.serverOrigin, Uri.parse('http://127.0.0.1:8787'));
      expect(releaseReload, isNull);
      expect(
        remote.failures,
        contains(SupervisorSetupFailure.insecureServerUrl),
      );
    });
  });
}

final class _FakeSecureStore implements SupervisorSecureKeyValueStore {
  final Map<String, String> values = <String, String>{};
  String? failWriteKey;
  Future<void>? _nextDeleteGate;

  void blockNextDeleteWith(Future<void> gate) {
    _nextDeleteGate = gate;
  }

  @override
  Future<void> delete(String key) async {
    final gate = _nextDeleteGate;
    _nextDeleteGate = null;
    if (gate != null) {
      await gate;
    }
    values.remove(key);
  }

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    if (key == failWriteKey) {
      throw StateError('simulated secure-storage write failure');
    }
    values[key] = value;
  }
}
