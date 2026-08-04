import '../../portfolio_risk/application/portfolio_risk_coordinator.dart';
import '../../portfolio_risk/data/portfolio_risk_ledger_store.dart';
import '../../portfolio_risk/domain/portfolio_risk_models.dart';
import '../../portfolio_risk/domain/portfolio_risk_transitions.dart';

final class LocalLivePortfolioRiskRuntime {
  LocalLivePortfolioRiskRuntime({
    required double dailyRiskLimit,
    PortfolioRiskLedgerStore? store,
    int timezoneOffsetMinutes = 0,
  }) : _store =
           store ??
           DatabasePortfolioRiskLedgerStore(
             recordKey: 'local-live-portfolio-risk-ledger-v1',
           ),
       _dailyRiskLimit = dailyRiskLimit,
       _timezoneOffsetMinutes = timezoneOffsetMinutes;

  final PortfolioRiskLedgerStore _store;
  final double _dailyRiskLimit;
  final int _timezoneOffsetMinutes;

  PortfolioRiskCoordinator get _coordinator => PortfolioRiskCoordinator(
    store: _store,
    defaultDailyRiskLimit: _dailyRiskLimit,
    timezoneOffsetMinutes: _timezoneOffsetMinutes,
  );

  Future<PortfolioReservationOutcome> reserve({
    required PortfolioEntryCandidate candidate,
    required PortfolioAccountTruth account,
    required DateTime now,
  }) => _coordinator.reserve(candidate: candidate, account: account, now: now);

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
  }) async {
    final store = _store;
    if (store is! AtomicPortfolioRiskLedgerStore) {
      throw StateError('Local Live portfolio reductions require atomic storage.');
    }
    return store.mutate<PortfolioRiskLedger>((current) async {
      final base = current ??
          PortfolioRiskLedger.initial(
            tradingDay: TradingDayId.start(
              now: now,
              timezoneOffsetMinutes: _timezoneOffsetMinutes,
            ),
            dailyRiskLimit: _dailyRiskLimit,
          );
      final next = PortfolioRiskTransitions.applyExchangeConfirmedReduction(
        ledger: base,
        positionId: positionId,
        eventId: eventId,
        remainingQuantity: remainingQuantity,
      );
      return PortfolioRiskLedgerMutation(value: next, nextLedger: next);
    });
  }

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
}
