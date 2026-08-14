/// Defense-in-depth text sanitizer for the read-only AI Supervisor boundary.
///
/// Strongly typed DTOs remain the primary allow-list. This helper only protects
/// free-form evidence/review text from accidentally carrying credential-like
/// material into a review bundle.
abstract final class SupervisorSafeText {
  static const String redacted = '[REDACTED]';

  static final RegExp _credentialAssignment = RegExp(
    r'\b(api[_-]?key|api[_-]?secret|authorization|token|password|'
    r'private[_-]?key|signature)\b\s*[:=]\s*([^\s,;]+)',
    caseSensitive: false,
  );

  static final RegExp _bearerToken = RegExp(
    r'\bbearer\s+[^\s,;]+',
    caseSensitive: false,
  );

  static String sanitize(String value) {
    // Redact the complete bearer credential before generic key/value handling.
    // Otherwise `Authorization: Bearer secret` could redact only `Bearer` and
    // accidentally leave the credential value behind as free text.
    var sanitized = value.replaceAll(_bearerToken, 'Bearer $redacted');
    sanitized = sanitized.replaceAllMapped(
      _credentialAssignment,
      (match) => '${match.group(1)}=$redacted',
    );
    return sanitized;
  }

  static List<String> sanitizeAll(Iterable<String> values) =>
      values.map(sanitize).toList(growable: false);
}
