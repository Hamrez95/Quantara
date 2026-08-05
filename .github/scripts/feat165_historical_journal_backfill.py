from pathlib import Path

root = Path('src/client/quantara_app')


def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text()
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{path}: expected one anchor, found {count}')
    path.write_text(text.replace(old, new, 1))


backfill = root / 'lib/features/trading_journal/application/trading_journal_exchange_backfill.dart'
backfill.write_text(r'''import '../../auto_trade/domain/trading_pnl_projection.dart';
import '../domain/trading_journal_models.dart';
import '../domain/trading_journal_projection.dart';

final class TradingJournalExchangeBackfillResult {
  const TradingJournalExchangeBackfillResult({
    required this.ledger,
    required this.closedTradeIds,
  });

  final TradingJournalLedger ledger;
  final List<String> closedTradeIds;

  bool get changed => closedTradeIds.isNotEmpty;
}

abstract final class TradingJournalExchangeBackfill {
  static TradingJournalExchangeBackfillResult reconcileVerifiedClosures({
    required TradingJournalLedger ledger,
    required TradingPnlProjection pnlProjection,
    required Set<String> openPositionIds,
    required DateTime recordedAt,
  }) {
    if (ledger.integrity == TradingJournalIntegrity.unverified ||
        !pnlProjection.isVerified ||
        !pnlProjection.fillsAvailable ||
        !pnlProjection.settlementsAvailable) {
      return TradingJournalExchangeBackfillResult(
        ledger: ledger,
        closedTradeIds: const [],
      );
    }

    final normalizedOpenIds = openPositionIds
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toSet();
    var next = ledger;
    final closedTradeIds = <String>[];
    final projections = TradingJournalProjector.projectAll(ledger);
    final plansById = {
      for (final plan in ledger.plans) plan.journalTradeId: plan,
    };

    for (final journal in projections) {
      final plan = plansById[journal.journalTradeId];
      if (plan == null ||
          plan.source != TradingJournalSource.localLive ||
          journal.state != TradingJournalTradeState.open) {
        continue;
      }
      final positionId = (journal.positionId ?? plan.positionId ?? '').trim();
      if (positionId.isEmpty || normalizedOpenIds.contains(positionId)) {
        continue;
      }
      final position = pnlProjection.forPositionId(positionId);
      if (!_isVerifiedClosedPosition(position, plan)) continue;

      final exits = [...position!.exitFills]
        ..sort((left, right) => left.occurredAt.compareTo(right.occurredAt));
      final latest = exits.last;
      final totalQuantity = exits.fold<double>(
        0,
        (sum, fill) => sum + fill.quantity.abs(),
      );
      final weightedNotional = exits.fold<double>(
        0,
        (sum, fill) => sum + fill.quantity.abs() * fill.price,
      );
      final closePrice = totalQuantity > 0
          ? weightedNotional / totalQuantity
          : latest.price;
      final closeReason = _inferCloseReason(plan, latest.price);
      final settlement = position.settlement!;
      final eventId =
          'verified-history-close:$positionId:${settlement.closedAt.toUtc().microsecondsSinceEpoch}';
      final event = TradingJournalEvent(
        eventId: eventId,
        journalTradeId: plan.journalTradeId,
        type: TradingJournalEventType.positionClosed,
        occurredAt: settlement.closedAt.toUtc(),
        recordedAt: recordedAt.toUtc(),
        source: TradingJournalFactSource.exchange,
        quality: TradingJournalFactQuality.confirmed,
        scope: TradingJournalScope.position,
        currency: pnlProjection.currency,
        asOf: position.asOf.toUtc(),
        positionId: positionId,
        orderId: latest.orderId.trim().isEmpty ? null : latest.orderId.trim(),
        quantity: totalQuantity > 0 ? totalQuantity : null,
        price: closePrice.isFinite && closePrice > 0 ? closePrice : null,
        grossPnl: _economicDelta(
          authoritative: position.realizedGross.value,
          journalValue: journal.grossPnl,
        ),
        fee: _economicDelta(
          authoritative: position.fees.value,
          journalValue: journal.fees,
        ),
        funding: _economicDelta(
          authoritative: position.funding.value,
          journalValue: journal.funding,
        ),
        remainingQuantity: 0,
        details: {
          'closeReason': closeReason.name,
          'backfilledFromVerifiedHistory': true,
          'exchangeTradeIds': exits
              .map((item) => item.tradeId)
              .where((item) => item.trim().isNotEmpty)
              .toList(growable: false),
          'latestExchangeTradeId': latest.tradeId,
          'authoritativeGrossPnl': position.realizedGross.value,
          'authoritativeFee': position.fees.value,
          'authoritativeFunding': position.funding.value,
        },
      );
      final appended = next.appendEvent(event);
      if (appended.generation == next.generation) continue;
      if (appended.integrity == TradingJournalIntegrity.unverified) {
        return TradingJournalExchangeBackfillResult(
          ledger: ledger,
          closedTradeIds: const [],
        );
      }
      next = appended;
      closedTradeIds.add(plan.journalTradeId);
    }

    return TradingJournalExchangeBackfillResult(
      ledger: next,
      closedTradeIds: List.unmodifiable(closedTradeIds),
    );
  }

  static bool _isVerifiedClosedPosition(
    PositionPnlProjection? position,
    TradingJournalPlan plan,
  ) {
    if (position == null ||
        !position.isVerified ||
        position.settlement == null ||
        position.exitFills.isEmpty ||
        !position.realizedGross.isFinal ||
        !position.fees.isFinal ||
        !position.funding.isFinal) {
      return false;
    }
    final settlement = position.settlement!;
    if (settlement.closedAt.toUtc().isBefore(plan.decidedAt.toUtc())) {
      return false;
    }
    if (position.symbol.trim().toUpperCase() !=
        plan.symbol.trim().toUpperCase()) {
      return false;
    }
    return position.exitFills.every(
      (fill) =>
          fill.reduceOnly &&
          fill.positionId.trim() == position.positionId.trim() &&
          fill.tradeId.trim().isNotEmpty &&
          fill.quantity.isFinite &&
          fill.quantity > 0 &&
          fill.price.isFinite &&
          fill.price > 0,
    );
  }

  static double _economicDelta({
    required double? authoritative,
    required double? journalValue,
  }) {
    final value = (authoritative ?? 0) - (journalValue ?? 0);
    return value.abs() < 0.00000001 ? 0 : value;
  }

  static TradingJournalCloseReason _inferCloseReason(
    TradingJournalPlan plan,
    double finalPrice,
  ) {
    if (!finalPrice.isFinite || finalPrice <= 0) {
      return TradingJournalCloseReason.exchange;
    }
    final stop = plan.originalStopLoss;
    if (stop.isFinite && stop > 0) {
      final stopTolerance = stop.abs() * 0.003;
      final stopLike = switch (plan.direction) {
        TradingJournalDirection.long => finalPrice <= stop + stopTolerance,
        TradingJournalDirection.short => finalPrice >= stop - stopTolerance,
        TradingJournalDirection.wait => false,
      };
      if (stopLike) return TradingJournalCloseReason.stop;
    }

    var highestTarget = 0;
    for (var index = 0; index < plan.targets.length && index < 3; index++) {
      final target = plan.targets[index];
      if (!target.isFinite || target <= 0) continue;
      final tolerance = target.abs() * 0.003;
      final reached = switch (plan.direction) {
        TradingJournalDirection.long => finalPrice + tolerance >= target,
        TradingJournalDirection.short => finalPrice - tolerance <= target,
        TradingJournalDirection.wait => false,
      };
      if (reached) highestTarget = index + 1;
    }
    return switch (highestTarget) {
      1 => TradingJournalCloseReason.takeProfit1,
      2 => TradingJournalCloseReason.takeProfit2,
      3 => TradingJournalCloseReason.takeProfit3,
      _ => TradingJournalCloseReason.exchange,
    };
  }
}
''')

