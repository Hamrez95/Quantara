import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    '5m through 30m market support, persisted controls and exchange-confirmed protected exits stay wired',
    () {
      final root = Directory.current.path;
      String source(String path) => File('$root/$path').readAsStringSync();

      final repository = source(
        'lib/features/owner_alpha/data/bitunix_owner_alpha_repository.dart',
      );
      final ui = source(
        'lib/features/owner_alpha/presentation/owner_alpha_auto_trade.dart',
      );
      final settingsUi = source(
        'lib/features/owner_alpha/presentation/owner_alpha_local_live_tools.dart',
      );
      final service = source(
        'lib/features/auto_trade/application/local_live_trade_service.dart',
      );
      final policy = source(
        'lib/features/owner_alpha/domain/profit_protection_policy.dart',
      );
      final stopPolicy = source(
        'lib/features/auto_trade/domain/profit_lock_stop_policy.dart',
      );
      final executor = source(
        'lib/features/auto_trade/application/profit_lock_promotion_executor.dart',
      );

      expect(
        repository,
        contains("['5m', '15m', '30m', '1h', '4h', '1D']"),
      );
      expect(repository, contains("'5m' => const Duration(minutes: 5)"));
      expect(repository, contains("'30m' => const Duration(minutes: 30)"));
      expect(ui, contains('SharedPreferencesLocalLivePreferencesStore'));
      final compactSettingsUi = settingsUi.replaceAll(RegExp(r'\s+'), '');
      expect(
        compactSettingsUi,
        contains("for(finaltimeframeinconst['5m','15m','1h','4h',])"),
      );
      expect(service, contains('ProfitProtectionPolicy.forIdea'));
      expect(service, contains('ConfirmedTargetFillProgress.reconcile'));
      expect(service, contains('targetOrderIds: managed.targetOrderIds'));
      expect(service, contains('ProfitLockStopPolicy.afterTp1'));
      expect(service, contains('ProfitLockStopPolicy.afterTp2'));
      expect(
        service,
        isNot(contains('position.quantity / managed.initialQuantity')),
      );
      expect(stopPolicy, contains('fill.orderId.trim()'));
      expect(stopPolicy, contains('seenTradeIds.add(tradeId)'));
      expect(
        stopPolicy,
        contains('observedRemainingQuantity is intentionally not used'),
      );
      expect(executor, contains('requestMutation(decision.proposedStop)'));
      expect(executor, contains('Never resend mutation'));
      expect(policy, contains('tp1Fraction: 0.65'));
      expect(policy, contains('tp2Fraction: 0.20'));
      expect(policy, contains('tp3Fraction: 0.15'));
      expect(policy, contains('targetAllocation: allocation'));
    },
  );
}