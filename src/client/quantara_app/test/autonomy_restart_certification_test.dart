import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/autonomy/domain/autonomy_restart_certification.dart';

void main() {
  List<AutonomyRestartObservation> allPassing() {
    final observations = <AutonomyRestartObservation>[];
    for (final checkpoint in AutonomyRestartCheckpoint.values) {
      observations.add(
        AutonomyRestartObservation(
          checkpoint: checkpoint,
          recovered: true,
          idempotent: true,
          reservationConsistent: true,
          protectionConsistent: true,
        ),
      );
    }
    return observations;
  }

  test('all restart boundaries must pass before promotion is eligible', () {
    final result = AutonomyRestartCertificationGate.evaluate(
      observations: allPassing(),
    );

    expect(result.stopShip, isFalse);
    expect(result.promotionEligible, isTrue);
    expect(result.failedCheckpoints, isEmpty);
    expect(
      result.observations.map((value) => value.checkpoint),
      AutonomyRestartCheckpoint.values,
    );
  });

  test('unknown submit outcome cannot blind-submit a duplicate order', () {
    final observations = allPassing();
    final index = AutonomyRestartCheckpoint.submitUnknownOutcome.index;
    observations[index] = AutonomyRestartObservation(
      checkpoint: AutonomyRestartCheckpoint.submitUnknownOutcome,
      recovered: true,
      idempotent: true,
      reservationConsistent: true,
      protectionConsistent: true,
      duplicateSubmitAttempted: true,
      evidenceIds: const ['submit-unknown:duplicate-attempt-blocker'],
    );

    final result = AutonomyRestartCertificationGate.evaluate(
      observations: observations,
    );

    expect(result.stopShip, isTrue);
    expect(result.promotionEligible, isFalse);
    expect(result.failedCheckpoints, [
      AutonomyRestartCheckpoint.submitUnknownOutcome,
    ]);
  });

  test('reservation inconsistency after restart is a stop-ship failure', () {
    final observations = allPassing();
    final index = AutonomyRestartCheckpoint.fill.index;
    observations[index] = AutonomyRestartObservation(
      checkpoint: AutonomyRestartCheckpoint.fill,
      recovered: true,
      idempotent: true,
      reservationConsistent: false,
      protectionConsistent: true,
      evidenceIds: const ['risk-ledger:reservation-drift'],
    );

    final result = AutonomyRestartCertificationGate.evaluate(
      observations: observations,
    );

    expect(result.stopShip, isTrue);
    expect(result.failedCheckpoints, [AutonomyRestartCheckpoint.fill]);
  });

  test('failed restart checkpoint requires explicit evidence', () {
    expect(
      () => AutonomyRestartObservation(
        checkpoint: AutonomyRestartCheckpoint.protection,
        recovered: false,
        idempotent: true,
        reservationConsistent: true,
        protectionConsistent: false,
      ),
      throwsFormatException,
    );
  });

  test('missing restart checkpoint cannot produce a green artifact', () {
    final incomplete = allPassing();
    incomplete.removeAt(AutonomyRestartCheckpoint.management.index);

    expect(
      () => AutonomyRestartCertificationGate.evaluate(observations: incomplete),
      throwsStateError,
    );
  });

  test('duplicate restart checkpoint is rejected', () {
    final duplicate = allPassing();
    duplicate.add(
      AutonomyRestartObservation(
        checkpoint: AutonomyRestartCheckpoint.acknowledgement,
        recovered: true,
        idempotent: true,
        reservationConsistent: true,
        protectionConsistent: true,
      ),
    );

    expect(
      () => AutonomyRestartCertificationGate.evaluate(observations: duplicate),
      throwsStateError,
    );
  });

  test('restart evidence IDs are normalized and cannot be empty', () {
    final observation = AutonomyRestartObservation(
      checkpoint: AutonomyRestartCheckpoint.close,
      recovered: false,
      idempotent: true,
      reservationConsistent: true,
      protectionConsistent: true,
      evidenceIds: const ['  close-reconcile:missing-truth  '],
    );

    expect(observation.evidenceIds, ['close-reconcile:missing-truth']);
    expect(
      () => AutonomyRestartObservation(
        checkpoint: AutonomyRestartCheckpoint.close,
        recovered: false,
        idempotent: true,
        reservationConsistent: true,
        protectionConsistent: true,
        evidenceIds: const ['   '],
      ),
      throwsFormatException,
    );
  });
}
