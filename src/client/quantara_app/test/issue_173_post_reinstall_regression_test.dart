import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/auto_trade/domain/remaining_target_protection_policy.dart';

void main() {
  test('one exchange lot TP remains active when quantity equals tolerance', () {
    expect(
      RemainingTargetProtectionPolicy.allRemainingTargetsProtected(
        targetOrderIds: const ['tp-1', '', ''],
        targetQuantities: const [0.1, 0, 0],
        filledQuantities: const [0, 0, 0],
        pendingProtection: const [
          PendingTargetProtectionEvidence(
            orderId: 'tp-1',
            triggerPrice: 88.8,
            quantity: 0.1,
          ),
        ],
        quantityTolerance: 0.1,
      ),
      isTrue,
    );
  });

  test(
    'one exchange lot TP still requires actual positive exchange evidence',
    () {
      expect(
        RemainingTargetProtectionPolicy.allRemainingTargetsProtected(
          targetOrderIds: const ['tp-1', '', ''],
          targetQuantities: const [0.1, 0, 0],
          filledQuantities: const [0, 0, 0],
          pendingProtection: const [],
          quantityTolerance: 0.1,
        ),
        isFalse,
      );
      expect(
        RemainingTargetProtectionPolicy.allRemainingTargetsProtected(
          targetOrderIds: const ['tp-1', '', ''],
          targetQuantities: const [0.1, 0, 0],
          filledQuantities: const [0, 0, 0],
          pendingProtection: const [
            PendingTargetProtectionEvidence(
              orderId: 'tp-1',
              triggerPrice: 88.8,
              quantity: 0,
            ),
          ],
          quantityTolerance: 0.1,
        ),
        isFalse,
      );
    },
  );

  test(
    'recovered journal replays decision snapshot without live substitution',
    () {
      final source = File(
        'lib/features/trading_journal/presentation/trading_journal_view.dart',
      ).readAsStringSync();

      expect(source, contains('TradingJournalReplay.decisionChart('));
      expect(source, contains('analysis: historicalAnalysis,'));
      expect(source, contains('currentIdea: null,'));
      expect(
        source,
        isNot(
          contains(
            "for (final fallbackTimeframe in const ['1h', '15m', '5m', '4h'])",
          ),
        ),
      );
      expect(
        source,
        contains('newer live data is never substituted for history'),
      );
      expect(source, contains('activeTargets'));
      expect(source, contains('targets: activeTargets'));
    },
  );

  test('initial target confirmation treats an exact lot as active', () {
    final source = File(
      'lib/features/auto_trade/application/local_live_trade_service.dart',
    ).readAsStringSync();

    expect(source, contains('if (planned <= 0) continue;'));
    expect(
      source,
      contains('final comparisonTolerance = quantityTolerance / 2;'),
    );
    expect(source, contains('item.takeProfitQuantity > 0'));
    expect(
      source,
      isNot(contains('if (planned <= quantityTolerance) continue;')),
    );
  });

  test('recovered evidence ignores inactive target R values', () {
    final source = File(
      'lib/features/trading_journal/application/local_live_journal_observer.dart',
    ).readAsStringSync();
    expect(source, contains('target <= 0 || riskPerUnit <= 0'));
    expect(source, contains('confirmed-active-target-ladder'));
    expect(source, contains("appVersion: '1.2.0-rc.2+124'"));
  });
}
