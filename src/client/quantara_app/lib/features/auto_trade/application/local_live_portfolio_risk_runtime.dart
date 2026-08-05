import '../../owner_alpha/domain/owner_alpha_models.dart';
import '../../portfolio_risk/application/portfolio_risk_coordinator.dart';
import '../../portfolio_risk/data/portfolio_risk_ledger_store.dart';
import '../../portfolio_risk/domain/portfolio_risk_models.dart';
import '../../portfolio_risk/domain/portfolio_risk_transitions.dart';
import '../domain/local_live_portfolio_admission.dart';
import '../domain/local_live_trade_models.dart';

final class LocalLivePortfolioRiskRuntime {
  factory LocalLivePortfolioRiskRuntime({
    required double dailyRiskLimit,
    PortfolioRiskLedgerStore? store,
    int timezoneOffsetMinutes = 0,
    double maximumAssetGroupRiskFraction = 0.60,
  }) => LocalLivePortfolioRiskRuntime._(
    store ??
        DatabasePortfolioRiskLedgerStore(
          recordKey: 'local-live-portfolio-risk-ledger-v1',
        ),
    dailyRiskLimit,
    timezoneOffsetMinutes,
    maximumAssetGroupRiskFraction,
  );

  const LocalLivePortfolioRiskRuntime._(
    this._store,
    this._dailyRiskLimit,
    this._timezoneOffsetMinutes,
    this.maximumAssetGroupRiskFraction,
  );

  final PortfolioRiskLedgerStore _store;
  final double _dailyRiskLimit;
  final int _timezoneOffsetMinutes;
  final double maximumAssetGroupRiskFraction;

  PortfolioRiskCoordinator get _coordinator => PortfolioRiskCoordinator(
    store: _store,
    policy: const PortfolioRiskPolicy(
      emergencyTechnicalCeiling:
          LocalLivePortfolioAdmission.maximumSupportedConcurrentPositions,
    ),
    defaultDailyRiskLimit: _dailyRiskLimit,
    timezoneOffsetMinutes: _timezoneOffsetMinutes,
  );

  Future<PortfolioRiskLedger> load({required DateTime now}) =>
      _coordinator.load(now: now);

  Future<PortfolioReservationOutcome> reserve({
    required PortfolioEntryCandidate candidate,
    required PortfolioAccountTruth account,
    required DateTime now,
  }) async {
    final store = _atomicStore;
    return store.mutate<PortfolioReservationOutcome>((current) async {
      var ledger = _normalize(current, now.toUtc());
      final accountWithReservations = _withLedgerReservations(account, ledger);
      var decision =
          const PortfolioRiskPolicy(
            emergencyTechnicalCeiling:
                LocalLivePortfolioAdmission.maximumSupportedConcurrentPositions,
          ).evaluate(
            ledger: ledger,
            candidate: candidate,
            account: accountWithReservations,
          );
      if (decision.allowed) {
        final sameAssetGroupRisk = ledger.activeReservations
            .where((item) => item.assetGroup == candidate.assetGroup)
            .fold<double>(0, (sum, item) => sum + item.maximumLoss);
        if (sameAssetGroupRisk + decision.maximumLoss >
            ledger.dailyRisk.limit * maximumAssetGroupRiskFraction + 1e-9) {
          decision = PortfolioEntryDecision(
            allowed: false,
            liveExecutionAllowed: false,
            reason: PortfolioEntryBlockReason.directionConcentration,
            maximumLoss: decision.maximumLoss,
            requiredMargin: decision.requiredMargin,
            availableRiskBefore: ledger.dailyRisk.available,
            availableRiskAfter: ledger.dailyRisk.available,
            availableMarginAfter:
                accountWithReservations.marginBudget.spendable,
          );
        }
      }
      if (decision.allowed) {
        decision = PortfolioEntryDecision(
          allowed: true,
          liveExecutionAllowed: true,
          reason: PortfolioEntryBlockReason.none,
          maximumLoss: decision.maximumLoss,
          requiredMargin: decision.requiredMargin,
          availableRiskBefore: decision.availableRiskBefore,
          availableRiskAfter: decision.availableRiskAfter,
          availableMarginAfter: decision.availableMarginAfter,
        );
        ledger = ledger.reserve(
          candidate: candidate,
          decision: decision,
          createdAt: now.toUtc(),
        );
      }
      return PortfolioRiskLedgerMutation(
        value: PortfolioReservationOutcome(
          decision: decision,
          ledger: ledger,
          snapshot: ledger.snapshot(account),
        ),
        nextLedger: ledger,
      );
    });
  }

