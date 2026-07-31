import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/auto_trade/application/local_live_execution_mode_controller.dart';
import 'package:quantara_app/features/auto_trade/data/local_live_execution_mode_store.dart';
import 'package:quantara_app/features/auto_trade/domain/local_live_execution_mode.dart';

final class _MemoryModeStore implements LocalLiveExecutionModeStore {
  _MemoryModeStore(this.value, {this.failSave = false});

  LocalLiveExecutionMode value;
  final bool failSave;

  @override
  Future<LocalLiveExecutionMode> load() async => value;

  @override
  Future<void> save(LocalLiveExecutionMode mode) async {
    if (failSave) throw StateError('save failed');
    value = mode;
  }
}

void main() {
  test('restores the persisted selection without arming trading', () async {
    final controller = LocalLiveExecutionModeController(
      store: _MemoryModeStore(LocalLiveExecutionMode.approvalRequired),
    );

    await controller.initialize();

    expect(controller.mode, LocalLiveExecutionMode.approvalRequired);
    expect(controller.initialized, isTrue);
    expect(controller.isBusy, isFalse);
  });

  test('guarded auto requires an explicit warning acknowledgement', () async {
    final store = _MemoryModeStore(LocalLiveExecutionMode.readOnly);
    final controller = LocalLiveExecutionModeController(store: store);
    await controller.initialize();

    final changed = await controller.select(
      LocalLiveExecutionMode.guardedAuto,
      tradingIsRunning: false,
      autoModeWarningAccepted: false,
    );

    expect(changed, isFalse);
    expect(controller.mode, LocalLiveExecutionMode.readOnly);
    expect(store.value, LocalLiveExecutionMode.readOnly);
  });

  test('user can intentionally switch between approval and auto', () async {
    final store = _MemoryModeStore(LocalLiveExecutionMode.approvalRequired);
    final controller = LocalLiveExecutionModeController(store: store);
    await controller.initialize();

    expect(
      await controller.select(
        LocalLiveExecutionMode.guardedAuto,
        tradingIsRunning: false,
        autoModeWarningAccepted: true,
      ),
      isTrue,
    );
    expect(controller.mode, LocalLiveExecutionMode.guardedAuto);

    expect(
      await controller.select(
        LocalLiveExecutionMode.approvalRequired,
        tradingIsRunning: false,
        autoModeWarningAccepted: true,
      ),
      isTrue,
    );
    expect(controller.mode, LocalLiveExecutionMode.approvalRequired);
  });

  test('mode cannot change while the execution service is running', () async {
    final store = _MemoryModeStore(LocalLiveExecutionMode.guardedAuto);
    final controller = LocalLiveExecutionModeController(store: store);
    await controller.initialize();

    final changed = await controller.select(
      LocalLiveExecutionMode.approvalRequired,
      tradingIsRunning: true,
      autoModeWarningAccepted: true,
    );

    expect(changed, isFalse);
    expect(controller.mode, LocalLiveExecutionMode.guardedAuto);
  });

  test('save failure rolls the visible mode back', () async {
    final store = _MemoryModeStore(
      LocalLiveExecutionMode.readOnly,
      failSave: true,
    );
    final controller = LocalLiveExecutionModeController(store: store);
    await controller.initialize();

    final changed = await controller.select(
      LocalLiveExecutionMode.approvalRequired,
      tradingIsRunning: false,
      autoModeWarningAccepted: true,
    );

    expect(changed, isFalse);
    expect(controller.mode, LocalLiveExecutionMode.readOnly);
    expect(controller.error, isNotNull);
  });

  test('wire names are stable and unknown values fail to read-only', () {
    expect(
      LocalLiveExecutionMode.guardedAuto.wireName,
      'guarded_auto',
    );
    expect(
      LocalLiveExecutionModeJson.parse('approval_required'),
      LocalLiveExecutionMode.approvalRequired,
    );
    expect(
      LocalLiveExecutionModeJson.parse('unexpected'),
      LocalLiveExecutionMode.readOnly,
    );
  });
}
