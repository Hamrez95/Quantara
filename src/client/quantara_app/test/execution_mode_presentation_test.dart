import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/auto_trade/domain/local_live_trade_models.dart';
import 'package:quantara_app/features/autonomy/domain/autonomy_policy_gateway.dart';
import 'package:quantara_app/features/owner_alpha/presentation/execution_mode_presentation.dart';

void main() {
  test('stopped runtime is presented as read only', () {
    final presentation = ExecutionModePresentation.fromLocalLive(
      _status(LocalLiveTradeState.stopped),
      persian: false,
    );

    expect(presentation.mode, AutonomyExecutionMode.readOnly);
    expect(presentation.title, 'Read Only');
    expect(presentation.newEntriesEnabled, isFalse);
    expect(presentation.failClosed, isFalse);
    expect(presentation.rawState, 'stopped');
  });

  test('running runtime only claims entry when domain evidence enables it', () {
    final blocked = ExecutionModePresentation.fromLocalLive(
      _status(LocalLiveTradeState.running),
      persian: false,
    );
    final enabled = ExecutionModePresentation.fromLocalLive(
      _status(LocalLiveTradeState.running, entriesEnabled: true),
      persian: false,
    );

    expect(blocked.mode, AutonomyExecutionMode.guardedAuto);
    expect(blocked.failClosed, isTrue);
    expect(blocked.summary, contains('fail-closed'));
    expect(enabled.mode, AutonomyExecutionMode.guardedAuto);
    expect(enabled.newEntriesEnabled, isTrue);
    expect(enabled.failClosed, isFalse);
  });

  test('management and unsafe runtime states remain visibly fail closed', () {
    for (final state in <LocalLiveTradeState>[
      LocalLiveTradeState.starting,
      LocalLiveTradeState.managingOnly,
      LocalLiveTradeState.circuitBreaker,
      LocalLiveTradeState.error,
    ]) {
      final presentation = ExecutionModePresentation.fromLocalLive(
        _status(state, entriesEnabled: true),
        persian: true,
      );

      expect(presentation.mode, AutonomyExecutionMode.guardedAuto);
      expect(presentation.newEntriesEnabled, isFalse, reason: state.name);
      expect(presentation.failClosed, isTrue, reason: state.name);
      expect(presentation.status, 'ورود مسدود');
    }
  });
}

LocalLiveTradeStatus _status(
  LocalLiveTradeState state, {
  bool entriesEnabled = false,
}) => LocalLiveTradeStatus(
  state: state,
  updatedAt: DateTime.utc(2026, 8, 18),
  message: state.name,
  entriesEnabled: entriesEnabled,
);
