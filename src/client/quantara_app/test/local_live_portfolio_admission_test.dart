import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/auto_trade/domain/auto_trade_models.dart';
import 'package:quantara_app/features/auto_trade/domain/local_live_portfolio_admission.dart';
import 'package:quantara_app/features/owner_alpha/domain/owner_alpha_models.dart';

void main() {
  test('allows a new slot after a runner remains below the configured cap', () {
    expect(
      LocalLivePortfolioAdmission.hasExecutionSlot(
        configuredMaximum: 3,
        managedPositionCount: 1,
        exchangePositionCount: 1,
      ),
      isTrue,
    );
    expect(
      LocalLivePortfolioAdmission.hasExecutionSlot(
        configuredMaximum: 3,
        managedPositionCount: 3,
        exchangePositionCount: 3,
      ),
      isFalse,
    );
  });

  test('position-count mismatch never creates an execution slot', () {
    expect(
      LocalLivePortfolioAdmission.hasExecutionSlot(
        configuredMaximum: 3,
        managedPositionCount: 1,
        exchangePositionCount: 2,
      ),
      isFalse,
    );
  });

  test('account truth preserves isolated protection and freshness gates', () {
    final now = DateTime.utc(2026, 8, 5, 0, 0);
    final account = AutoTradeAccountSnapshot(
      marginCoin: 'USDT',
      available: 80,
      frozen: 0,
      positionMargin: 20,
      crossUnrealizedPnl: 0,
      isolatedUnrealizedPnl: 2,
      positionMode: 'HEDGE',
      positions: const [
        AutoTradePosition(
          positionId: 'p1',
          symbol: 'BTCUSDT',
          quantity: 0.001,
          side: 'LONG',
          marginMode: 'ISOLATED',
          positionMode: 'HEDGE',
          leverage: 3,
          margin: 20,
          unrealizedPnl: 2,
          liquidationPrice: 1000,
          averageOpenPrice: 60000,
        ),
      ],
      orders: const [],
      syncedAt: now.subtract(const Duration(seconds: 20)),
    );

    final truth = LocalLivePortfolioAdmission.accountTruth(
      account: account,
      observedAt: now,
      allOpenPositionsProtected: true,
    );

    expect(truth.fresh, isTrue);
    expect(truth.marginMode, 'isolated');
    expect(truth.allOpenPositionsProtected, isTrue);
    expect(truth.safetyBuffer, 12);
    expect(truth.feeReserve, closeTo(0.102, 1e-9));
  });

  test('candidate maps setup identity, direction and asset group deterministically', () {
    final idea = TradeIdea(
      symbol: 'ETHUSDT',
      timeframe: '1h',
      direction: TradeDirection.short,
      confidencePercent: 72,
      entryLower: 3000,
      entryUpper: 3010,
      stopLoss: 3050,
      targets: const [2900, 2850, 2800],
      riskReward: 1.8,
      maximumLoss: 2,
      positionSize: 0.02,
      notionalValue: 60,
      recommendedLeverage: 3,
      maximumSafeLeverage: 5,
      requiredMargin: 20,
      estimatedRoundTripCosts: 0.1,
      setupId: 'eth-1h-short-1',
      candleClosedAt: DateTime.utc(2026, 8, 5),
      summary: 'test',
      invalidation: 'test',
      reasons: const ['test'],
    );

    final candidate = LocalLivePortfolioAdmission.candidate(
      idea: idea,
      plannedQuantity: 0.02,
      entryPrice: 3000,
      stopPrice: 3050,
      requiredMargin: 20,
      leverage: 3,
      minimumQuantity: 0.001,
      minimumNotional: 5,
    );

    expect(candidate.reservationId, 'local-live:eth-1h-short-1');
    expect(candidate.candidateId, 'eth-1h-short-1');
    expect(candidate.side.name, 'short');
    expect(candidate.assetGroup, 'crypto-major');
  });
}
