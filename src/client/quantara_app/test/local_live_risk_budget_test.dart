import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/auto_trade/domain/local_live_risk_budget.dart';

void main() {
  group('LocalLiveRiskBudget', () {
    test('reserves the daily budget across all remaining position slots', () {
      final snapshot = LocalLiveRiskBudget.calculate(
        const LocalLiveRiskBudgetInput(
          startEquity: 100,
          dailyLossLimitPercent: 1,
          riskPerTradePercent: 1,
          maximumConcurrentPositions: 3,
          openPositionCount: 0,
          openRisks: [],
        ),
      );

      expect(snapshot.dailyBudget, closeTo(1, 0.000001));
      expect(snapshot.openSlots, 3);
      expect(snapshot.nextTradeAllocation, closeTo(1 / 3, 0.000001));
    });

    test('never lets several positions exceed aggregate daily loss budget', () {
      final afterFirst = LocalLiveRiskBudget.calculate(
        const LocalLiveRiskBudgetInput(
          startEquity: 100,
          dailyLossLimitPercent: 1,
          riskPerTradePercent: 1,
          maximumConcurrentPositions: 3,
          openPositionCount: 1,
          openRisks: [
            LocalLiveOpenRisk(
              positionId: 'p1',
              symbol: 'BTCUSDT',
              worstCaseLoss: 1 / 3,
            ),
          ],
        ),
      );

      final afterSecond = LocalLiveRiskBudget.calculate(
        LocalLiveRiskBudgetInput(
          startEquity: 100,
          dailyLossLimitPercent: 1,
          riskPerTradePercent: 1,
          maximumConcurrentPositions: 3,
          openPositionCount: 2,
          openRisks: [
            const LocalLiveOpenRisk(
              positionId: 'p1',
              symbol: 'BTCUSDT',
              worstCaseLoss: 1 / 3,
            ),
            LocalLiveOpenRisk(
              positionId: 'p2',
              symbol: 'ETHUSDT',
              worstCaseLoss: afterFirst.nextTradeAllocation,
            ),
          ],
        ),
      );

      expect(afterFirst.nextTradeAllocation, closeTo(1 / 3, 0.000001));
      expect(afterSecond.nextTradeAllocation, closeTo(1 / 3, 0.000001));
      expect(
        afterSecond.consumedRisk + afterSecond.nextTradeAllocation,
        lessThanOrEqualTo(afterSecond.dailyBudget + 0.000001),
      );
    });

    test('realized losses remain consumed for the rest of the session', () {
      final snapshot = LocalLiveRiskBudget.calculate(
        const LocalLiveRiskBudgetInput(
          startEquity: 100,
          dailyLossLimitPercent: 1,
          riskPerTradePercent: 1,
          maximumConcurrentPositions: 3,
          openPositionCount: 0,
          openRisks: [],
          realizedPnl: -0.4,
        ),
      );

      expect(snapshot.realizedLoss, closeTo(0.4, 0.000001));
      expect(snapshot.remainingRisk, closeTo(0.6, 0.000001));
      expect(snapshot.nextTradeAllocation, closeTo(0.2, 0.000001));
    });

    test('a missing verified stop blocks all new entries', () {
      final snapshot = LocalLiveRiskBudget.calculate(
        const LocalLiveRiskBudgetInput(
          startEquity: 100,
          dailyLossLimitPercent: 1,
          riskPerTradePercent: 0.25,
          maximumConcurrentPositions: 3,
          openPositionCount: 1,
          openRisks: [
            LocalLiveOpenRisk(
              positionId: 'p1',
              symbol: 'BTCUSDT',
              worstCaseLoss: 0.2,
              protectionVerified: false,
            ),
          ],
        ),
      );

      expect(snapshot.protectionVerified, isFalse);
      expect(snapshot.nextTradeAllocation, 0);
      expect(snapshot.canOpenAnotherPosition, isFalse);
    });

    test('pending orders reserve both risk and a position slot', () {
      final snapshot = LocalLiveRiskBudget.calculate(
        const LocalLiveRiskBudgetInput(
          startEquity: 100,
          dailyLossLimitPercent: 1,
          riskPerTradePercent: 1,
          maximumConcurrentPositions: 3,
          openPositionCount: 0,
          openRisks: [],
          pendingReservedRisk: 0.25,
          pendingPositionCount: 1,
        ),
      );

      expect(snapshot.openSlots, 2);
      expect(snapshot.remainingRisk, closeTo(0.75, 0.000001));
      expect(snapshot.nextTradeAllocation, closeTo(0.375, 0.000001));
    });

    test('per-trade preference can be stricter than equal-slot allocation', () {
      final snapshot = LocalLiveRiskBudget.calculate(
        const LocalLiveRiskBudgetInput(
          startEquity: 100,
          dailyLossLimitPercent: 2,
          riskPerTradePercent: 0.25,
          maximumConcurrentPositions: 2,
          openPositionCount: 0,
          openRisks: [],
        ),
      );

      expect(snapshot.nextTradeAllocation, closeTo(0.25, 0.000001));
    });
  });

  group('LocalLiveSafetyPolicy', () {
    test('allows three slots but keeps the canary per-trade ceiling', () {
      expect(
        () => LocalLiveSafetyPolicy.canary.validateUserPreferences(
          riskPerTradePercent: 0.25,
          dailyLossPercent: 1,
          maximumConcurrentPositions: 3,
        ),
        returnsNormally,
      );
    });

    test('rejects authority above immutable canary ceilings', () {
      expect(
        () => LocalLiveSafetyPolicy.canary.validateUserPreferences(
          riskPerTradePercent: 0.30,
          dailyLossPercent: 1,
          maximumConcurrentPositions: 3,
        ),
        throwsFormatException,
      );
      expect(
        () => LocalLiveSafetyPolicy.canary.validateUserPreferences(
          riskPerTradePercent: 0.25,
          dailyLossPercent: 1,
          maximumConcurrentPositions: 4,
        ),
        throwsFormatException,
      );
    });
  });
}
