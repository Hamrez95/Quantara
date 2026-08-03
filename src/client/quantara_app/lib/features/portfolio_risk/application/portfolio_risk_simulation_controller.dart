import 'package:flutter/foundation.dart';

import '../data/portfolio_risk_ledger_store.dart';
import '../domain/portfolio_risk_models.dart';
import 'portfolio_risk_coordinator.dart';

final class PortfolioRiskSimulationController extends ChangeNotifier {
  PortfolioRiskSimulationController({
    PortfolioRiskCoordinator? coordinator,
    PortfolioAccountTruth? account,
  }) : _coordinator =
           coordinator ??
           PortfolioRiskCoordinator(
             store: DatabasePortfolioRiskLedgerStore(),
             defaultDailyRiskLimit: 10,
             timezoneOffsetMinutes: DateTime.now().timeZoneOffset.inMinutes,
           ),
       _account =
           account ??
           PortfolioAccountTruth(
             asOf: DateTime.now().toUtc(),
             fresh: true,
             allOpenPositionsProtected: true,
             marginMode: 'isolated',
             freeMargin: 100,
             usedMargin: 0,
             maintenanceMargin: 0,
             pendingMarginReservations: 0,
             safetyBuffer: 10,
             feeReserve: 1,
           );

  final PortfolioRiskCoordinator _coordinator;
  PortfolioAccountTruth _account;
  PortfolioRiskSnapshot? _snapshot;
  PortfolioEntryDecision? _lastDecision;
  Object? _error;
  bool _loading = false;
  int _sequence = 0;

  PortfolioRiskSnapshot? get snapshot => _snapshot;
  PortfolioEntryDecision? get lastDecision => _lastDecision;
  Object? get error => _error;
  bool get loading => _loading;
  bool get accountFresh => _account.fresh;

  Future<void> initialize() async {
    if (_loading) return;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _snapshot = await _coordinator.snapshot(account: _account);
    } on Object catch (error) {
      _error = error;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> reserveExample(double riskAmount) async {
    if (_loading) return;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final sequence = ++_sequence;
      final symbols = ['BTCUSDT', 'ETHUSDT', 'SOLUSDT', 'XRPUSDT'];
      final symbol = symbols[(sequence - 1) % symbols.length];
      final side = sequence.isOdd ? PortfolioSide.long : PortfolioSide.short;
      final entry = 100.0;
      final stop = side == PortfolioSide.long ? 99.0 : 101.0;
      final outcome = await _coordinator.reserve(
        candidate: PortfolioEntryCandidate(
          reservationId: 'simulation-reservation-$sequence',
          journalTradeId: 'simulation-trade-$sequence',
          candidateId: 'simulation-candidate-$sequence',
          symbol: symbol,
          assetGroup: 'crypto',
          side: side,
          strategy: 'portfolio-budget-simulation',
          plannedQuantity: riskAmount,
          entryPrice: entry,
          stopPrice: stop,
          contractMultiplier: 1,
          entryFeeRate: 0,
          exitFeeRate: 0,
          slippageRate: 0,
          fundingReserve: 0,
          requiredMargin: riskAmount * 2,
          leverage: 10,
          minimumQuantity: 0.001,
          minimumNotional: 1,
        ),
        account: _account,
      );
      _lastDecision = outcome.decision;
      _snapshot = outcome.snapshot;
    } on Object catch (error) {
      _error = error;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> reset() async {
    if (_loading) return;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      await _coordinator.resetSimulation(
        now: DateTime.now().toUtc(),
        dailyRiskLimit: 10,
      );
      _sequence = 0;
      _lastDecision = null;
      _snapshot = await _coordinator.snapshot(account: _account);
    } on Object catch (error) {
      _error = error;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> toggleFreshness() async {
    _account = PortfolioAccountTruth(
      asOf: DateTime.now().toUtc(),
      fresh: !_account.fresh,
      allOpenPositionsProtected: _account.allOpenPositionsProtected,
      marginMode: _account.marginMode,
      freeMargin: _account.freeMargin,
      usedMargin: _account.usedMargin,
      maintenanceMargin: _account.maintenanceMargin,
      pendingMarginReservations: _account.pendingMarginReservations,
      safetyBuffer: _account.safetyBuffer,
      feeReserve: _account.feeReserve,
    );
    await initialize();
  }
}
