import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'broad discovery uses regime playbook portfolio and HTF runtime context',
    () {
      final source = File(
        'lib/features/owner_alpha/data/opportunity_discovery_universe.dart',
      ).readAsStringSync();

      expect(source, contains('RegimePlaybookPortfolioEngine.evaluate'));
      expect(source, contains('higherTimeframeDirection'));
      expect(source, contains('higherTimeframeFresh'));
      expect(source, contains('liquidityVerified: true'));
      expect(source, contains('processingLatency:'));
      expect(source, contains('playbookId:'));
    },
  );

  test('playbook portfolio has no exchange mutation authority', () {
    final source = [
      File(
        'lib/features/owner_alpha/data/regime_playbook_portfolio_engine.dart',
      ).readAsStringSync(),
      File(
        'lib/features/owner_alpha/data/regime_playbook_conflict_resolver.dart',
      ).readAsStringSync(),
    ].join('\n');

    for (final forbidden in const [
      'BitunixApiCredentials',
      'BitunixLocalLiveApiClient',
      'placeMarketEntry',
      'placeOrder',
      'closePositionReduceOnly',
      'cancelEntryOrder',
      'withdraw',
      'transfer',
    ]) {
      expect(source, isNot(contains(forbidden)), reason: forbidden);
    }
  });
}
