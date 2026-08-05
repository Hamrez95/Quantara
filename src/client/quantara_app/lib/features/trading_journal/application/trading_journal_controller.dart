import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../auto_trade/domain/trading_pnl_projection.dart';

import '../data/trading_journal_store.dart';
import '../domain/trading_journal_models.dart';
import '../domain/trading_journal_projection.dart';
import '../domain/trading_journal_statistics.dart';
import 'trading_journal_exchange_backfill.dart';

final class TradingJournalController extends ChangeNotifier {
  TradingJournalController({required this.store});

  final TradingJournalStore store;
  TradingJournalLedger _ledger = TradingJournalLedger.empty();
  List<TradingJournalProjection> _projections = const [];
  TradingJournalStatistics _statistics = TradingJournalStatistics.calculate(
    const [],
  );
  Timer? _localRefreshTimer;
  bool _isLoading = false;
  String? _error;

  TradingJournalLedger get ledger => _ledger;
  List<TradingJournalProjection> get projections => _projections;
  TradingJournalStatistics get statistics => _statistics;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> initialize() async {
    await refresh();
    _localRefreshTimer ??= Timer.periodic(
      const Duration(seconds: 3),
      (_) => unawaited(refresh(silent: true)),
    );
  }

  Future<void> refresh({bool silent = false}) async {
    if (_isLoading) return;
    _isLoading = true;
    var shouldNotify = !silent;
    if (!silent) {
      _error = null;
      notifyListeners();
    }
    try {
      final next = await store.load();
      final changed =
          next.generation != _ledger.generation ||
          next.integrity != _ledger.integrity ||
          !listEquals(next.warnings, _ledger.warnings);
      if (changed) {
        _ledger = next;
        _error = null;
        _rebuild();
        shouldNotify = true;
      }
    } on Object {
      const nextError = 'Journal integrity check failed.';
      shouldNotify = shouldNotify || _error != nextError;
      _error = nextError;
    } finally {
      _isLoading = false;
      if (shouldNotify) notifyListeners();
    }
  }

  Future<int> reconcileVerifiedExchangeClosures({
    required TradingPnlProjection pnlProjection,
    required Set<String> openPositionIds,
    DateTime? recordedAt,
  }) async {
    try {
      final current = await store.load();
      final result = TradingJournalExchangeBackfill.reconcileVerifiedClosures(
        ledger: current,
        pnlProjection: pnlProjection,
        openPositionIds: openPositionIds,
        recordedAt: (recordedAt ?? DateTime.now()).toUtc(),
      );
      if (!result.changed) return 0;
      await store.replace(result.ledger);
      _ledger = await store.load();
      _error = null;
      _rebuild();
      notifyListeners();
      return result.closedTradeIds.length;
    } on Object {
      _error = 'Verified exchange history could not repair the journal safely.';
      notifyListeners();
      return 0;
    }
  }

  Future<void> appendPlan(TradingJournalPlan plan) async {
    try {
      await store.appendPlan(plan);
      _ledger = await store.load();
      _error = null;
      _rebuild();
    } on Object {
      _error = 'Journal write failed safely.';
    }
    notifyListeners();
  }

  Future<void> appendEvent(TradingJournalEvent event) async {
    try {
      await store.appendEvent(event);
      _ledger = await store.load();
      _error = null;
      _rebuild();
    } on Object {
      _error = 'Journal write failed safely.';
    }
    notifyListeners();
  }

  void _rebuild() {
    _projections = TradingJournalProjector.projectAll(_ledger);
    _statistics = TradingJournalStatistics.calculate(_projections);
    if (_ledger.integrity == TradingJournalIntegrity.unverified) {
      _error = _ledger.warnings.isEmpty
          ? 'Journal integrity check failed.'
          : _ledger.warnings.join(' ');
    }
  }

  @override
  void dispose() {
    _localRefreshTimer?.cancel();
    super.dispose();
  }
}
