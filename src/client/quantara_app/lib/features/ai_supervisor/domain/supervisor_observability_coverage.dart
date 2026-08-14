import 'supervisor_system_evidence.dart';

enum SupervisorCoverageAccess { observable, excludedSecret }

final class SupervisorCoverageEntry {
  const SupervisorCoverageEntry({
    required this.surface,
    required this.access,
    required this.reason,
    this.domain,
  });

  final String surface;
  final SupervisorCoverageAccess access;
  final String reason;
  final SupervisorEvidenceDomain? domain;

  Map<String, Object?> toJson() => <String, Object?>{
    'surface': surface,
    'access': access.name,
    'reason': reason,
    if (domain != null) 'domain': domain!.name,
  };
}

/// Documents the trust boundary for system-wide Supervisor observation.
///
/// This list is intentionally explicit: adding a new application surface does
/// not make it observable automatically. Secret-bearing stores remain outside
/// the evidence graph even when adjacent runtime/config state is observable.
abstract final class SupervisorObservabilityCoverage {
  static const String schemaVersion = '1';

  static const List<SupervisorCoverageEntry> entries = <SupervisorCoverageEntry>[
    SupervisorCoverageEntry(
      surface: 'client.app_state',
      access: SupervisorCoverageAccess.observable,
      reason: 'Non-secret application state and feature health.',
      domain: SupervisorEvidenceDomain.app,
    ),
    SupervisorCoverageEntry(
      surface: 'backend.health',
      access: SupervisorCoverageAccess.observable,
      reason: 'Non-secret backend health, version and diagnostic evidence.',
      domain: SupervisorEvidenceDomain.backend,
    ),
    SupervisorCoverageEntry(
      surface: 'runtime.lifecycle',
      access: SupervisorCoverageAccess.observable,
      reason: 'Scanner, reconciliation and lifecycle evidence without credentials.',
      domain: SupervisorEvidenceDomain.runtime,
    ),
    SupervisorCoverageEntry(
      surface: 'strategy.definition_and_scorecard',
      access: SupervisorCoverageAccess.observable,
      reason: 'Strategy/version/configuration and outcome evidence.',
      domain: SupervisorEvidenceDomain.strategy,
    ),
    SupervisorCoverageEntry(
      surface: 'risk.non_secret_state',
      access: SupervisorCoverageAccess.observable,
      reason: 'Risk limits, consumption and deterministic gate outcomes.',
      domain: SupervisorEvidenceDomain.risk,
    ),
    SupervisorCoverageEntry(
      surface: 'journal.statistics_and_linkage',
      access: SupervisorCoverageAccess.observable,
      reason: 'Trade lifecycle linkage and non-secret performance statistics.',
      domain: SupervisorEvidenceDomain.journal,
    ),
    SupervisorCoverageEntry(
      surface: 'build_and_ci',
      access: SupervisorCoverageAccess.observable,
      reason: 'Build version, commit, test and CI evidence.',
      domain: SupervisorEvidenceDomain.build,
    ),
    SupervisorCoverageEntry(
      surface: 'test.results',
      access: SupervisorCoverageAccess.observable,
      reason: 'Deterministic validation evidence and regressions.',
      domain: SupervisorEvidenceDomain.test,
    ),
    SupervisorCoverageEntry(
      surface: 'config.non_secret',
      access: SupervisorCoverageAccess.observable,
      reason: 'Allow-listed non-secret effective configuration.',
      domain: SupervisorEvidenceDomain.config,
    ),
    SupervisorCoverageEntry(
      surface: 'persistence.health',
      access: SupervisorCoverageAccess.observable,
      reason: 'Schema/migration/storage health without raw credential stores.',
      domain: SupervisorEvidenceDomain.persistence,
    ),
    SupervisorCoverageEntry(
      surface: 'credentials.api_keys_and_secrets',
      access: SupervisorCoverageAccess.excludedSecret,
      reason: 'Credentials are structurally outside Supervisor evidence.',
    ),
    SupervisorCoverageEntry(
      surface: 'credentials.authorization_and_tokens',
      access: SupervisorCoverageAccess.excludedSecret,
      reason: 'Authorization headers and access/refresh tokens are excluded.',
    ),
    SupervisorCoverageEntry(
      surface: 'credentials.signatures_private_keys_and_signing_material',
      access: SupervisorCoverageAccess.excludedSecret,
      reason: 'Request signatures, private keys and signing material are excluded.',
    ),
    SupervisorCoverageEntry(
      surface: 'credentials.raw_secret_environment_and_stores',
      access: SupervisorCoverageAccess.excludedSecret,
      reason: 'Secret environment values and raw credential stores are excluded.',
    ),
  ];

  static Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'entries': entries.map((entry) => entry.toJson()).toList(growable: false),
  };
}
