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
        capitalGuardian: LocalLiveCapitalGuardianStatus(
          currentEquity: 1000,
          peakEquity: 1060,
          drawdownFraction: 0.0566037736,
          drawdownTier: 'soft',
          riskMultiplier: 0.5,
          openRisk: 0.075,
          remainingRisk: 0.225,
          asOf: DateTime.utc(2026, 8, 5, 4, 45),
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
      expect(restored.capitalGuardian, isNotNull);
      expect(restored.capitalGuardian!.currentEquity, 1000);
      expect(restored.capitalGuardian!.peakEquity, 1060);
      expect(restored.capitalGuardian!.drawdownTier, 'soft');
      expect(restored.capitalGuardian!.riskMultiplier, 0.5);
      expect(restored.capitalGuardian!.openRisk, 0.075);
      expect(restored.capitalGuardian!.remainingRisk, 0.225);
    },
  );
}
