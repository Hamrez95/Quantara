import 'dart:convert';

import 'local_live_observability.dart';

/// Builds a support bundle from non-secret Local Live state.
///
/// The sanitizer is deliberately recursive because exchange responses, audit
/// messages and future diagnostic sections may contain nested maps. Sensitive
/// keys are removed and credential-like fragments inside strings are redacted.
abstract final class LocalLiveDiagnosticBundle {
  static const int schemaVersion = 1;

  static Map<String, Object?> build({
    required DateTime generatedAt,
    required Map<String, Object?> sections,
    Iterable<String> explicitSecretValues = const [],
    Iterable<LocalLiveObservabilityEvent> observabilityEvents = const [],
    int observabilityMaximumEvents =
        LocalLiveObservabilityExport.defaultMaximumEvents,
  }) {
    final boundedEvents = observabilityEvents.toList(growable: false);
    final exportedSections = <String, Object?>{
      ...sections,
      if (boundedEvents.isNotEmpty)
        'localLiveObservability': LocalLiveObservabilityExport.build(
          boundedEvents,
          maximumEvents: observabilityMaximumEvents,
        ),
    };
    final payload = <String, Object?>{
      'schemaVersion': schemaVersion,
      'generatedAt': generatedAt.toUtc().toIso8601String(),
      'product': 'Quantara',
      'scope': 'local-live-support',
      'privacy':
          'User-initiated diagnostic export. API credentials and authorization data are excluded.',
      'sections': exportedSections,
    };
    return sanitizeMap(payload, explicitSecretValues: explicitSecretValues);
  }

  static String encode({
    required DateTime generatedAt,
    required Map<String, Object?> sections,
    Iterable<String> explicitSecretValues = const [],
    Iterable<LocalLiveObservabilityEvent> observabilityEvents = const [],
    int observabilityMaximumEvents =
        LocalLiveObservabilityExport.defaultMaximumEvents,
  }) => const JsonEncoder.withIndent('  ').convert(
    build(
      generatedAt: generatedAt,
      sections: sections,
      explicitSecretValues: explicitSecretValues,
      observabilityEvents: observabilityEvents,
      observabilityMaximumEvents: observabilityMaximumEvents,
    ),
  );

  static Map<String, Object?> sanitizeMap(
    Map<String, Object?> source, {
    Iterable<String> explicitSecretValues = const [],
  }) {
    final secrets = explicitSecretValues
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet();
    final sanitized = _sanitizeValue(source, secrets);
    return sanitized is Map<String, Object?> ? sanitized : const {};
  }

  static Object? _sanitizeValue(Object? value, Set<String> secrets) {
    if (value is Map<Object?, Object?>) {
      final result = <String, Object?>{};
      for (final entry in value.entries) {
        final key = entry.key.toString();
        if (_sensitiveKey(key)) continue;
        result[key] = _sanitizeValue(entry.value, secrets);
      }
      return result;
    }
    if (value is Iterable<Object?>) {
      return value
          .map((item) => _sanitizeValue(item, secrets))
          .toList(growable: false);
    }
    if (value is String) return _sanitizeString(value, secrets);
    if (value is num || value is bool || value == null) return value;
    return _sanitizeString(value.toString(), secrets);
  }

  static bool _sensitiveKey(String key) {
    final normalized = key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    const exact = {
      'secret',
      'authorization',
      'password',
      'credentials',
      'credential',
      'signature',
    };
    if (exact.contains(normalized)) return true;
    const sensitiveSuffixes = {
      'apikey',
      'apisecret',
      'secretkey',
      'password',
      'accesstoken',
      'refreshtoken',
      'sessiontoken',
      'credentials',
      'credential',
      'privatekey',
      'signature',
    };
    return sensitiveSuffixes.any(normalized.endsWith);
  }

  static String _sanitizeString(String input, Set<String> secrets) {
    var result = input;
    for (final secret in secrets) {
      result = result.replaceAll(secret, '[REDACTED]');
    }

    // Redact full authorization schemes before the generic key/value rule so
    // a prefix such as `authorization=Basic` cannot leave the encoded payload
    // behind in a support bundle.
    result = result.replaceAll(
      RegExp(r'bearer\s+[a-z0-9._~+/=-]+', caseSensitive: false),
      'Bearer [REDACTED]',
    );
    result = result.replaceAll(
      RegExp(r'basic\s+[a-z0-9+/=]+', caseSensitive: false),
      'Basic [REDACTED]',
    );
    result = result.replaceAll(
      RegExp(
        r'(api\s*[_-]?\s*key|api\s*[_-]?\s*secret|secret\s*[_-]?\s*key|authorization|password|access\s*[_-]?\s*token|refresh\s*[_-]?\s*token|session\s*[_-]?\s*token|private\s*[_-]?\s*key|request\s*[_-]?\s*signature|signature)\s*[:=]\s*(?:bearer\s+|basic\s+)?[^\s,;]+',
        caseSensitive: false,
      ),
      '[REDACTED_CREDENTIAL]',
    );
    return result;
  }
}
