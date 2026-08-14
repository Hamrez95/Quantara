import 'supervisor_safe_text.dart';

enum SupervisorEvidenceDomain {
  app,
  backend,
  runtime,
  strategy,
  risk,
  journal,
  build,
  test,
  config,
  persistence,
}

enum SupervisorEvidenceSeverity { info, warning, error, critical }

/// Strongly typed, non-secret evidence visible to the AI Supervisor.
///
/// Values intentionally stay within an allow-listed scalar shape. Unknown
/// application objects, headers, credential stores and environment maps cannot
/// be attached to this contract.
final class SupervisorSystemEvidence {
  SupervisorSystemEvidence({
    required this.evidenceId,
    required this.domain,
    required this.kind,
    required this.observedAtUtc,
    required this.summary,
    this.severity = SupervisorEvidenceSeverity.info,
    this.component,
    this.version,
    this.correlationId,
    Map<String, String> attributes = const {},
  }) : attributes = Map.unmodifiable(
         attributes.map(
           (key, value) => MapEntry(
             SupervisorSafeText.sanitize(key),
             SupervisorSafeText.sanitize(value),
           ),
         ),
       );

  static const String schemaVersion = '1';

  final String evidenceId;
  final SupervisorEvidenceDomain domain;
  final String kind;
  final DateTime observedAtUtc;
  final String summary;
  final SupervisorEvidenceSeverity severity;
  final String? component;
  final String? version;
  final String? correlationId;
  final Map<String, String> attributes;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'evidenceId': SupervisorSafeText.sanitize(evidenceId),
    'domain': domain.name,
    'kind': SupervisorSafeText.sanitize(kind),
    'observedAtUtc': observedAtUtc.toUtc().toIso8601String(),
    'summary': SupervisorSafeText.sanitize(summary),
    'severity': severity.name,
    if (component != null)
      'component': SupervisorSafeText.sanitize(component!),
    if (version != null) 'version': SupervisorSafeText.sanitize(version!),
    if (correlationId != null)
      'correlationId': SupervisorSafeText.sanitize(correlationId!),
    'attributes': attributes,
  };
}
