import 'package:flutter/foundation.dart';

import '../data/trading_journal_store.dart';
import '../domain/trading_journal_models.dart';
import '../domain/trading_journal_projection.dart';
import '../domain/trading_journal_statistics.dart';

final class TradingJournalController extends ChangeNotifier {
  TradingJournalController({required this.store});

  final TradingJournalStore store;
  TradingJournalLedger _ledger = TradingJournalLedger.empty();
  List<TradingJournalProjection> _projections = const [];
  TradingJournalStatistics _statistics = TradingJournalStatistics.calculate(
    const [],
  );
  bool _isLoading = false;
  String? _error;

  TradingJournalLedger get ledger => _ledger;
  List<TradingJournalProjection> get projections => _projections;
  TradingJournalStatistics get statistics => _statistics;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> initialize() => refresh();

  Future<void> refresh() async {
    if (_isLoading) return;
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      _ledger = await store.load();
      _rebuild();
    } on Object {
      _error = 'Journal integrity check failed.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> appendPlan(TradingJournalPlan plan) async {
    try {
      await store.appendPlan(plan);
      _ledger = await store.load();
      _rebuild();
      _error = null;
    } on Object {
      _error = 'Journal write failed safely.';
    }
    notifyListeners();
  }

  Future<void> appendEvent(TradingJournalEvent event) async {
    try {
      await store.appendEvent(event);
      _ledger = await store.load();
      _rebuild();
      _error = null;
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
}
