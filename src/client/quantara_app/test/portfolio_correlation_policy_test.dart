import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/portfolio_risk/domain/portfolio_correlation_policy.dart';
import 'package:quantara_app/features/portfolio_risk/domain/portfolio_risk_models.dart';

void main() {
  final now = DateTime.utc(2026, 8, 17, 8);
  final day = TradingDayId.start(now: now, timezoneOffsetMinutes: 0);

  PortfolioRiskLedger ledgerWith(List<PositionRiskReservation> reservations) =>
      PortfolioRiskLedger(
        schemaVersion: 1,
        revision: 1,
        tradingDay: day,
        dailyRiskLimit: 10,
        realizedLoss: 0,
        realizedProfit: 0,
        reservations: reservations,
        processedEventIds: const {},
      );

  PositionRiskReservation openRisk(
    String id, {
    required String symbol,
    required String assetGroup,
    required double risk,
  }) => PositionRiskReservation(
    reservationId: 'reservation-$id',
    journalTradeId: 'trade-$id',
    candidateId: 'candidate-$id',
    symbol: symbol,
    assetGroup: assetGroup,
    side: PortfolioSide.long,
    strategy: 'test',
    entryOrderId: 'order-$id',
    positionId: 'position-$id',
    plannedQuantity: 1,
    filledQuantity: 1,
    entryPrice: 100,
    currentExchangeConfirmedStop: 99,
    contractMultiplier: 1,
    estimatedEntryFee: 0,
    estimatedExitFee: 0,
    slippageReserve: 0,
    fundingReserve: 0,
    maximumLoss: risk,
    reservedMargin: 1,
    createdAt: now,
    tradingDayId: day.value,
    lifecycle: PortfolioReservationLifecycle.open,
    verification: PortfolioVerificationState.exchangeConfirmed,
    revision: 1,
  );

  PortfolioEntryCandidate candidate(
    String id, {
    required String symbol,
    required String assetGroup,
  }) => PortfolioEntryCandidate(
    reservationId: 'new-reservation-$id',
    journalTradeId: 'new-trade-$id',
    candidateId: 'new-candidate-$id',
    symbol: symbol,
    assetGroup: assetGroup,
    side: PortfolioSide.long,
    strategy: 'test',
    plannedQuantity: 1,
    entryPrice: 100,
    stopPrice: 99,
    contractMultiplier: 1,
    entryFeeRate: 0,
    exitFeeRate: 0,
    slippageRate: 0,
    fundingReserve: 0,
    requiredMargin: 1,
    leverage: 10,
    minimumQuantity: 0.001,
    minimumNotional: 1,
  );

  PortfolioEntryDecision allowed(double risk) => PortfolioEntryDecision(
    allowed: true,
    liveExecutionAllowed: false,
    reason: PortfolioEntryBlockReason.none,
    maximumLoss: risk,
    requiredMargin: 1,
    availableRiskBefore: 10,
    availableRiskAfter: 10 - risk,
    availableMarginAfter: 99,
  );

  test('correlated symbols share one hard risk bucket', () {
    const policy = PortfolioCorrelationPolicy(
      maximumBucketRiskFraction: 0.6,
      bucketBySymbol: {
        'BTCUSDT': 'large-cap-beta',
        'ETHUSDT': 'large-cap-beta',
      },
    );
    final ledger = ledgerWith([
      openRisk('btc', symbol: 'BTCUSDT', assetGroup: 'crypto', risk: 4),
    ]);

    final decision = policy.evaluate(
      ledger: ledger,
      candidate: candidate('eth', symbol: 'ETHUSDT', assetGroup: 'crypto'),
      baseDecision: allowed(3),
    );

    expect(decision.allowed, isFalse);
    expect(decision.reason, PortfolioCorrelationReason.correlationBucketLimit);
    expect(decision.bucket, 'large-cap-beta');
    expect(decision.bucketRiskBefore, 4);
    expect(decision.bucketRiskAfter, 7);
    expect(decision.bucketRiskLimit, 6);
  });

  test('independent bucket can use capacity left by another bucket', () {
    const policy = PortfolioCorrelationPolicy(
      maximumBucketRiskFraction: 0.6,
      bucketBySymbol: {
        'BTCUSDT': 'large-cap-beta',
        'SOLUSDT': 'solana-ecosystem',
      },
    );
    final ledger = ledgerWith([
      openRisk('btc', symbol: 'BTCUSDT', assetGroup: 'crypto', risk: 5),
    ]);

    final decision = policy.evaluate(
      ledger: ledger,
      candidate: candidate('sol', symbol: 'SOLUSDT', assetGroup: 'crypto'),
      baseDecision: allowed(3),
    );

    expect(decision.allowed, isTrue);
    expect(decision.bucket, 'solana-ecosystem');
    expect(decision.bucketRiskBefore, 0);
    expect(decision.bucketRiskAfter, 3);
  });

  test('unknown symbols fall back to a conservative asset-group bucket', () {
    const policy = PortfolioCorrelationPolicy(maximumBucketRiskFraction: 0.5);
    final ledger = ledgerWith([
      openRisk('a', symbol: 'AAAUSDT', assetGroup: 'crypto', risk: 3),
    ]);

    final decision = policy.evaluate(
      ledger: ledger,
      candidate: candidate('b', symbol: 'BBBUSDT', assetGroup: 'crypto'),
      baseDecision: allowed(2.1),
    );

    expect(decision.allowed, isFalse);
    expect(decision.bucket, 'asset:crypto');
    expect(decision.reason, PortfolioCorrelationReason.correlationBucketLimit);
  });

  test('risk exactly on the bucket ceiling is allowed', () {
    const policy = PortfolioCorrelationPolicy(
      maximumBucketRiskFraction: 0.5,
      bucketBySymbol: {
        'BTCUSDT': 'large-cap-beta',
        'ETHUSDT': 'large-cap-beta',
      },
    );
    final ledger = ledgerWith([
      openRisk('btc', symbol: 'BTCUSDT', assetGroup: 'crypto', risk: 3),
    ]);

    final decision = policy.evaluate(
      ledger: ledger,
      candidate: candidate('eth', symbol: 'ETHUSDT', assetGroup: 'crypto'),
      baseDecision: allowed(2),
    );

    expect(decision.allowed, isTrue);
    expect(decision.bucketRiskAfter, 5);
  });

  test('correlation policy never overrides a rejected base decision', () {
    const policy = PortfolioCorrelationPolicy();
    final blocked = PortfolioEntryDecision(
      allowed: false,
      liveExecutionAllowed: false,
      reason: PortfolioEntryBlockReason.riskBudgetInsufficient,
      maximumLoss: 3,
      requiredMargin: 1,
      availableRiskBefore: 2,
      availableRiskAfter: 2,
      availableMarginAfter: 99,
    );

    final decision = policy.evaluate(
      ledger: ledgerWith(const []),
      candidate: candidate('btc', symbol: 'BTCUSDT', assetGroup: 'crypto'),
      baseDecision: blocked,
    );

    expect(decision.allowed, isFalse);
    expect(decision.reason, PortfolioCorrelationReason.baseDecisionRejected);
  });
}
