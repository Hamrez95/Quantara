import 'dart:async';

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
  int _pendingOperations = 0;
  Future<void>? _initialization;
  Future<void> _operationTail = Future<void>.value();

  PortfolioRiskSnapshot? get snapshot => _snapshot;
  PortfolioEntryDecision? get lastDecision => _lastDecision;
  Object? get error => _error;
  bool get loading => _loading;
  bool get accountFresh => _account.fresh;

  Future<void> initialize() => _initialization ??= _initializeOnce();

  Future<void> _initializeOnce() async {
    _setLoading(true);
    _error = null;
    try {
      _snapshot = await _coordinator.snapshot(account: _account);
      _publishState();
    } on Object catch (error) {
      _error = error;
      _publishState();
    } finally {
      if (_pendingOperations == 0) _setLoading(false);
    }
  }

  Future<void> reserveExample(double riskAmount) => _enqueue(() async {
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
    _publishState();
  });

  Future<void> reset() => _enqueue(() async {
    await _coordinator.resetSimulation(
      now: DateTime.now().toUtc(),
      dailyRiskLimit: 10,
    );
    _sequence = 0;
    _lastDecision = null;
    _snapshot = await _coordinator.snapshot(account: _account);
    _publishState();
  });

  Future<void> toggleFreshness() => _enqueue(() async {
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
    _snapshot = await _coordinator.snapshot(account: _account);
    _publishState();
  });

  Future<void> _enqueue(Future<void> Function() operation) {
    _pendingOperations += 1;
    _setLoading(true);

    final result = _operationTail.then<void>((_) async {
      await initialize();
      _error = null;
      try {
        await operation();
      } on Object catch (error, stackTrace) {
        _error = error;
        _publishState();
        Error.throwWithStackTrace(error, stackTrace);
      } finally {
        _pendingOperations -= 1;
        if (_pendingOperations == 0) _setLoading(false);
      }
    });
    _operationTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  void _publishState() {
    notifyListeners();
  }

  void _setLoading(bool value) {
    if (_loading == value) return;
    _loading = value;
    notifyListeners();
  }
}
