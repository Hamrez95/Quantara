import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/ai_supervisor/domain/supervisor_system_evidence.dart';

void main() {
  test('serializes allow-listed system evidence deterministically', () {
    final evidence = SupervisorSystemEvidence(
      evidenceId: 'runtime.scan.42',
      domain: SupervisorEvidenceDomain.runtime,
      kind: 'scannerHeartbeat',
      observedAtUtc: DateTime.utc(2026, 8, 14, 6, 30),
      summary: 'scanner completed cycle',
      component: 'local_live_trade_controller',
      version: '1.2.0-rc.3+126',
      correlationId: 'scan-42',
      attributes: const {'state': 'armed', 'candidateCount': '3'},
    );

    expect(evidence.toJson(), <String, Object?>{
      'schemaVersion': '1',
      'evidenceId': 'runtime.scan.42',
      'domain': 'runtime',
      'kind': 'scannerHeartbeat',
      'observedAtUtc': '2026-08-14T06:30:00.000Z',
      'summary': 'scanner completed cycle',
      'severity': 'info',
      'component': 'local_live_trade_controller',
      'version': '1.2.0-rc.3+126',
      'correlationId': 'scan-42',
      'attributes': <String, String>{'state': 'armed', 'candidateCount': '3'},
    });
  });

  test('redacts credential-like text from evidence fields', () {
    final evidence = SupervisorSystemEvidence(
      evidenceId: 'backend.error.7',
      domain: SupervisorEvidenceDomain.backend,
      kind: 'requestFailure',
      observedAtUtc: DateTime.utc(2026, 8, 14, 6, 31),
      summary: 'Authorization: Bearer private-value',
      attributes: const {'detail': 'apiKey=private-key-value'},
    );

    final json = evidence.toJson().toString();
    expect(json, isNot(contains('private-value')));
    expect(json, isNot(contains('private-key-value')));
    expect(json, contains('[REDACTED]'));
  });
}
