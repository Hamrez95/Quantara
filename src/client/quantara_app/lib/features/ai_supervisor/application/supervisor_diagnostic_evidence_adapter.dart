import 'dart:convert';

import '../../auto_trade/application/local_live_diagnostic_bundle.dart';
import '../domain/supervisor_system_evidence.dart';

/// Converts the existing secret-free Local Live diagnostic bundle into the
/// system-wide Supervisor evidence graph.
///
/// Only explicitly registered diagnostic sections cross this boundary. A new
/// top-level section added elsewhere in Quantara is therefore not exposed to AI
/// review until this registry is deliberately updated and reviewed.
abstract final class SupervisorDiagnosticEvidenceAdapter {
  static const Map<String, SupervisorEvidenceDomain> _sectionDomains = {
    'configuration': SupervisorEvidenceDomain.config,
    'localLiveStatus': SupervisorEvidenceDomain.runtime,
    'privateAccountReconciliation': SupervisorEvidenceDomain.runtime,
    'accountSnapshot': SupervisorEvidenceDomain.risk,
    'analysisRuntime': SupervisorEvidenceDomain.strategy,
    'auditEvents': SupervisorEvidenceDomain.runtime,
    'tradingJournal': SupervisorEvidenceDomain.journal,
    'tradeEvidencePackets': SupervisorEvidenceDomain.journal,
    'supportSessionFoundation': SupervisorEvidenceDomain.app,
    'persistedLocalServiceState': SupervisorEvidenceDomain.persistence,
  };

  static Set<String> get observableSections =>
      Set<String>.unmodifiable(_sectionDomains.keys);

  static List<SupervisorSystemEvidence> fromDiagnosticBundle({
    required String bundleId,
    required DateTime observedAtUtc,
    required Map<String, Object?> diagnosticBundle,
    String? correlationId,
  }) {
    final sanitized = LocalLiveDiagnosticBundle.sanitizeMap(diagnosticBundle);
    final sections = sanitized['sections'];
    if (sections is! Map<Object?, Object?>) return const [];

    final evidence = <SupervisorSystemEvidence>[];
    for (final registration in _sectionDomains.entries) {
      if (!sections.containsKey(registration.key)) continue;
      final value = sections[registration.key];
      evidence.add(
        SupervisorSystemEvidence(
          evidenceId: 'diagnostic:$bundleId:${registration.key}',
          domain: registration.value,
          kind: 'diagnosticSection',
          observedAtUtc: observedAtUtc,
          summary: 'Sanitized ${registration.key} diagnostic evidence.',
          component: 'local_live_diagnostics',
          correlationId: correlationId ?? bundleId,
          attributes: {
            'section': registration.key,
            'payload': jsonEncode(_canonicalize(value)),
          },
        ),
      );
    }
    return List.unmodifiable(evidence);
  }

  static Object? _canonicalize(Object? value) {
    if (value is Map<Object?, Object?>) {
      final keys = value.keys.map((key) => key.toString()).toList()..sort();
      return <String, Object?>{
        for (final key in keys) key: _canonicalize(value[key]),
      };
    }
    if (value is Iterable<Object?>) {
      return value.map(_canonicalize).toList(growable: false);
    }
    if (value is num || value is bool || value is String || value == null) {
      return value;
    }
    return value.toString();
  }
}
