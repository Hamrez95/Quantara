import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/owner_alpha/application/global_pause_observability.dart';
import 'package:quantara_app/features/owner_alpha/application/global_pause_runtime_coordinator.dart';
import 'package:quantara_app/features/owner_alpha/application/global_pause_runtime_policy.dart';
import 'package:quantara_app/features/owner_alpha/data/durable_global_pause_runtime_store.dart';

void main() {
  test(
    'offline pause quiesces scanning network and background service',
    () async {
      final memory = _MemoryStore();
      final operations = _FakeOperations()..evidence = _flatHealthy;
      final coordinator = _coordinator(memory, operations);
      await coordinator.initialize();

      await coordinator.requestPause();

      expect(coordinator.mode, GlobalPauseRuntimeMode.pausedOffline);
      expect(operations.stopScanningCalls, 1);
      expect(operations.stopNetworkCalls, 1);
      expect(operations.stopBackgroundCalls, 1);
      expect(operations.keepPrivateCalls, 0);
    },
  );

  test(
    'live exposure enters safe pause and keeps only private management',
    () async {
      final memory = _MemoryStore();
      final operations = _FakeOperations()..evidence = _protectedExposure;
      final coordinator = _coordinator(memory, operations);
      await coordinator.initialize();

      await coordinator.requestPause(pauseFullyWhenFlat: true);

      expect(
        coordinator.mode,
        GlobalPauseRuntimeMode.safePausedManagingExisting,
      );
      expect(operations.stopScanningCalls, 1);
      expect(operations.stopNetworkCalls, 1);
      expect(operations.keepPrivateCalls, 1);
      expect(operations.stopBackgroundCalls, 0);
    },
  );

  test(
    'pause fully when flat transitions without restarting scanners',
    () async {
      final memory = _MemoryStore();
      final operations = _FakeOperations()..evidence = _protectedExposure;
      final coordinator = _coordinator(memory, operations);
      await coordinator.initialize();
      await coordinator.requestPause(pauseFullyWhenFlat: true);
      operations.evidence = _flatHealthy;

      await coordinator.reconcilePausedExposure();

      expect(coordinator.mode, GlobalPauseRuntimeMode.pausedOffline);
      expect(operations.stopBackgroundCalls, 1);
      expect(operations.prepareResumeCalls, 0);
    },
  );

  test(
    'stale account blocks explicit resume and leaves runtime quiesced',
    () async {
      final memory = _MemoryStore();
      final operations = _FakeOperations()..evidence = _flatHealthy;
      final coordinator = _coordinator(memory, operations);
      await coordinator.initialize();
      await coordinator.requestPause();
      operations.evidence = _staleFlat;

      final resumed = await coordinator.requestResume();

      expect(resumed, isFalse);
      expect(coordinator.mode, GlobalPauseRuntimeMode.pausedOffline);
      expect(operations.prepareResumeCalls, 0);
      expect(operations.stopScanningCalls, greaterThanOrEqualTo(2));
    },
  );

  test(
    'resume validates twice and never grants robot/order authority',
    () async {
      final memory = _MemoryStore();
      final operations = _FakeOperations()..evidence = _flatHealthy;
      final coordinator = _coordinator(memory, operations);
      await coordinator.initialize();
      await coordinator.requestPause();

      final resumed = await coordinator.requestResume();

      expect(resumed, isTrue);
      expect(coordinator.mode, GlobalPauseRuntimeMode.running);
      expect(operations.evidenceReads, greaterThanOrEqualTo(3));
      expect(operations.prepareResumeCalls, 1);
    },
  );

  test('restored offline state is applied before any resume work', () async {
    final memory = _MemoryStore();
    final durable = DurableGlobalPauseRuntimeStore(keyValueStore: memory);
    await durable.persist(
      mode: GlobalPauseRuntimeMode.pausedOffline,
      pauseFullyWhenFlat: true,
    );
    final operations = _FakeOperations()..evidence = _flatHealthy;
    final coordinator = GlobalPauseRuntimeCoordinator(
      store: DurableGlobalPauseRuntimeStore(keyValueStore: memory),
      operations: operations,
      sessionId: 'test-session',
    );

    await coordinator.initialize();

    expect(coordinator.mode, GlobalPauseRuntimeMode.pausedOffline);
    expect(operations.stopScanningCalls, 1);
    expect(operations.stopNetworkCalls, 1);
    expect(operations.stopBackgroundCalls, 1);
    expect(operations.prepareResumeCalls, 0);
    expect(operations.evidenceReads, 0);
  });
}

GlobalPauseRuntimeCoordinator _coordinator(
  _MemoryStore memory,
  _FakeOperations operations,
) => GlobalPauseRuntimeCoordinator(
  store: DurableGlobalPauseRuntimeStore(keyValueStore: memory),
  operations: operations,
  events: _EventSink(),
  sessionId: 'test-session',
  clock: () => DateTime.utc(2026, 9, 4, 10),
);

const _flatHealthy = GlobalPauseRuntimeEvidence(
  openPositionCount: 0,
  openOrderCount: 0,
  protectionVerified: true,
  accountFresh: true,
  reconciliationHealthy: true,
);

const _protectedExposure = GlobalPauseRuntimeEvidence(
  openPositionCount: 1,
  openOrderCount: 0,
  protectionVerified: true,
  accountFresh: true,
  reconciliationHealthy: true,
);

const _staleFlat = GlobalPauseRuntimeEvidence(
  openPositionCount: 0,
  openOrderCount: 0,
  protectionVerified: true,
  accountFresh: false,
  reconciliationHealthy: true,
);

final class _MemoryStore implements GlobalPauseRuntimeKeyValueStore {
  final Map<String, String> values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

final class _EventSink implements GlobalPauseEventSink {
  final List<GlobalPauseEvent> events = <GlobalPauseEvent>[];

  @override
  Future<void> record(GlobalPauseEvent event) async {
    events.add(event);
  }
}

final class _FakeOperations implements GlobalPauseRuntimeOperations {
  GlobalPauseRuntimeEvidence evidence = _flatHealthy;
  int evidenceReads = 0;
  int stopScanningCalls = 0;
  int stopNetworkCalls = 0;
  int keepPrivateCalls = 0;
  int stopBackgroundCalls = 0;
  int prepareResumeCalls = 0;

  @override
  Future<GlobalPauseRuntimeEvidence> refreshAuthoritativeEvidence() async {
    evidenceReads += 1;
    return evidence;
  }

  @override
  Future<void> stopScanningAndCandidateWork() async {
    stopScanningCalls += 1;
  }

  @override
  Future<void> stopNonEssentialNetworkWork() async {
    stopNetworkCalls += 1;
  }

  @override
  Future<void> keepPrivateManagementOnly() async {
    keepPrivateCalls += 1;
  }

  @override
  Future<void> stopBackgroundService() async {
    stopBackgroundCalls += 1;
  }

  @override
  Future<void> prepareNonEssentialRuntimeForResume() async {
    prepareResumeCalls += 1;
  }

  @override
  Future<GlobalPauseActivitySnapshot> activitySnapshot() async =>
      GlobalPauseActivitySnapshot(
        activeScanners: stopScanningCalls == 0 ? 1 : 0,
        activeSubscriptions: stopNetworkCalls == 0 ? 1 : 0,
        activeTimers: stopScanningCalls == 0 ? 1 : 0,
        backgroundServiceActive: stopBackgroundCalls == 0,
      );
}
