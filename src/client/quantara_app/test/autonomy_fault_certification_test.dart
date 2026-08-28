import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/auto_trade/domain/autonomy_fault_certification.dart';

void main() {
  final allInvariants = AutonomyFaultCertificationPolicy.requiredInvariants;
  final at = DateTime.utc(2026, 8, 28, 18);

  AutonomyFaultObservation observation(
    String id,
    AutonomyFaultDomain domain, {
    Set<AutonomySafetyInvariant>? passed,
    Set<AutonomySafetyInvariant> failed = const {},
    DateTime? observedAt,
  }) => AutonomyFaultObservation(
    scenarioId: id,
    domain: domain,
    observedAtUtc: observedAt ?? at,
    passedInvariants: passed ?? allInvariants,
    failedInvariants: failed,
  );

  List<AutonomyFaultObservation> completeMatrix() => [
    observation('market-disconnect-storm', AutonomyFaultDomain.marketFeed),
    observation('private-submit-timeout', AutonomyFaultDomain.privateExecution),
    observation(
      'process-death-after-submit',
      AutonomyFaultDomain.processStorage,
    ),
    observation(
      'strategy-quarantined-open',
      AutonomyFaultDomain.strategyPolicy,
    ),
  ];

  test('certifies only complete zero-tolerance evidence', () {
    final result = AutonomyFaultCertificationPolicy.evaluate(completeMatrix());

    expect(result.certified, isTrue);
    expect(result.blockReasons, isEmpty);
    expect(
      result.coveredDomains,
      AutonomyFaultCertificationPolicy.requiredDomains,
    );
    expect(result.failedInvariants, isEmpty);
  });

  test('fails closed when one required fault domain is missing', () {
    final observations = completeMatrix()
      ..removeWhere(
        (item) => item.domain == AutonomyFaultDomain.processStorage,
      );

    final result = AutonomyFaultCertificationPolicy.evaluate(observations);

    expect(result.certified, isFalse);
    expect(
      result.blockReasons.any(
        (reason) => reason.startsWith('faultDomainsMissing:'),
      ),
      isTrue,
    );
  });

  test('fails closed when invariant evidence is incomplete', () {
    final limited = allInvariants.difference({
      AutonomySafetyInvariant.ambiguousOutcomeRetainsRisk,
    });
    final observations = [
      observation(
        'market-disconnect-storm',
        AutonomyFaultDomain.marketFeed,
        passed: limited,
      ),
      observation(
        'private-submit-timeout',
        AutonomyFaultDomain.privateExecution,
        passed: limited,
      ),
      observation(
        'process-death-after-submit',
        AutonomyFaultDomain.processStorage,
        passed: limited,
      ),
      observation(
        'strategy-quarantined-open',
        AutonomyFaultDomain.strategyPolicy,
        passed: limited,
      ),
    ];

    final result = AutonomyFaultCertificationPolicy.evaluate(observations);

    expect(result.certified, isFalse);
    expect(
      result.blockReasons,
      contains(contains('ambiguousOutcomeRetainsRisk')),
    );
  });

  test('one failed zero-tolerance invariant blocks certification', () {
    final observations = completeMatrix();
    observations[1] = observation(
      'private-submit-timeout',
      AutonomyFaultDomain.privateExecution,
      failed: {AutonomySafetyInvariant.noDuplicateLiveOrder},
    );

    final result = AutonomyFaultCertificationPolicy.evaluate(observations);

    expect(result.certified, isFalse);
    expect(
      result.failedInvariants,
      contains(AutonomySafetyInvariant.noDuplicateLiveOrder),
    );
    expect(
      result.blockReasons,
      contains(contains('zeroToleranceInvariantFailed:noDuplicateLiveOrder')),
    );
  });

  test('contradictory pass/fail evidence blocks certification', () {
    final observations = completeMatrix();
    observations[0] = observation(
      'market-disconnect-storm',
      AutonomyFaultDomain.marketFeed,
      failed: {AutonomySafetyInvariant.noEntryFromStaleOrAmbiguousTruth},
    );

    final result = AutonomyFaultCertificationPolicy.evaluate(observations);

    expect(result.certified, isFalse);
    expect(
      result.blockReasons,
      contains('contradictoryInvariantEvidence:market-disconnect-storm'),
    );
  });

  test(
    'duplicate scenario identities cannot inflate certification evidence',
    () {
      final observations = completeMatrix()
        ..add(
          observation(
            'market-disconnect-storm',
            AutonomyFaultDomain.marketFeed,
          ),
        );

      final result = AutonomyFaultCertificationPolicy.evaluate(observations);

      expect(result.certified, isFalse);
      expect(
        result.blockReasons,
        contains('duplicateScenarioIdentity:market-disconnect-storm'),
      );
    },
  );

  test('non-UTC observations fail closed', () {
    final observations = completeMatrix();
    observations[0] = observation(
      'market-disconnect-storm',
      AutonomyFaultDomain.marketFeed,
      observedAt: DateTime(2026, 8, 28, 18),
    );

    final result = AutonomyFaultCertificationPolicy.evaluate(observations);

    expect(result.certified, isFalse);
    expect(
      result.blockReasons,
      contains('nonUtcObservation:market-disconnect-storm'),
    );
  });

  test('empty evidence never certifies', () {
    final result = AutonomyFaultCertificationPolicy.evaluate(const []);

    expect(result.certified, isFalse);
    expect(result.blockReasons, contains('faultEvidenceMissing'));
  });
}
