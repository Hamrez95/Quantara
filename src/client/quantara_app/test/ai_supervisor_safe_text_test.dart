import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/ai_supervisor/domain/supervisor_safe_text.dart';

void main() {
  test('redacts credential-like key/value assignments', () {
    const source =
        'candidate rejected; apiKey:super-secret token=abc123 signature:sig-value';

    final sanitized = SupervisorSafeText.sanitize(source);

    expect(sanitized, isNot(contains('super-secret')));
    expect(sanitized, isNot(contains('abc123')));
    expect(sanitized, isNot(contains('sig-value')));
    expect(sanitized, contains('apiKey=[REDACTED]'));
    expect(sanitized, contains('token=[REDACTED]'));
    expect(sanitized, contains('signature=[REDACTED]'));
  });

  test('redacts bearer credentials embedded in free-form text', () {
    const source = 'authorization failure: Bearer eyJ.private.payload';

    final sanitized = SupervisorSafeText.sanitize(source);

    expect(sanitized, isNot(contains('eyJ.private.payload')));
    expect(sanitized, contains('Bearer [REDACTED]'));
  });

  test('redacts complete authorization bearer header value', () {
    const source = 'Authorization: Bearer top-secret-token';

    final sanitized = SupervisorSafeText.sanitize(source);

    expect(sanitized, isNot(contains('top-secret-token')));
    expect(sanitized, 'Authorization=[REDACTED]');
  });

  test('leaves ordinary diagnostic text unchanged', () {
    const source = 'portfolio slot available; candidate failed risk gate';

    expect(SupervisorSafeText.sanitize(source), source);
  });
}
