import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/auto_trade/domain/local_live_trade_models.dart';

void main() {
  test(
    'round-trips atomic portfolio budget status through service payload',
    () {
      final status = LocalLiveTradeStatus(
        state: LocalLiveTradeState.running,
        updatedAt: DateTime.utc(2026, 8, 5, 4, 45),
        message: 'running',
        openPositionCount: 1,
        entriesEnabled: true,
        portfolioBudget: LocalLivePortfolioBudgetStatus(
          asOf: DateTime.utc(2026, 8, 5, 4, 45),
          riskLimit: 0.30,
          riskConsumed: 0.075,
          riskAvailable: 0.225,
          openRisk: 0.075,
          pendingRisk: 0,
          ambiguousRisk: 0,
          reservedMargin: 1.25,
          spendableMargin: 26.40,
          accountFresh: true,
          allPositionsProtected: true,
          liveExecutionAllowed: true,
          blockReason: 'none',
        ),
      );

      final restored = LocalLiveTradeStatus.fromJson(status.toJson());

      expect(restored.portfolioBudget, isNotNull);
      expect(restored.portfolioBudget!.riskLimit, 0.30);
      expect(restored.portfolioBudget!.riskAvailable, 0.225);
      expect(restored.portfolioBudget!.openRisk, 0.075);
      expect(restored.portfolioBudget!.reservedMargin, 1.25);
      expect(restored.portfolioBudget!.spendableMargin, 26.40);
      expect(restored.portfolioBudget!.liveExecutionAllowed, isTrue);
      expect(restored.portfolioBudget!.blockReason, 'none');
    },
  );
}
