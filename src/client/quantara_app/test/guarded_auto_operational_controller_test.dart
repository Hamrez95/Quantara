import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/owner_alpha/application/guarded_auto_operational_controller.dart';
import 'package:quantara_app/features/owner_alpha/application/guarded_auto_operational_state.dart';
import 'package:quantara_app/features/owner_alpha/data/durable_guarded_auto_operational_store.dart';

void main() {
  test('missing durable state restores paused and blocks new entries', () async {
    final memory = _MemoryStore();
    final controller = GuardedAutoOperationalController(
      store: DurableGuardedAutoOperationalStore(keyValueStore: memory),
      clock: () => DateTime.utc(2026, 9, 4, 1),
    );

    expect(controller.blocksNewEntries, isTrue);
    await controller.initialize();

    expect(controller.state!.isPaused, isTrue);
    expect(
      controller.state!.pauseCause,
      GuardedAutoPauseCause.restoredUnknownState,
    );
    expect(controller.blocksNewEntries, isTrue);
  });

  test('emergency stop is durable and restart remains paused', () async {
    final memory = _MemoryStore();
    final store = DurableGuardedAutoOperationalStore(keyValueStore: memory);
    final controller = GuardedAutoOperationalController(
      store: store,
      clock: () => DateTime.utc(2026, 9, 4, 2),
    );
    await controller.initialize();
    await controller.emergencyStop(
      lastHealthyAtUtc: DateTime.utc(2026, 9, 4, 1, 59),
    );

    final restarted = GuardedAutoOperationalController(
      store: DurableGuardedAutoOperationalStore(keyValueStore: memory),
      clock: () => DateTime.utc(2026, 9, 4, 3),
    );
    await restarted.initialize();

    expect(restarted.state!.isPaused, isTrue);
    expect(
      restarted.state!.pauseCause,
      GuardedAutoPauseCause.userEmergencyStop,
    );
    expect(
      restarted.state!.lastHealthyAtUtc,
      DateTime.utc(2026, 9, 4, 1, 59),
    );
    expect(restarted.blocksNewEntries, isTrue);
  });

  test('anomaly auto-disable records cause and operator action', () async {
    final controller = GuardedAutoOperationalController(
      store: DurableGuardedAutoOperationalStore(
        keyValueStore: _MemoryStore(),
      ),
      clock: () => DateTime.utc(2026, 9, 4, 4),
    );

    await controller.autoDisable(
      cause: GuardedAutoPauseCause.reconciliationFailure,
      operatorAction: 'Reconcile exchange evidence before recovery.',
      lastHealthyAtUtc: DateTime.utc(2026, 9, 4, 3, 58),
    );

    expect(controller.state!.isPaused, isTrue);
    expect(
      controller.state!.pauseCause,
      GuardedAutoPauseCause.reconciliationFailure,
    );
    expect(
      controller.state!.operatorAction,
      'Reconcile exchange evidence before recovery.',
    );
    expect(controller.blocksNewEntries, isTrue);
  });

  test('recovery can only return to disarmed and never rearms', () async {
    final memory = _MemoryStore();
    var now = DateTime.utc(2026, 9, 4, 5);
    final controller = GuardedAutoOperationalController(
      store: DurableGuardedAutoOperationalStore(keyValueStore: memory),
      clock: () => now,
    );
    await controller.emergencyStop();

    now = DateTime.utc(2026, 9, 4, 5, 1);
    await controller.recoverToDisarmed();

    expect(controller.state!.mode, GuardedAutoOperationalMode.disarmed);
    expect(controller.state!.pauseCause, isNull);
    expect(controller.blocksNewEntries, isTrue);

    final restarted = GuardedAutoOperationalController(
      store: DurableGuardedAutoOperationalStore(keyValueStore: memory),
      clock: () => DateTime.utc(2026, 9, 4, 6),
    );
    await restarted.initialize();
    expect(restarted.state!.mode, GuardedAutoOperationalMode.disarmed);
    expect(restarted.blocksNewEntries, isTrue);
  });

  test('corrupt durable state fails closed', () async {
    final memory = _MemoryStore()
      ..values['quantara.guarded-auto-operational-v1'] = '{bad';
    final controller = GuardedAutoOperationalController(
      store: DurableGuardedAutoOperationalStore(keyValueStore: memory),
      clock: () => DateTime.utc(2026, 9, 4, 7),
    );

    await controller.initialize();

    expect(controller.state!.isPaused, isTrue);
    expect(
      controller.state!.pauseCause,
      GuardedAutoPauseCause.restoredUnknownState,
    );
    expect(controller.blocksNewEntries, isTrue);
  });
}

final class _MemoryStore implements GuardedAutoOperationalKeyValueStore {
  final Map<String, String> values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}
