import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/auto_trade/application/local_live_diagnostic_bundle.dart';

void main() {
  test(
    'diagnostic bundle recursively strips credentials and secret values',
    () {
      const explicitSecret = 'super-secret-value';
      final encoded = LocalLiveDiagnosticBundle.encode(
        generatedAt: DateTime.utc(2026, 8, 6),
        explicitSecretValues: const [explicitSecret],
        sections: const {
          'configuration': {
            'apiKey': 'key-value',
            'secretKey': explicitSecret,
            'nested': {
              'Authorization': 'Bearer token-value',
              'safe': 'BTCUSDT',
            },
          },
          'audit': [
            'authorization=Basic dXNlcjpwYXNz',
            'API key: visible-key',
            'normal event',
          ],
        },
      );

      expect(encoded, isNot(contains('key-value')));
      expect(encoded, isNot(contains(explicitSecret)));
      expect(encoded, isNot(contains('token-value')));
      expect(encoded, isNot(contains('visible-key')));
      expect(encoded, isNot(contains('dXNlcjpwYXNz')));
      expect(encoded, isNot(contains('secretKey')));
      expect(encoded, contains('BTCUSDT'));
      expect(encoded, contains('normal event'));
    },
  );

  test('diagnostic output remains valid structured JSON', () {
    final encoded = LocalLiveDiagnosticBundle.encode(
      generatedAt: DateTime.utc(2026, 8, 6),
      sections: const {
        'status': {'state': 'running', 'managedPositionCount': 2},
      },
    );
    final decoded = jsonDecode(encoded) as Map<String, Object?>;
    expect(decoded['schemaVersion'], LocalLiveDiagnosticBundle.schemaVersion);
    expect(decoded['scope'], 'local-live-support');
    expect(decoded['sections'], isA<Map<String, Object?>>());
  });
}
