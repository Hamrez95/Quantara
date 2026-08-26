import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/app_update/presentation/profile_app_update_card.dart';

void main() {
  test('requires stable and canary HTTPS manifest endpoints', () {
    const missing = AppUpdateProfileConfiguration(
      stableManifestUrl: '',
      canaryManifestUrl: 'https://updates.example.com/canary.json',
    );
    const insecure = AppUpdateProfileConfiguration(
      stableManifestUrl: 'http://updates.example.com/stable.json',
      canaryManifestUrl: 'https://updates.example.com/canary.json',
    );
    const configured = AppUpdateProfileConfiguration(
      stableManifestUrl: 'https://updates.example.com/stable.json',
      canaryManifestUrl: 'https://updates.example.com/canary.json',
    );

    expect(missing.isConfigured, isFalse);
    expect(insecure.isConfigured, isFalse);
    expect(configured.isConfigured, isTrue);
  });

  test('rejects credential-bearing and malformed internal endpoints', () {
    const credentials = AppUpdateProfileConfiguration(
      stableManifestUrl: 'https://updates.example.com/stable.json',
      canaryManifestUrl: 'https://updates.example.com/canary.json',
      internalManifestUrl: 'https://user:pass@updates.example.com/internal.json',
    );
    const valid = AppUpdateProfileConfiguration(
      stableManifestUrl: 'https://updates.example.com/stable.json',
      canaryManifestUrl: 'https://updates.example.com/canary.json',
      internalManifestUrl: 'https://updates.example.com/internal.json',
    );

    expect(credentials.internalEnabled, isFalse);
    expect(valid.internalEnabled, isTrue);
  });
}
