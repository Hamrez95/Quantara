enum AutonomyFaultDomain {
  marketFeed,
  privateExecution,
  processStorage,
  strategyPolicy,
}

enum AutonomySafetyInvariant {
  noDuplicateLiveOrder,
  noRiskOrMarginDoubleSpend,
  noEntryFromStaleOrAmbiguousTruth,
  noUnprotectedOwnedExposure,
  noWrongSideStopAccepted,
  noStopWidening,
  noPrivilegedAccountMutation,
  noLostOrDoubleCountedFill,
  ambiguousOutcomeRetainsRisk,
}

final class AutonomyFaultObservation {
  const AutonomyFaultObservation({
    required this.scenarioId,
    required this.domain,
    required this.observedAtUtc,
    required this.passedInvariants,
    required this.failedInvariants,
    this.notes,
  });

  final String scenarioId;
  final AutonomyFaultDomain domain;
  final DateTime observedAtUtc;
  final Set<AutonomySafetyInvariant> passedInvariants;
  final Set<AutonomySafetyInvariant> failedInvariants;
  final String? notes;

  bool get hasContradictoryEvidence =>
      passedInvariants.intersection(failedInvariants).isNotEmpty;
}

final class AutonomyFaultCertificationResult {
  const AutonomyFaultCertificationResult({
    required this.certified,
    required this.coveredDomains,
    required this.failedInvariants,
    required this.blockReasons,
  });

  final bool certified;
  final Set<AutonomyFaultDomain> coveredDomains;
  final Set<AutonomySafetyInvariant> failedInvariants;
  final List<String> blockReasons;
}

final class AutonomyFaultCertificationPolicy {
  const AutonomyFaultCertificationPolicy._();

  static const requiredDomains = <AutonomyFaultDomain>{
    AutonomyFaultDomain.marketFeed,
    AutonomyFaultDomain.privateExecution,
    AutonomyFaultDomain.processStorage,
    AutonomyFaultDomain.strategyPolicy,
  };

  static const requiredInvariants = <AutonomySafetyInvariant>{
    AutonomySafetyInvariant.noDuplicateLiveOrder,
    AutonomySafetyInvariant.noRiskOrMarginDoubleSpend,
    AutonomySafetyInvariant.noEntryFromStaleOrAmbiguousTruth,
    AutonomySafetyInvariant.noUnprotectedOwnedExposure,
    AutonomySafetyInvariant.noWrongSideStopAccepted,
    AutonomySafetyInvariant.noStopWidening,
    AutonomySafetyInvariant.noPrivilegedAccountMutation,
    AutonomySafetyInvariant.noLostOrDoubleCountedFill,
    AutonomySafetyInvariant.ambiguousOutcomeRetainsRisk,
  };

  static AutonomyFaultCertificationResult evaluate(
    Iterable<AutonomyFaultObservation> observations,
  ) {
    final items = observations.toList(growable: false);
    final blockReasons = <String>[];
    final coveredDomains = <AutonomyFaultDomain>{};
    final passedInvariants = <AutonomySafetyInvariant>{};
    final failedInvariants = <AutonomySafetyInvariant>{};
    final scenarioIds = <String>{};

    if (items.isEmpty) {
      return const AutonomyFaultCertificationResult(
        certified: false,
        coveredDomains: <AutonomyFaultDomain>{},
        failedInvariants: <AutonomySafetyInvariant>{},
        blockReasons: <String>['faultEvidenceMissing'],
      );
    }

    for (final item in items) {
      final scenarioId = item.scenarioId.trim();
      if (scenarioId.isEmpty) {
        blockReasons.add('scenarioIdentityMissing');
      } else if (!scenarioIds.add(scenarioId)) {
        blockReasons.add('duplicateScenarioIdentity:$scenarioId');
      }
      if (!item.observedAtUtc.isUtc) {
        blockReasons.add('nonUtcObservation:$scenarioId');
      }
      if (item.hasContradictoryEvidence) {
        blockReasons.add('contradictoryInvariantEvidence:$scenarioId');
      }
      coveredDomains.add(item.domain);
      passedInvariants.addAll(item.passedInvariants);
      failedInvariants.addAll(item.failedInvariants);
    }

    final missingDomains = requiredDomains.difference(coveredDomains);
    if (missingDomains.isNotEmpty) {
      blockReasons.add(
        'faultDomainsMissing:${_sortedNames(missingDomains.map((e) => e.name))}',
      );
    }

    final missingInvariants = requiredInvariants.difference(passedInvariants);
    if (missingInvariants.isNotEmpty) {
      blockReasons.add(
        'invariantEvidenceMissing:${_sortedNames(missingInvariants.map((e) => e.name))}',
      );
    }

    if (failedInvariants.isNotEmpty) {
      blockReasons.add(
        'zeroToleranceInvariantFailed:${_sortedNames(failedInvariants.map((e) => e.name))}',
      );
    }

    return AutonomyFaultCertificationResult(
      certified: blockReasons.isEmpty,
      coveredDomains: Set.unmodifiable(coveredDomains),
      failedInvariants: Set.unmodifiable(failedInvariants),
      blockReasons: List.unmodifiable(blockReasons),
    );
  }

  static String _sortedNames(Iterable<String> values) {
    final sorted = values.toList(growable: false)..sort();
    return sorted.join(',');
  }
}
