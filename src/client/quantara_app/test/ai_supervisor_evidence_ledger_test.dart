import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/ai_supervisor/domain/supervisor_evidence_ledger.dart';
import 'package:quantara_app/features/ai_supervisor/domain/supervisor_system_evidence.dart';

SupervisorSystemEvidence evidence(
  String id,
  DateTime observedAtUtc, {
  String? correlationId,
}) => SupervisorSystemEvidence(
  evidenceId: id,
  domain: SupervisorEvidenceDomain.runtime,
  kind: 'test',
  observedAtUtc: observedAtUtc,
  summary: 'test evidence',
  correlationId: correlationId,
);

void main() {
  test('prunes expired and oldest evidence while preserving deterministic order', () {
    final now = DateTime.utc(2026, 8, 14, 8);
    final ledger = SupervisorEvidenceLedger(
      maxEntries: 2,
      maxAge: const Duration(days: 1),
    );

    ledger.recordAll(<SupervisorSystemEvidence>[
      evidence('expired', now.subtract(const Duration(days: 2))),
      evidence('b', now.subtract(const Duration(minutes: 2))),
      evidence('a', now.subtract(const Duration(minutes: 1))),
      evidence('c', now),
    ], nowUtc: now);

    expect(ledger.length, 2);
    expect(
      ledger.snapshot().map((entry) => entry.evidenceId).toList(),
      <String>['a', 'c'],
    );
  });

  test('correlates evidence across components by stable correlation id', () {
    final now = DateTime.utc(2026, 8, 14, 8);
    final ledger = SupervisorEvidenceLedger();

    ledger.recordAll(<SupervisorSystemEvidence>[
      evidence('scan', now, correlationId: 'trade-42'),
      evidence('journal', now.add(const Duration(seconds: 1)), correlationId: 'trade-42'),
      evidence('other', now.add(const Duration(seconds: 2)), correlationId: 'trade-99'),
    ], nowUtc: now.add(const Duration(seconds: 2)));

    expect(
      ledger.byCorrelationId('trade-42').map((entry) => entry.evidenceId).toList(),
      <String>['scan', 'journal'],
    );
  });
}