  Future<PortfolioRiskLedger> adoptVerifiedOpenPosition({
    required LocalLiveManagedPosition managed,
    required double confirmedStop,
    required DateTime now,
  }) => _atomicStore.mutate<PortfolioRiskLedger>((current) async {
    final base = _normalize(current, now.toUtc());
    final positionId = managed.positionId.trim();
    if (positionId.isEmpty ||
        managed.initialQuantity <= 0 ||
        managed.entryPrice <= 0 ||
        confirmedStop <= 0 ||
        managed.leverage <= 0) {
      throw const LocalLiveTradeSafeException(
        'Recovered position risk facts are invalid.',
      );
    }
    final matching = base.activeReservations
        .where((item) => item.positionId == positionId)
        .toList(growable: false);
    final existingVerified = matching.where(
      (item) =>
          item.open &&
          item.verification == PortfolioVerificationState.exchangeConfirmed,
    );
    if (existingVerified.isNotEmpty) {
      final existing = existingVerified.single;
      if (existing.symbol.toUpperCase() == managed.symbol.toUpperCase() &&
          (existing.filledQuantity - managed.initialQuantity).abs() <= 1e-9) {
        return PortfolioRiskLedgerMutation(value: base, nextLedger: base);
      }
      throw const LocalLiveTradeSafeException(
        'A conflicting verified reservation already owns this position.',
      );
    }
    if (matching.any(
      (item) => !item.reservationId.startsWith('external-unmanaged:'),
    )) {
      throw const LocalLiveTradeSafeException(
        'A conflicting risk reservation prevents safe recovery.',
      );
    }
    if (base.activeReservations.any(
      (item) =>
          item.positionId != positionId &&
          item.symbol.toUpperCase() == managed.symbol.toUpperCase(),
    )) {
      throw const LocalLiveTradeSafeException(
        'Another active reservation already uses the recovered symbol.',
      );
    }

    final notional = managed.initialQuantity * managed.entryPrice;
    final entryFee = notional * 0.0006;
    final exitFee = managed.initialQuantity * confirmedStop * 0.0006;
    final slippage = notional * 0.0008;
    final fundingReserve = notional * 0.0003;
    final side = managed.direction == TradeDirection.long
        ? PortfolioSide.long
        : PortfolioSide.short;
    final maximumLoss = PortfolioRiskMath.confirmedOpenRisk(
      side: side,
      entryPrice: managed.entryPrice,
      confirmedStop: confirmedStop,
      remainingQuantity: managed.initialQuantity,
      contractMultiplier: 1,
      entryFee: entryFee,
      exitFee: exitFee,
      slippageReserve: slippage,
      fundingReserve: fundingReserve,
    );
    final observedMargin = notional / managed.leverage;
    final retained = base.reservations
        .where(
          (item) =>
              !(item.positionId == positionId &&
                  item.reservationId.startsWith('external-unmanaged:')),
        )
        .toList(growable: false);
    final reservation = PositionRiskReservation(
      reservationId: 'recovered-local-live:$positionId',
      journalTradeId: 'local-live:$positionId',
      candidateId: managed.setupId,
      symbol: managed.symbol.toUpperCase(),
      assetGroup: LocalLivePortfolioAdmission.assetGroupForSymbol(
        managed.symbol,
      ),
      side: side,
      strategy: 'recovered-local-live',
      entryOrderId: managed.entryOrderId,
      positionId: positionId,
      plannedQuantity: managed.initialQuantity,
      filledQuantity: managed.initialQuantity,
      entryPrice: managed.entryPrice,
      currentExchangeConfirmedStop: confirmedStop,
      contractMultiplier: 1,
      estimatedEntryFee: entryFee,
      estimatedExitFee: exitFee,
      slippageReserve: slippage,
      fundingReserve: fundingReserve,
      maximumLoss: maximumLoss,
      reservedMargin: observedMargin,
      createdAt: managed.openedAt.toUtc(),
      tradingDayId: base.tradingDay.value,
      lifecycle: PortfolioReservationLifecycle.open,
      verification: PortfolioVerificationState.exchangeConfirmed,
      revision: 1,
    );
    final next = PortfolioRiskLedger(
      schemaVersion: base.schemaVersion,
      revision: base.revision + 1,
      tradingDay: base.tradingDay,
      dailyRiskLimit: base.dailyRiskLimit,
      realizedLoss: base.realizedLoss,
      realizedProfit: base.realizedProfit,
      reservations: [...retained, reservation],
      processedEventIds: {
        ...base.processedEventIds,
        'recover-open:$positionId',
      },
    );
    return PortfolioRiskLedgerMutation(value: next, nextLedger: next);
  });

