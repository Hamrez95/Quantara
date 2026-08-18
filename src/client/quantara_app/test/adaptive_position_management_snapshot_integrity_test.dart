import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/auto_trade/domain/adaptive_position_management.dart';

void main() {
  test('restart snapshot rejects revision that does not match unique events', () {
    expect(
      () => AdaptiveManagementSnapshot.fromJson({
        'version': 1,
        'state': 'active',
        'revision': 4,
        'processedEvents': [
          {'id': '1', 'kind': 'arm'},
          {'id': '2', 'kind': 'entryConfirmed'},
          {'id': '3', 'kind': 'managementActivated'},
        ],
      }),
      throwsFormatException,
    );
  });

  test('restart snapshot rejects state unsupported by event history', () {
    expect(
      () => AdaptiveManagementSnapshot.fromJson({
        'version': 1,
        'state': 'protected',
        'revision': 4,
        'processedEvents': [
          {'id': '1', 'kind': 'arm'},
          {'id': '2', 'kind': 'entryConfirmed'},
          {'id': '3', 'kind': 'managementActivated'},
          {'id': '4', 'kind': 'runnerActivated'},
        ],
      }),
      throwsFormatException,
    );
  });

  test('valid terminal snapshot with absorbed audit event survives restart', () {
    var snapshot = AdaptiveManagementSnapshot.initial();
    snapshot = snapshot.apply(
      const AdaptiveManagementEvent(
        id: '1',
        kind: AdaptiveManagementEventKind.arm,
      ),
    );
    snapshot = snapshot.apply(
      const AdaptiveManagementEvent(
        id: '2',
        kind: AdaptiveManagementEventKind.entryConfirmed,
      ),
    );
    snapshot = snapshot.apply(
      const AdaptiveManagementEvent(
        id: '3',
        kind: AdaptiveManagementEventKind.exitConfirmed,
      ),
    );
    snapshot = snapshot.apply(
      const AdaptiveManagementEvent(
        id: '4',
        kind: AdaptiveManagementEventKind.managementActivated,
      ),
    );

    final restored = AdaptiveManagementSnapshot.fromJson(snapshot.toJson());

    expect(restored.state, AdaptiveManagementState.exited);
    expect(restored.revision, snapshot.revision);
    expect(restored.processedEvents, snapshot.processedEvents);
  });
}
