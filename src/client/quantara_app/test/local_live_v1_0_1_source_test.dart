import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('5m, persisted controls and regime-aware protected exits stay wired', () {
    final root = Directory.current.path;
    String source(String path) => File('$root/$path').readAsStringSync();

    final repository = source(
      'lib/features/owner_alpha/data/bitunix_owner_alpha_repository.dart',
    );
    final ui = source(
      'lib/features/owner_alpha/presentation/owner_alpha_auto_trade.dart',
    );
    final service = source(
      'lib/features/auto_trade/application/local_live_trade_service.dart',
    );
    final policy = source(
      'lib/features/owner_alpha/domain/profit_protection_policy.dart',
    );

    expect(repository, contains("['5m', '15m', '1h', '4h', '1D']"));
    expect(repository, contains("'5m' => const Duration(minutes: 5)"));
    expect(ui, contains('SharedPreferencesLocalLivePreferencesStore'));
    expect(ui, contains("['5m', '15m', '1h', '4h']"));
    expect(service, contains('ProfitProtectionPolicy.forIdea'));
    expect(service, contains('managed.targetFractions.first'));
    expect(service, contains('managed.targetFractions.last'));
    expect(policy, contains('[0.55, 0.30, 0.15]'));
    expect(policy, contains('[0.40, 0.25, 0.35]'));
    expect(policy, contains('[0.40, 0.30, 0.30]'));
  });
}
