import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/autonomy/domain/autonomy_certification.dart';
import 'package:quantara_app/features/autonomy/domain/autonomy_fault_campaign.dart';

void main() {
  List<AutonomyFaultCampaignScenario> completeCampaign() {
    final scenarios = <AutonomyFaultCampaignScenario>[];
    for (final fault in AutonomyFaultCode.values) {
      scenarios.add(
        AutonomyFaultCampaignScenario(
          version: 'autonomy-fault-campaign/1.0',
          seed: fault.index,
          fault: fault,
          category: fault.category,
        ),
      );
    }
    return scenarios;
  }

  test('complete campaign covers every required fault and category', () {
    final result = AutonomyFaultCampaignGate.evaluate(
      scenarios: completeCampaign(),
    );

    expect(result.complete, isTrue);
    expect(result.scenarios.length, AutonomyFaultCode.values.length);
    expect(result.countFor(AutonomyFaultCategory.marketPublic), 7);
    expect(result.countFor(AutonomyFaultCategory.privateExecution), 14);
    expect(result.countFor(AutonomyFaultCategory.processStoragePlatform), 12);
    expect(result.countFor(AutonomyFaultCategory.strategyAutonomy), 6);
  });

  test('missing fault cannot produce a complete campaign artifact', () {
    final incomplete = completeCampaign();
    incomplete.removeAt(AutonomyFaultCode.submitTimeoutUnknownOutcome.index);

    expect(
      () => AutonomyFaultCampaignGate.evaluate(scenarios: incomplete),
      throwsStateError,
    );
  });

  test('duplicate fault is rejected even with a different seed', () {
    final duplicate = completeCampaign();
    duplicate.add(
      const AutonomyFaultCampaignScenario(
        version: 'autonomy-fault-campaign/1.0',
        seed: 999,
        fault: AutonomyFaultCode.localClockJump,
        category: AutonomyFaultCategory.marketPublic,
      ),
    );

    expect(
      () => AutonomyFaultCampaignGate.evaluate(scenarios: duplicate),
      throwsStateError,
    );
  });

  test('fault category mismatch fails closed', () {
    const invalid = AutonomyFaultCampaignScenario(
      version: 'autonomy-fault-campaign/1.0',
      seed: 42,
      fault: AutonomyFaultCode.submitTimeoutUnknownOutcome,
      category: AutonomyFaultCategory.marketPublic,
    );

    expect(invalid.validate, throwsStateError);
  });

  test('campaign scenario requires deterministic version and seed metadata', () {
    const invalid = AutonomyFaultCampaignScenario(
      version: ' ',
      seed: -1,
      fault: AutonomyFaultCode.driftBreakerTriggered,
      category: AutonomyFaultCategory.strategyAutonomy,
    );

    expect(invalid.validate, throwsFormatException);
  });

  test('campaign scenario converts to the shared certification scenario', () {
    const scenario = AutonomyFaultCampaignScenario(
      version: 'autonomy-fault-campaign/1.0',
      seed: 7,
      fault: AutonomyFaultCode.privateDisconnectBeforeSubmit,
      category: AutonomyFaultCategory.privateExecution,
    );

    final shared = scenario.toFaultScenario();

    expect(shared.version, scenario.version);
    expect(shared.seed, scenario.seed);
    expect(shared.category, scenario.category);
    expect(shared.faultCode, scenario.fault.name);
  });
}
