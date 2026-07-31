import 'package:flutter/foundation.dart';

import '../data/local_live_execution_mode_store.dart';
import '../domain/local_live_execution_mode.dart';

final class LocalLiveExecutionModeController extends ChangeNotifier {
  LocalLiveExecutionModeController({
    LocalLiveExecutionModeStore store =
        const SharedPreferencesLocalLiveExecutionModeStore(),
  }) : _store = store;

  final LocalLiveExecutionModeStore _store;

  LocalLiveExecutionMode _mode = LocalLiveExecutionMode.readOnly;
  bool _initialized = false;
  bool _busy = false;
  String? _error;
  bool _disposed = false;

  LocalLiveExecutionMode get mode => _mode;
  bool get initialized => _initialized;
  bool get isBusy => _busy;
  String? get error => _error;

  Future<void> initialize() async {
    if (_initialized || _busy || _disposed) return;
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      _mode = await _store.load();
      _initialized = true;
    } on Object {
      _mode = LocalLiveExecutionMode.readOnly;
      _error = 'Execution mode could not be restored safely.';
    } finally {
      if (!_disposed) {
        _busy = false;
        notifyListeners();
      }
    }
  }

  Future<bool> select(
    LocalLiveExecutionMode next, {
    required bool tradingIsRunning,
    required bool autoModeWarningAccepted,
  }) async {
    if (_busy || _disposed || next == _mode) return next == _mode;
    if (tradingIsRunning) {
      _error = 'Stop new entries before changing the execution mode.';
      notifyListeners();
      return false;
    }
    if (next == LocalLiveExecutionMode.guardedAuto &&
        !autoModeWarningAccepted) {
      _error = 'Guarded Auto requires explicit acknowledgement.';
      notifyListeners();
      return false;
    }

    final previous = _mode;
    _busy = true;
    _error = null;
    _mode = next;
    notifyListeners();
    try {
      await _store.save(next);
      return true;
    } on Object {
      _mode = previous;
      _error = 'Execution mode could not be saved.';
      return false;
    } finally {
      if (!_disposed) {
        _busy = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
