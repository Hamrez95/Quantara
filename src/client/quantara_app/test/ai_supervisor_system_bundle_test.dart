import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/ai_supervisor/domain/supervisor_evidence_ledger.dart';
import 'package:quantara_app/features/ai_supervisor/domain/supervisor_system_bundle.dart';
import 'package:quantara_app/features/ai_supervisor/domain/supervisor_system_evidence.dart';

void main() {
  test('serializes deterministic bounded evidence with coverage metadata', () {
    final capturedAt = DateTime.utc(2026, 8, 14, 8, 30);
    final ledger = SupervisorEvidenceLedger();
    ledger.record(
      SupervisorSystemEvidence(
        evidenceId: 'runtime.scan.1',
        domain: SupervisorEvidenceDomain.runtime,
        kind: 'scannerHeartbeat',
        observedAtUtc: capturedAt,
        summary: 'cycle complete',
        correlationId: 'scan-1',
      ),
      nowUtc: capturedAt,
    );

    final bundle = SupervisorSystemBundle(
      bundleId: 'review-1',
      capturedAtUtc: capturedAt,
      ledger: ledger,
    );

    final first = bundle.toJson().toString();
    final second = bundle.toJson().toString();

    expect(first, second);
    expect(first, contains('runtime.scan.1'));
    expect(first, contains('coverage'));
    expect(first, contains('excludedSecret'));
  });

  test('does not leak credential-like free-form evidence through bundle', () {
    final capturedAt = DateTime.utc(2026, 8, 14, 8, 31);
    final ledger = SupervisorEvidenceLedger();
    ledger.record(
      SupervisorSystemEvidence(
        evidenceId: 'backend.failure.1',
        domain: SupervisorEvidenceDomain.backend,
        kind: 'requestFailure',
        observedAtUtc: capturedAt,
        summary: 'Authorization: Bearer private-value',
        attributes: const {'detail': 'apiSecret=private-secret'},
      ),
      nowUtc: capturedAt,
    );

    final serialized = SupervisorSystemBundle(
      bundleId: 'review-2',
      capturedAtUtc: capturedAt,
      ledger: ledger,
    ).toJson().toString();

    expect(serialized, isNot(contains('private-value')));
    expect(serialized, isNot(contains('private-secret')));
    expect(serialized, contains('[REDACTED]'));
  });
}
