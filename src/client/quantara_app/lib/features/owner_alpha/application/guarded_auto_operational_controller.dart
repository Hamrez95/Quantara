import 'package:flutter/foundation.dart';

import '../data/durable_guarded_auto_operational_store.dart';
import 'guarded_auto_operational_state.dart';

final class GuardedAutoOperationalController extends ChangeNotifier {
  GuardedAutoOperationalController({required this.store, required this.clock});

  final DurableGuardedAutoOperationalStore store;
  final DateTime Function() clock;

  GuardedAutoOperationalState? _state;
  bool _busy = false;

  GuardedAutoOperationalState? get state => _state;
  bool get busy => _busy;
  bool get blocksNewEntries => _state?.blocksNewEntries ?? true;

  Future<void> initialize() async {
    if (_busy || _state != null) return;
    _busy = true;
    notifyListeners();
    try {
      _state = await store.load(nowUtc: clock().toUtc());
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> emergencyStop({DateTime? lastHealthyAtUtc}) => _pause(
    next: (_state ?? _unknown()).emergencyPause(
      atUtc: clock().toUtc(),
      lastHealthyAtUtc: lastHealthyAtUtc,
    ),
  );

  Future<void> autoDisable({
    required GuardedAutoPauseCause cause,
    required String operatorAction,
    DateTime? lastHealthyAtUtc,
  }) => _pause(
    next: (_state ?? _unknown()).autoDisable(
      cause: cause,
      atUtc: clock().toUtc(),
      operatorAction: operatorAction,
      lastHealthyAtUtc: lastHealthyAtUtc,
    ),
  );

  /// Clears the stop condition only to the non-executing disarmed state.
  Future<void> recoverToDisarmed() => _pause(
    next: (_state ?? _unknown()).recoverToDisarmed(atUtc: clock().toUtc()),
  );

  Future<void> _pause({required GuardedAutoOperationalState next}) async {
    if (_busy) return;
    _busy = true;
    notifyListeners();
    try {
      await store.save(next);
      _state = next;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  GuardedAutoOperationalState _unknown() => GuardedAutoOperationalState.paused(
    cause: GuardedAutoPauseCause.restoredUnknownState,
    atUtc: clock().toUtc(),
    operatorAction: 'Review state and explicitly recover to disarmed.',
  );
}
