import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/autonomy/domain/autonomy_certification.dart';
import 'package:quantara_app/features/autonomy/domain/autonomy_fault_campaign.dart';
import 'package:quantara_app/features/autonomy/domain/autonomy_fault_runner.dart';

void main() {
  List<AutonomyFaultCampaignScenario> campaign() => AutonomyFaultCode.values
      .map(
        (fault) => AutonomyFaultCampaignScenario(
          version: 'fault-runner/1.0',
          seed: 1000 + fault.index,
          fault: fault,
          category: fault.category,
        ),
      )
      .toList(growable: false);

  Iterable<AutonomyInvariantObservation> observations({
    AutonomyStopShipInvariant? failed,
    String evidenceId = 'fault:evidence',
  }) => AutonomyStopShipInvariant.values.map(
    (invariant) => AutonomyInvariantObservation(
      invariant: invariant,
      passed: invariant != failed,
      evidenceIds: invariant == failed ? [evidenceId] : const [],
    ),
  );

  test(
    'runner executes and certifies every required fault exactly once',
    () async {
      final executed = <AutonomyFaultCode>[];

      final result = await AutonomyFaultCampaignRunner.run(
        scenarios: campaign(),
        execute: (scenario) async {
          executed.add(scenario.fault);
          return observations();
        },
      );

      expect(executed, AutonomyFaultCode.values);
      expect(result.certifications, hasLength(AutonomyFaultCode.values.length));
      expect(result.stopShip, isFalse);
      expect(result.promotionEligible, isTrue);
      expect(result.failedFaultCodes, isEmpty);
    },
  );

  test(
    'one machine-asserted invariant failure stop-ships the campaign',
    () async {
      final result = await AutonomyFaultCampaignRunner.run(
        scenarios: campaign(),
        execute: (scenario) async {
          if (scenario.fault == AutonomyFaultCode.submitTimeoutUnknownOutcome) {
            return observations(
              failed: AutonomyStopShipInvariant.ambiguousMutationReleasedRisk,
              evidenceId: 'supervisor:unknown-submit-risk-release',
            );
          }
          return observations();
        },
      );

      expect(result.stopShip, isTrue);
      expect(result.promotionEligible, isFalse);
      expect(result.failedFaultCodes, [
        AutonomyFaultCode.submitTimeoutUnknownOutcome.name,
      ]);
    },
  );

  test(
    'runner fails closed before execution when campaign is incomplete',
    () async {
      final incomplete = campaign().toList()
        ..removeWhere(
          (scenario) =>
              scenario.fault == AutonomyFaultCode.databaseWriteInterruption,
        );
      var executed = false;

      await expectLater(
        AutonomyFaultCampaignRunner.run(
          scenarios: incomplete,
          execute: (scenario) async {
            executed = true;
            return observations();
          },
        ),
        throwsStateError,
      );
      expect(executed, isFalse);
    },
  );

  test('runner rejects missing invariant evidence from any fault', () async {
    await expectLater(
      AutonomyFaultCampaignRunner.run(
        scenarios: campaign(),
        execute: (scenario) async {
          if (scenario.fault == AutonomyFaultCode.networkTransportFlap) {
            return AutonomyStopShipInvariant.values
                .where(
                  (invariant) =>
                      invariant != AutonomyStopShipInvariant.marginDoubleSpend,
                )
                .map(
                  (invariant) => AutonomyInvariantObservation(
                    invariant: invariant,
                    passed: true,
                  ),
                );
          }
          return observations();
        },
      ),
      throwsStateError,
    );
  });
}
