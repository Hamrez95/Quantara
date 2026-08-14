import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/ai_supervisor/domain/supervisor_review.dart';

void main() {
  test('review keeps facts, hypotheses and recommendations distinct', () {
    final review = SupervisorReview(
      generatedAtUtc: DateTime.parse('2026-08-14T00:00:00+03:30'),
      reviewId: 'review-1',
      snapshotSchemaVersion: '1',
      findings: <SupervisorFinding>[
        SupervisorFinding(
          kind: SupervisorFindingKind.observedFact,
          summary: 'Scanner heartbeat is stale.',
          confidence: 1,
          evidence: const <SupervisorEvidenceRef>[
            SupervisorEvidenceRef(id: 'event-17', source: 'flight-recorder'),
          ],
        ),
        SupervisorFinding(
          kind: SupervisorFindingKind.hypothesis,
          summary: 'A recovered account gate may not have resumed scanning.',
          confidence: 0.65,
          validationTests: const <String>['replay recovered account state'],
        ),
        SupervisorFinding(
          kind: SupervisorFindingKind.recommendation,
          summary: 'Add a deterministic resume regression test.',
          confidence: 0.9,
          rollbackCriteria: const <String>['do not promote if replay diverges'],
        ),
      ],
    );

    final json = review.toJson();
    final findings = json['findings']! as List<Object?>;

    expect(json['schemaVersion'], '1');
    expect(json['generatedAtUtc'], '2026-08-13T20:30:00.000Z');
    expect((findings[0]! as Map<String, Object?>)['kind'], 'observedFact');
    expect((findings[1]! as Map<String, Object?>)['kind'], 'hypothesis');
    expect((findings[2]! as Map<String, Object?>)['kind'], 'recommendation');
  });

  test('review can fail closed when evidence is insufficient', () {
    final review = SupervisorReview(
      generatedAtUtc: DateTime.utc(2026, 8, 14),
      reviewId: 'review-2',
      snapshotSchemaVersion: '1',
      insufficientEvidenceReason: 'exchange truth is stale',
    );

    expect(review.hasSufficientEvidence, isFalse);
    expect(
      review.toJson()['insufficientEvidenceReason'],
      'exchange truth is stale',
    );
  });

  test('finding confidence must stay in the normalized range', () {
    expect(
      () => SupervisorFinding(
        kind: SupervisorFindingKind.hypothesis,
        summary: 'invalid',
        confidence: 1.1,
      ),
      throwsA(isA<AssertionError>()),
    );
  });
}