  Future<PortfolioRiskLedger> release({
    required String reservationId,
    required String eventId,
    required DateTime now,
  }) => _coordinator.release(
    reservationId: reservationId,
    eventId: eventId,
    now: now,
  );

  Future<PortfolioRiskLedger> markAmbiguous({
    required String reservationId,
    required String eventId,
    required DateTime now,
  }) => _coordinator.markAmbiguous(
    reservationId: reservationId,
    eventId: eventId,
    now: now,
  );

  Future<PortfolioRiskLedger> recordFill({
    required String reservationId,
    required String eventId,
    required String entryOrderId,
    required String positionId,
    required double fillQuantity,
    required DateTime now,
  }) => _coordinator.applyPartialFill(
    reservationId: reservationId,
    eventId: eventId,
    entryOrderId: entryOrderId,
    positionId: positionId,
    fillQuantity: fillQuantity,
    now: now,
  );

  Future<PortfolioRiskLedger> confirmStop({
    required String positionId,
    required String eventId,
    required double confirmedStop,
    required DateTime now,
  }) => _coordinator.confirmStop(
    positionId: positionId,
    eventId: eventId,
    confirmedStop: confirmedStop,
    now: now,
  );

  Future<PortfolioRiskLedger> reduce({
    required String positionId,
    required String eventId,
    required double remainingQuantity,
    required DateTime now,
  }) => _atomicStore.mutate<PortfolioRiskLedger>((current) async {
    final base = _normalize(current, now.toUtc());
    final next = PortfolioRiskTransitions.applyExchangeConfirmedReduction(
      ledger: base,
      positionId: positionId,
      eventId: eventId,
      remainingQuantity: remainingQuantity,
    );
    return PortfolioRiskLedgerMutation(value: next, nextLedger: next);
  });

  Future<PortfolioRiskLedger> close({
    required String positionId,
    required String eventId,
    required double exchangeConfirmedNetPnl,
    required DateTime now,
  }) => _coordinator.closePosition(
    positionId: positionId,
    eventId: eventId,
    exchangeConfirmedNetPnl: exchangeConfirmedNetPnl,
    now: now,
  );

  Future<PortfolioRiskSnapshot> snapshot({
    required PortfolioAccountTruth account,
    required DateTime now,
  }) => _coordinator.snapshot(account: account, now: now);

  AtomicPortfolioRiskLedgerStore get _atomicStore {
    final store = _store;
    if (store is! AtomicPortfolioRiskLedgerStore) {
      throw StateError('Local Live portfolio risk requires atomic storage.');
    }
    return store as AtomicPortfolioRiskLedgerStore;
  }

  PortfolioRiskLedger _normalize(PortfolioRiskLedger? current, DateTime now) {
    if (current == null) {
      return PortfolioRiskLedger.initial(
        tradingDay: TradingDayId.start(
          now: now,
          timezoneOffsetMinutes: _timezoneOffsetMinutes,
        ),
        dailyRiskLimit: _dailyRiskLimit,
      );
    }
    final rolled = current.rollTradingDay(
      now: now,
      nextDailyRiskLimit: _dailyRiskLimit,
    );
    if (rolled.activeReservations.isNotEmpty ||
        rolled.realizedLoss > 0 ||
        rolled.realizedProfit > 0 ||
        (rolled.dailyRiskLimit - _dailyRiskLimit).abs() <= 1e-9) {
      return rolled;
    }
    return PortfolioRiskLedger(
      schemaVersion: rolled.schemaVersion,
      revision: rolled.revision + 1,
      tradingDay: rolled.tradingDay,
      dailyRiskLimit: _dailyRiskLimit,
      realizedLoss: rolled.realizedLoss,
      realizedProfit: rolled.realizedProfit,
      reservations: rolled.reservations,
      processedEventIds: rolled.processedEventIds,
    );
  }

  PortfolioAccountTruth _withLedgerReservations(
    PortfolioAccountTruth account,
    PortfolioRiskLedger ledger,
  ) => PortfolioAccountTruth(
    asOf: account.asOf,
    fresh: account.fresh,
    allOpenPositionsProtected: account.allOpenPositionsProtected,
    marginMode: account.marginMode,
    freeMargin: account.freeMargin,
    usedMargin: account.usedMargin,
    maintenanceMargin: account.maintenanceMargin,
    pendingMarginReservations:
        account.pendingMarginReservations + ledger.reservedMargin,
    safetyBuffer: account.safetyBuffer,
    feeReserve: account.feeReserve,
  );
}