controller = root / 'lib/features/trading_journal/application/trading_journal_controller.dart'
text = controller.read_text()
if 'reconcileVerifiedExchangeClosures' not in text:
    replace_once(
        controller,
        "import 'package:flutter/foundation.dart';\n",
        "import 'package:flutter/foundation.dart';\n\nimport '../../auto_trade/domain/trading_pnl_projection.dart';\n",
    )
    replace_once(
        controller,
        "import '../domain/trading_journal_statistics.dart';\n",
        "import '../domain/trading_journal_statistics.dart';\nimport 'trading_journal_exchange_backfill.dart';\n",
    )
    marker = '''  Future<void> appendPlan(TradingJournalPlan plan) async {'''
    method = '''  Future<int> reconcileVerifiedExchangeClosures({
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

'''
    if marker not in controller.read_text():
        raise SystemExit('journal controller append plan marker missing')
    controller.write_text(controller.read_text().replace(marker, method + marker, 1))

page = root / 'lib/features/owner_alpha/presentation/owner_alpha_page.dart'
text = page.read_text()
if '_reconcileJournalFromAccount' not in text:
    marker = '''  Future<void> _refreshCurrentDestination() async {'''
    helper = '''  Future<void> _reconcileJournalFromAccount() async {
    final snapshot = _autoTradeController.snapshot;
    if (snapshot == null) return;
    await _journalController.reconcileVerifiedExchangeClosures(
      pnlProjection: snapshot.authoritativePnl,
      openPositionIds: snapshot.positions
          .map((position) => position.positionId.trim())
          .where((positionId) => positionId.isNotEmpty)
          .toSet(),
    );
  }

'''
    if marker not in text:
        raise SystemExit('owner page refresh marker missing')
    page.write_text(text.replace(marker, helper + marker, 1))
    replace_once(
        page,
        '''        if (state != null) {
          await state.refreshAll();
        } else {
          await _autoTradeController.reconcile(
            reason: PrivateAccountRefreshReason.manual,
            force: true,
          );
        }
        return;
      case 6:
        await _journalController.refresh();
        return;''',
        '''        if (state != null) {
          await state.refreshAll();
        } else {
          await _autoTradeController.reconcile(
            reason: PrivateAccountRefreshReason.manual,
            force: true,
          );
        }
        await _reconcileJournalFromAccount();
        return;
      case 6:
        if (_autoTradeController.isConnected) {
          await _autoTradeController.reconcile(
            reason: PrivateAccountRefreshReason.manual,
            force: true,
          );
        }
        await _reconcileJournalFromAccount();
        await _journalController.refresh();
        return;''',
    )
    replace_once(
        page,
        '''            onNavigate: (value) => setState(() => _destination = value),''',
        '''            onNavigate: (value) {
              setState(() => _destination = value);
              if (value == 5 || value == 6) {
                unawaited(_refreshCurrentDestination());
              }
            },''',
    )

