import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/auto_trade/application/local_live_diagnostic_bundle.dart';

void main() {
  test('prefixed credential and support-session keys never leak', () {
    final encoded = LocalLiveDiagnosticBundle.encode(
      generatedAt: DateTime.utc(2026, 8, 8),
      sections: const {
        'nested': {
          'bitunixApiKey': 'bitunix-key-leak',
          'exchangeApiSecret': 'exchange-secret-leak',
          'supportSessionToken': 'support-token-leak',
          'requestSignature': 'signature-leak',
          'safeSymbol': 'SOLUSDT',
        },
        'messages': [
          'session_token=support-token-in-string',
          'request_signature=signed-string',
          'safe diagnostic',
        ],
      },
    );

    for (final secret in const [
      'bitunix-key-leak',
      'exchange-secret-leak',
      'support-token-leak',
      'signature-leak',
      'support-token-in-string',
      'signed-string',
    ]) {
      expect(encoded, isNot(contains(secret)));
    }
    expect(encoded, contains('SOLUSDT'));
    expect(encoded, contains('safe diagnostic'));
  });
}
