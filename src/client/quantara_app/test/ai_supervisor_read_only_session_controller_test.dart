import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/ai_supervisor/application/supervisor_read_only_session_controller.dart';
import 'package:quantara_app/features/ai_supervisor/domain/supervisor_read_only_session.dart';

void main() {
  test('controller exposes deterministic remaining time and expiry', () {
    var now = DateTime.utc(2026, 9, 1, 0);
    final timers = <_FakeTimer>[];
    final controller = SupervisorReadOnlySessionController(
      now: () => now,
      timerFactory: (interval, callback) {
        final timer = _FakeTimer(callback);
        timers.add(timer);
        return timer;
      },
    );
    addTearDown(controller.dispose);

    controller.start(const Duration(minutes: 15));
    expect(controller.status, SupervisorSessionStatus.active);
    expect(controller.remaining, const Duration(minutes: 15));
    expect(timers.single.isActive, isTrue);

    now = now.add(const Duration(minutes: 14));
    timers.single.fire();
    expect(controller.remaining, const Duration(minutes: 1));

    now = now.add(const Duration(minutes: 1));
    timers.single.fire();
    expect(controller.status, SupervisorSessionStatus.expired);
    expect(controller.remaining, Duration.zero);
    expect(timers.single.isActive, isFalse);
  });

  test('stop is immediate and blocks gateway evidence', () {
    final startedAt = DateTime.utc(2026, 9, 1, 0);
    final controller = SupervisorReadOnlySessionController(
      now: () => startedAt,
      timerFactory: (interval, callback) => _FakeTimer(callback),
    );
    addTearDown(controller.dispose);

    controller.start(const Duration(minutes: 30));
    controller.stop();
    controller.stop();

    expect(controller.status, SupervisorSessionStatus.stopped);
    expect(controller.remaining, Duration.zero);
    expect(
      () => controller.evidenceForGateway(const <String, Object?>{
        'platform': 'android',
      }),
      throwsStateError,
    );
  });

  test('invalid restart preserves the current active session', () {
    final startedAt = DateTime.utc(2026, 9, 1, 0);
    final timers = <_FakeTimer>[];
    final controller = SupervisorReadOnlySessionController(
      now: () => startedAt,
      timerFactory: (interval, callback) {
        final timer = _FakeTimer(callback);
        timers.add(timer);
        return timer;
      },
    );
    addTearDown(controller.dispose);

    controller.start(const Duration(minutes: 30));
    final originalExpiry = controller.expiresAt;
    final originalTimer = timers.single;

    expect(
      () => controller.start(const Duration(hours: 2)),
      throwsArgumentError,
    );

    expect(controller.status, SupervisorSessionStatus.active);
    expect(controller.expiresAt, originalExpiry);
    expect(originalTimer.isActive, isTrue);
    expect(timers, hasLength(1));
  });

  test('gateway keeps exact allow-list and clear removes session', () {
    final startedAt = DateTime.utc(2026, 9, 1, 0);
    final controller = SupervisorReadOnlySessionController(
      now: () => startedAt,
      timerFactory: (interval, callback) => _FakeTimer(callback),
    );
    addTearDown(controller.dispose);

    controller.start(const Duration(minutes: 10));
    final evidence = controller.evidenceForGateway(<String, Object?>{
      'connectionStatus': 'connected',
      'platform': 'android',
      'controlToken': 'must-not-cross',
      'order': 'must-not-cross',
    });

    expect(evidence, const <String, Object?>{
      'connectionStatus': 'connected',
      'platform': 'android',
    });

    controller.clear();
    expect(controller.status, SupervisorSessionStatus.inactive);
    expect(controller.remaining, Duration.zero);
    expect(
      () => controller.evidenceForGateway(const <String, Object?>{
        'platform': 'android',
      }),
      throwsStateError,
    );
  });
}

final class _FakeTimer implements Timer {
  _FakeTimer(this._callback);

  final void Function(Timer timer) _callback;
  bool _active = true;
  int _tick = 0;

  void fire() {
    if (!_active) return;
    _tick++;
    _callback(this);
  }

  @override
  bool get isActive => _active;

  @override
  int get tick => _tick;

  @override
  void cancel() {
    _active = false;
  }
}
