import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/autonomy/domain/autonomy_certification.dart';

void main() {
  const scenario = AutonomyFaultScenario(
    version: 'autonomy-certification/1.0',
    seed: 42,
    category: AutonomyFaultCategory.privateExecution,
    faultCode: 'submit-timeout-unknown-outcome',
  );

  List<AutonomyInvariantObservation> allPassing() => AutonomyStopShipInvariant
      .values
      .map(
        (invariant) =>
            AutonomyInvariantObservation(invariant: invariant, passed: true),
      )
      .toList();

  test(
    'complete zero-tolerance matrix is promotion eligible only when all pass',
    () {
      final result = AutonomyCertificationGate.evaluate(
        scenario: scenario,
        observations: allPassing(),
      );

      expect(result.stopShip, isFalse);
      expect(result.promotionEligible, isTrue);
      expect(result.failedInvariants, isEmpty);
      expect(
        result.observations.map((value) => value.invariant),
        AutonomyStopShipInvariant.values,
      );
    },
  );

  test('any invariant failure is a stop-ship result with evidence', () {
    final observations = allPassing();
    final index = observations.indexWhere(
      (value) =>
          value.invariant == AutonomyStopShipInvariant.duplicateLiveOrder,
    );
    observations[index] = AutonomyInvariantObservation(
      invariant: AutonomyStopShipInvariant.duplicateLiveOrder,
      passed: false,
      evidenceIds: const ['order-replay:duplicate-1'],
    );

    final result = AutonomyCertificationGate.evaluate(
      scenario: scenario,
      observations: observations,
    );

    expect(result.stopShip, isTrue);
    expect(result.promotionEligible, isFalse);
    expect(result.failedInvariants, [
      AutonomyStopShipInvariant.duplicateLiveOrder,
    ]);
  });

  test('failed invariant without evidence is rejected', () {
    expect(
      () => AutonomyInvariantObservation(
        invariant: AutonomyStopShipInvariant.riskDoubleSpend,
        passed: false,
      ),
      throwsFormatException,
    );
  });

  test('missing invariant observation cannot produce a green artifact', () {
    final incomplete = allPassing()
      ..removeWhere(
        (value) =>
            value.invariant == AutonomyStopShipInvariant.wrongSideStopAccepted,
      );

    expect(
      () => AutonomyCertificationGate.evaluate(
        scenario: scenario,
        observations: incomplete,
      ),
      throwsStateError,
    );
  });

  test('duplicate invariant observation is rejected', () {
    final duplicate = allPassing()
      ..add(
        AutonomyInvariantObservation(
          invariant: AutonomyStopShipInvariant.marginDoubleSpend,
          passed: true,
        ),
      );

    expect(
      () => AutonomyCertificationGate.evaluate(
        scenario: scenario,
        observations: duplicate,
      ),
      throwsStateError,
    );
  });

  test('scenario seed is deterministic and must be non-negative', () {
    expect(scenario.toJson()['seed'], 42);
    expect(
      () => const AutonomyFaultScenario(
        version: 'autonomy-certification/1.0',
        seed: -1,
        category: AutonomyFaultCategory.marketPublic,
        faultCode: 'duplicate-event',
      ).validate(),
      throwsFormatException,
    );
  });
}
