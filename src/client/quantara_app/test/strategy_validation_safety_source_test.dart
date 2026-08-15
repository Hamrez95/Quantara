import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/owner_alpha/domain/regime_playbook_models.dart';

void main() {
  test('validation and promotion code has no exchange or live-order authority', () {
    final files = <File>[
      File('lib/features/strategy_lab/data/strategy_validation_engine.dart'),
      File(
        'lib/features/strategy_lab/data/strategy_validation_stress_engine.dart',
      ),
      File(
        'lib/features/strategy_lab/data/strategy_promotion_packet_builder.dart',
      ),
      File('lib/features/strategy_lab/domain/strategy_validation_models.dart'),
      File('lib/features/strategy_lab/domain/strategy_promotion_models.dart'),
      File(
        'lib/features/strategy_lab/domain/strategy_validation_stage_policy.dart',
      ),
    ];
    final source = files.map((file) => file.readAsStringSync()).join('\n');

    for (final forbidden in [
      'BitunixLocalLiveApiClient',
      'placeMarketEntry',
      'placeOrder',
      'withdraw',
      'transfer',
      'updateLeverage',
      'setMarginMode',
      'portfolioGuard.reserve',
    ]) {
      expect(source, isNot(contains(forbidden)), reason: forbidden);
    }
  });

  test('each regime playbook can be rolled back independently', () {
    const flags = RegimePlaybookFeatureFlags(
      trendPullbackContinuation: false,
      rangeEdgeSweepReclaim: true,
      breakoutAcceptanceRetest: false,
      failedBreakoutReversal: true,
      momentumExpansionScalp: false,
    );

    expect(flags.enabled(RegimePlaybookId.trendPullbackContinuation), isFalse);
    expect(flags.enabled(RegimePlaybookId.rangeEdgeSweepReclaim), isTrue);
    expect(flags.enabled(RegimePlaybookId.breakoutAcceptanceRetest), isFalse);
    expect(flags.enabled(RegimePlaybookId.failedBreakoutReversal), isTrue);
    expect(flags.enabled(RegimePlaybookId.momentumExpansionScalp), isFalse);
  });
}
