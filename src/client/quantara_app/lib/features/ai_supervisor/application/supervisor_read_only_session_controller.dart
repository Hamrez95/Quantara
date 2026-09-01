import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/supervisor_read_only_session.dart';

typedef SupervisorNow = DateTime Function();
typedef SupervisorPeriodicTimerFactory = Timer Function(
  Duration interval,
  void Function(Timer timer) callback,
);

final class SupervisorReadOnlySessionController extends ChangeNotifier {
  SupervisorReadOnlySessionController({
    SupervisorNow? now,
    SupervisorPeriodicTimerFactory? timerFactory,
  }) : _now = now ?? DateTime.now,
       _timerFactory = timerFactory ?? Timer.periodic;

  final SupervisorNow _now;
  final SupervisorPeriodicTimerFactory _timerFactory;

  SupervisorReadOnlySession? _session;
  Timer? _ticker;

  SupervisorSessionStatus get status {
    final session = _session;
    if (session == null) return SupervisorSessionStatus.inactive;
    return session.statusAt(_now());
  }

  Duration get remaining {
    final session = _session;
    if (session == null) return Duration.zero;
    return session.remainingAt(_now());
  }

  DateTime? get expiresAt => _session?.expiresAt;

  bool get isActive => status == SupervisorSessionStatus.active;

  void start(Duration duration) {
    _ticker?.cancel();
    _session = SupervisorReadOnlySession(
      startedAt: _now(),
      duration: duration,
    );
    _ticker = _timerFactory(const Duration(seconds: 1), (_) => refresh());
    notifyListeners();
  }

  void stop() {
    final session = _session;
    if (session == null) return;
    session.stop();
    _ticker?.cancel();
    _ticker = null;
    notifyListeners();
  }

  void clear() {
    if (_session == null && _ticker == null) return;
    _ticker?.cancel();
    _ticker = null;
    _session = null;
    notifyListeners();
  }

  void refresh() {
    final session = _session;
    if (session == null) return;
    if (session.statusAt(_now()) != SupervisorSessionStatus.active) {
      _ticker?.cancel();
      _ticker = null;
    }
    notifyListeners();
  }

  Map<String, Object?> evidenceForGateway(Map<String, Object?> evidence) {
    final session = _session;
    if (session == null) {
      throw StateError('Supervisor session is not active.');
    }
    return session.evidenceForGateway(now: _now(), evidence: evidence);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _ticker = null;
    super.dispose();
  }
}
