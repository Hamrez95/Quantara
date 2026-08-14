import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/ai_supervisor/domain/supervisor_observability_coverage.dart';
import 'package:quantara_app/features/ai_supervisor/domain/supervisor_system_evidence.dart';

void main() {
  test('covers every non-secret evidence domain', () {
    final observableDomains = SupervisorObservabilityCoverage.entries
        .where((entry) => entry.access == SupervisorCoverageAccess.observable)
        .map((entry) => entry.domain)
        .whereType<SupervisorEvidenceDomain>()
        .toSet();

    expect(observableDomains, SupervisorEvidenceDomain.values.toSet());
  });

  test('keeps credential surfaces explicitly excluded', () {
    final excluded = SupervisorObservabilityCoverage.entries
        .where((entry) => entry.access == SupervisorCoverageAccess.excludedSecret)
        .map((entry) => entry.surface)
        .toSet();

    expect(excluded, contains('credentials.api_keys_and_secrets'));
    expect(excluded, contains('credentials.authorization_and_tokens'));
    expect(
      excluded,
      contains('credentials.signatures_private_keys_and_signing_material'),
    );
    expect(
      excluded,
      contains('credentials.raw_secret_environment_and_stores'),
    );
  });

  test('serializes coverage deterministically', () {
    final first = SupervisorObservabilityCoverage.toJson().toString();
    final second = SupervisorObservabilityCoverage.toJson().toString();

    expect(first, second);
    expect(first, contains('excludedSecret'));
  });
}
