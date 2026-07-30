import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/auto_trade/application/auto_trade_shadow_planner.dart';
import 'package:quantara_app/features/auto_trade/domain/auto_trade_execution_models.dart';
import 'package:quantara_app/features/auto_trade/domain/auto_trade_models.dart';

void main() {
  final now = DateTime.utc(2026, 7, 30, 12);

  test('shadow plan sizes from live equity and remains below risk budget', () {
    final result = AutoTradeShadowPlanner.create(
      candidate: _candidate(now),
      context: _context(now),
    );

    expect(result.accepted, isTrue);
    final plan = result.plan!;
    expect(plan.status, AutoTradePlanStatus.shadow);
    expect(plan.riskBudget, closeTo(8, 0.0001));
    expect(plan.riskPerUnit, closeTo(2.2, 0.0001));
    expect(plan.quantity, closeTo(3.636, 0.0001));
    expect(plan.maximumLoss, lessThanOrEqualTo(plan.riskBudget));
    expect(plan.requiredMargin, closeTo(plan.notional / 10, 0.0001));
    expect(plan.isolatedMargin, isTrue);
  });

  test('leverage changes required margin but not quantity, notional or loss', () {
    final low = AutoTradeShadowPlanner.create(
      candidate: _candidate(now),
      context: _context(now, leverage: 5),
    ).plan!;
    final high = AutoTradeShadowPlanner.create(
      candidate: _candidate(now),
      context: _context(now, leverage: 50),
    ).plan!;

    expect(high.quantity, closeTo(low.quantity, 0.0001));
    expect(high.notional, closeTo(low.notional, 0.0001));
    expect(high.maximumLoss, closeTo(low.maximumLoss, 0.0001));
    expect(high.requiredMargin, closeTo(low.requiredMargin / 10, 0.0001));
  });

  test('manual mode creates an approval-only plan with stable client id', () {
    final first = AutoTradeShadowPlanner.create(
      candidate: _candidate(now),
      context: _context(now, mode: AutoTradeOperatingMode.manualApproval),
    ).plan!;
    final second = AutoTradeShadowPlanner.create(
      candidate: _candidate(now),
      context: _context(now, mode: AutoTradeOperatingMode.manualApproval),
    ).plan!;

    expect(first.status, AutoTradePlanStatus.awaitingApproval);
    expect(first.requiresManualApproval, isTrue);
    expect(first.clientId, second.clientId);
  });

  test('stale, conflicting and non-primary signals fail closed', () {
    final stale = _candidate(
      now,
      primarySetup: false,
      timeframeConflict: true,
      createdAt: now.subtract(const Duration(hours: 1)),
      marketDataAt: now.subtract(const Duration(hours: 1)),
    );
    final result = AutoTradeShadowPlanner.create(
      candidate: stale,
      context: _context(now),
    );

    expect(result.accepted, isFalse);
    expect(
      result.rejections,
      containsAll({
        AutoTradeRejectionCode.staleSignal,
        AutoTradeRejectionCode.notPrimarySetup,
        AutoTradeRejectionCode.timeframeConflict,
      }),
    );
  });

  test('existing position or pending entry blocks duplicate exposure', () {
    final result = AutoTradeShadowPlanner.create(
      candidate: _candidate(now),
      context: _context(
        now,
        positions: [
          const AutoTradePosition(
            positionId: 'p-1',
            symbol: 'BTCUSDT',
            quantity: 0.01,
            side: 'LONG',
            marginMode: 'ISOLATION',
            positionMode: 'ONE_WAY',
            leverage: 10,
            margin: 20,
            unrealizedPnl: 0,
            liquidationPrice: 70,
            averageOpenPrice: 100,
          ),
        ],
      ),
    );

    expect(result.accepted, isFalse);
    expect(
      result.rejections,
      contains(AutoTradeRejectionCode.existingExposure),
    );
  });

  test('read-only mode never creates an executable order plan', () {
    final result = AutoTradeShadowPlanner.create(
      candidate: _candidate(now),
      context: _context(now, mode: AutoTradeOperatingMode.readOnly),
    );

    expect(result.accepted, isFalse);
    expect(
      result.rejections,
      contains(AutoTradeRejectionCode.unsupportedMode),
    );
  });

  test('insufficient available margin rejects rather than reducing safety', () {
    final result = AutoTradeShadowPlanner.create(
      candidate: _candidate(now),
      context: _context(now, available: 5),
    );

    expect(result.accepted, isFalse);
    expect(
      result.rejections,
      contains(AutoTradeRejectionCode.insufficientAvailableMargin),
    );
  });
}

AutoTradeSignalCandidate _candidate(
  DateTime now, {
  bool primarySetup = true,
  bool timeframeConflict = false,
  DateTime? createdAt,
  DateTime? marketDataAt,
}) => AutoTradeSignalCandidate(
  setupId: 'BTCUSDT|1h|long|abc',
  symbol: 'BTCUSDT',
  timeframe: '1h',
  strategyVersion: 'structure-v2',
  direction: AutoTradeDirection.long,
  entryPrice: 100,
  stopLoss: 98,
  targets: const [104, 106, 108],
  createdAt: createdAt ?? now.subtract(const Duration(seconds: 20)),
  validUntil: now.add(const Duration(minutes: 10)),
  marketDataAt: marketDataAt ?? now.subtract(const Duration(seconds: 5)),
  primarySetup: primarySetup,
  timeframeConflict: timeframeConflict,
  estimatedRoundTripFeeRate: 0.001,
  estimatedSlippageBps: 10,
);

AutoTradePlanningContext _context(
  DateTime now, {
  AutoTradeOperatingMode mode = AutoTradeOperatingMode.shadow,
  int leverage = 10,
  double available = 800,
  List<AutoTradePosition> positions = const [],
  List<AutoTradeOrder> orders = const [],
}) => AutoTradePlanningContext(
  mode: mode,
  account: AutoTradeAccountSnapshot(
    marginCoin: 'USDT',
    available: available,
    frozen: 0,
    positionMargin: 0,
    crossUnrealizedPnl: 0,
    isolatedUnrealizedPnl: 0,
    positionMode: 'ONE_WAY',
    positions: positions,
    orders: orders,
    syncedAt: now.subtract(const Duration(seconds: 3)),
  ),
  instrument: const AutoTradeInstrumentRules(
    symbol: 'BTCUSDT',
    tickSize: 0.1,
    stepSize: 0.001,
    minimumQuantity: 0.001,
    maximumQuantity: 100,
    maximumLeverage: 100,
    tradable: true,
    apiTradingSupported: true,
  ),
  limits: AutoTradeExecutionLimits(
    riskPercent: 1,
    defaultLeverage: leverage,
    maximumConcurrentPositions: 3,
    maximumMarginUsagePercent: 50,
    maximumDailyLossPercent: 4,
    maximumSlippageBps: 15,
    maximumSignalAge: const Duration(minutes: 5),
    allowedSymbols: const {'BTCUSDT'},
    allowedTimeframes: const {'1h'},
    allowedStrategies: const {'structure-v2'},
  ),
  now: now,
  currentDailyLossPercent: 0,
  privateStreamHealthy: true,
);