(root / 'test/trading_journal_exchange_backfill_test.dart').write_text(r'''import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/auto_trade/domain/trading_pnl_projection.dart';
import 'package:quantara_app/features/trading_journal/application/trading_journal_exchange_backfill.dart';
import 'package:quantara_app/features/trading_journal/domain/trading_journal_models.dart';
import 'package:quantara_app/features/trading_journal/domain/trading_journal_projection.dart';

void main() {
  test('repairs the historical GRAM stop from verified exchange history', () {
    final ledger = TradingJournalLedger.empty()
        .appendPlan(_plan())
        .appendEvent(_entry());
    final pnl = _verifiedPnl();

    final result = TradingJournalExchangeBackfill.reconcileVerifiedClosures(
      ledger: ledger,
      pnlProjection: pnl,
      openPositionIds: const {},
      recordedAt: DateTime.utc(2026, 8, 5, 5),
    );
    final projection = TradingJournalProjector.project(
      ledger: result.ledger,
      journalTradeId: 'local-live:gram-position',
    );

    expect(result.closedTradeIds, ['local-live:gram-position']);
    expect(projection.state, TradingJournalTradeState.closed);
    expect(projection.closeReason, TradingJournalCloseReason.stop);
    expect(projection.remainingQuantity, 0);
    expect(projection.grossPnl, closeTo(-0.2574, 0.00000001));
    expect(projection.fees, closeTo(0.03575286, 0.00000001));
    expect(projection.funding, 0);
    expect(projection.netPnl, closeTo(-0.29315286, 0.00000001));
    final close = projection.timeline.last;
    expect(close.quantity, 42.9);
    expect(close.price, 1.389);
    expect(close.details['backfilledFromVerifiedHistory'], isTrue);
  });

  test('historical closure repair is idempotent', () {
    final first = TradingJournalExchangeBackfill.reconcileVerifiedClosures(
      ledger: TradingJournalLedger.empty()
          .appendPlan(_plan())
          .appendEvent(_entry()),
      pnlProjection: _verifiedPnl(),
      openPositionIds: const {},
      recordedAt: DateTime.utc(2026, 8, 5, 5),
    );
    final second = TradingJournalExchangeBackfill.reconcileVerifiedClosures(
      ledger: first.ledger,
      pnlProjection: _verifiedPnl(),
      openPositionIds: const {},
      recordedAt: DateTime.utc(2026, 8, 5, 5, 1),
    );

    expect(second.changed, isFalse);
    expect(second.ledger.events, hasLength(first.ledger.events.length));
    expect(second.ledger.integrity, isNot(TradingJournalIntegrity.unverified));
  });

  test('does not close a journal trade while exchange position remains open', () {
    final ledger = TradingJournalLedger.empty()
        .appendPlan(_plan())
        .appendEvent(_entry());
    final result = TradingJournalExchangeBackfill.reconcileVerifiedClosures(
      ledger: ledger,
      pnlProjection: _verifiedPnl(),
      openPositionIds: const {'gram-position'},
      recordedAt: DateTime.utc(2026, 8, 5, 5),
    );

    expect(result.changed, isFalse);
    expect(result.ledger.generation, ledger.generation);
  });

  test('does not mutate journal from unverified exchange truth', () {
    final ledger = TradingJournalLedger.empty()
        .appendPlan(_plan())
        .appendEvent(_entry());
    final unverified = TradingPnlProjection.unavailable(
      currency: 'USDT',
      asOf: DateTime.utc(2026, 8, 5, 5),
      warning: 'ambiguous',
    );
    final result = TradingJournalExchangeBackfill.reconcileVerifiedClosures(
      ledger: ledger,
      pnlProjection: unverified,
      openPositionIds: const {},
      recordedAt: DateTime.utc(2026, 8, 5, 5),
    );

    expect(result.changed, isFalse);
    expect(result.ledger.generation, ledger.generation);
  });
}

TradingPnlProjection _verifiedPnl() => TradingPnlProjection.reconcile(
  currency: 'USDT',
  asOf: DateTime.utc(2026, 8, 5, 3, 20),
  unrealizedByPosition: const {},
  fills: [
    ExchangePnlFill(
      tradeId: '2795413522294203930',
      orderId: '7352379888826528074',
      positionId: 'gram-position',
      symbol: 'GRAMUSDT',
      quantity: 42.9,
      price: 1.389,
      realizedPnl: -0.2574,
      fee: 0.03575286,
      reduceOnly: true,
      occurredAt: DateTime.utc(2026, 8, 5, 3, 19, 14),
      side: 'SELL',
    ),
  ],
  settlements: [
    ExchangePositionSettlement(
      positionId: 'gram-position',
      symbol: 'GRAMUSDT',
      funding: 0,
      openedAt: DateTime.utc(2026, 8, 5, 2),
      closedAt: DateTime.utc(2026, 8, 5, 3, 19, 14),
      realizedPnl: -0.2574,
      fee: 0.03575286,
    ),
  ],
);

TradingJournalPlan _plan() => TradingJournalPlan(
  journalTradeId: 'local-live:gram-position',
  setupId: 'gram-setup',
  analysisVersion: 'v1',
  symbol: 'GRAMUSDT',
  market: 'USDT_PERPETUAL',
  timeframe: '15m',
  direction: TradingJournalDirection.long,
  strategy: 'structureZones',
  cadence: 'local-live',
  source: TradingJournalSource.localLive,
  decidedAt: DateTime.utc(2026, 8, 5, 2),
  decisionPrice: 1.40,
  entryLower: 1.40,
  entryUpper: 1.40,
  plannedEntry: 1.40,
  originalStopLoss: 1.39,
  targets: const [1.4191578119874324, 1.4100541342999584, 1.4282614896749064],
  expectedRMultiples: const [1, 2, 3],
  confidencePercent: 70,
  confluence: const ['15m'],
  regime: 'transition',
  rationale: 'physical canary',
  invalidation: 'stop',
  accountEquity: 29.81,
  riskPercent: 0.1,
  riskBudget: 0.02981,
  leverage: 10,
  expectedMargin: 6.006,
  passedGates: const ['isolated-margin'],
  blockedGates: const [],
  appVersion: '1.2.0-rc.2',
  strategyRulesVersion: 'v1',
  positionId: 'gram-position',
  entryOrderId: 'entry-order',
  clientId: 'q-local-gram',
);

TradingJournalEvent _entry() => TradingJournalEvent(
  eventId: 'entry',
  journalTradeId: 'local-live:gram-position',
  type: TradingJournalEventType.entryFilled,
  occurredAt: DateTime.utc(2026, 8, 5, 2),
  recordedAt: DateTime.utc(2026, 8, 5, 2),
  source: TradingJournalFactSource.exchange,
  quality: TradingJournalFactQuality.confirmed,
  scope: TradingJournalScope.position,
  currency: 'USDT',
  asOf: DateTime.utc(2026, 8, 5, 2),
  positionId: 'gram-position',
  orderId: 'entry-order',
  quantity: 42.9,
  price: 1.40,
  remainingQuantity: 42.9,
);
''')

source_test = root / 'test/physical_canary_regression_source_test.dart'
text = source_test.read_text()
if 'reconcileVerifiedExchangeClosures' not in text:
    marker = '''  test('journal confirmation and closed lifecycle are neutral, not profit green', () {'''
    addition = '''  test('verified historical exchange closure repairs old open journal records', () {
    final controller = File(
      'lib/features/trading_journal/application/trading_journal_controller.dart',
    ).readAsStringSync();
    final page = File(
      'lib/features/owner_alpha/presentation/owner_alpha_page.dart',
    ).readAsStringSync();
    expect(controller, contains('reconcileVerifiedExchangeClosures'));
    expect(page, contains('_reconcileJournalFromAccount'));
    expect(page, contains('snapshot.authoritativePnl'));
    expect(page, contains('value == 5 || value == 6'));
  });

'''
    if marker not in text:
        raise SystemExit('physical source test journal marker missing')
    source_test.write_text(text.replace(marker, addition + marker, 1))
