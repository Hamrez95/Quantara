/// Defense-in-depth text sanitizer for the read-only AI Supervisor boundary.
///
/// Strongly typed DTOs remain the primary allow-list. This helper only protects
/// free-form evidence/review text from accidentally carrying credential-like
/// material into a review bundle.
abstract final class SupervisorSafeText {
  static const String redacted = '[REDACTED]';

  static final RegExp _credentialAssignment = RegExp(
    r'\b(api[_-]?key|api[_-]?secret|authorization|token|password|private[_-]?key|signature)\b\s*[:=]\s*([^\s,;]+)',
    caseSensitive: false,
  );

  static final RegExp _bearerToken = RegExp(
    r'\bbearer\s+[^\s,;]+',
    caseSensitive: false,
  );

  static String sanitize(String value) {
    var sanitized = value.replaceAllMapped(
      _credentialAssignment,
      (match) => '${match.group(1)}=$redacted',
    );
    sanitized = sanitized.replaceAll(_bearerToken, 'Bearer $redacted');
    return sanitized;
  }
}
