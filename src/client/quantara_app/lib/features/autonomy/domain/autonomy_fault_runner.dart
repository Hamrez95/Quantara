import 'dart:collection';

import 'package:flutter/foundation.dart';

import 'autonomy_certification.dart';
import 'autonomy_fault_campaign.dart';

typedef AutonomyFaultScenarioExecutor =
    Future<Iterable<AutonomyInvariantObservation>> Function(
      AutonomyFaultCampaignScenario scenario,
    );

@immutable
final class AutonomyFaultCampaignRunResult {
  AutonomyFaultCampaignRunResult({
    required this.campaign,
    required Iterable<AutonomyCertificationResult> certifications,
  }) : certifications = UnmodifiableListView(
         certifications.toList(growable: false),
       ) {
    if (this.certifications.length != campaign.scenarios.length) {
      throw StateError(
        'Every fault campaign scenario requires exactly one certification result.',
      );
    }
    for (var index = 0; index < campaign.scenarios.length; index++) {
      final expected = campaign.scenarios[index];
      final actual = this.certifications[index].scenario;
      if (actual.version != expected.version ||
          actual.seed != expected.seed ||
          actual.category != expected.category ||
          actual.faultCode != expected.fault.name) {
        throw StateError(
          'Certification result identity must match its deterministic fault scenario.',
        );
      }
    }
  }

  final AutonomyFaultCampaignResult campaign;
  final UnmodifiableListView<AutonomyCertificationResult> certifications;

  bool get stopShip => certifications.any((result) => result.stopShip);

  bool get promotionEligible => campaign.complete && !stopShip;

  List<String> get failedFaultCodes => List.unmodifiable(
    certifications
        .where((result) => result.stopShip)
        .map((result) => result.scenario.faultCode),
  );

  Map<String, Object?> toJson() => {
    'campaign': campaign.toJson(),
    'scenarioCount': certifications.length,
    'stopShip': stopShip,
    'promotionEligible': promotionEligible,
    'failedFaultCodes': failedFaultCodes,
    'certifications': certifications
        .map((result) => result.toJson())
        .toList(growable: false),
  };
}

abstract final class AutonomyFaultCampaignRunner {
  static Future<AutonomyFaultCampaignRunResult> run({
    required Iterable<AutonomyFaultCampaignScenario> scenarios,
    required AutonomyFaultScenarioExecutor execute,
  }) async {
    final campaign = AutonomyFaultCampaignGate.evaluate(scenarios: scenarios);
    final certifications = <AutonomyCertificationResult>[];

    for (final scenario in campaign.scenarios) {
      final observations = await execute(scenario);
      certifications.add(
        AutonomyCertificationGate.evaluate(
          scenario: scenario.toFaultScenario(),
          observations: observations,
        ),
      );
    }

    return AutonomyFaultCampaignRunResult(
      campaign: campaign,
      certifications: certifications,
    );
  }
}
