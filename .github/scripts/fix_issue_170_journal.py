from pathlib import Path

ROOT = Path('src/client/quantara_app')


def replace_once(path: Path, old: str, new: str, label: str) -> None:
    text = path.read_text(encoding='utf-8')
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f'{label}: expected one match, found {count}')
    path.write_text(text.replace(old, new, 1), encoding='utf-8')

# 1) A closed position with internally consistent settlement + fills can be
# verified at position scope even when an unrelated historical row made the
# account-wide source warning non-verified.
pnl = ROOT / 'lib/features/auto_trade/domain/trading_pnl_projection.dart'
replace_once(
    pnl,
    """      final verified = !positionConflict && sourceVerified;

      final realizedValue = fillsAvailable
""",
    """      final closedEvidenceCanStandAlone =
          settlement != null && positionFills.isNotEmpty && !positionConflict;
      final verified =
          !positionConflict && (sourceVerified || closedEvidenceCanStandAlone);

      final realizedValue = fillsAvailable
""",
    'closed position scoped verification',
)

# 2) Do not let one old unverified foreground-mirror warning freeze all future
# Local Live journal events. Import each newer fact only if it keeps the durable
# ledger verified.
db_store = ROOT / 'lib/features/trading_journal/data/database_trading_journal_store.dart'
replace_once(
    db_store,
    """  if (durable.integrity == TradingJournalIntegrity.unverified ||
      foregroundMirror.integrity == TradingJournalIntegrity.unverified) {
    return durable;
  }
  var merged = durable;
""",
    """  if (durable.integrity == TradingJournalIntegrity.unverified) {
    return durable;
  }
  var merged = durable;
""",
    'foreground mirror whole-ledger freeze',
)
replace_once(
    db_store,
    """    merged = merged.appendPlan(plan);
  }
  final knownTradeIds = merged.plans.map((plan) => plan.journalTradeId).toSet();
""",
    """    final candidate = merged.appendPlan(plan);
    if (candidate.integrity != TradingJournalIntegrity.unverified) {
      merged = candidate;
    }
  }
  final knownTradeIds = merged.plans.map((plan) => plan.journalTradeId).toSet();
""",
    'safe plan import',
)
replace_once(
    db_store,
    """    merged = merged.appendEvent(event);
  }
  return merged;
""",
    """    final candidate = merged.appendEvent(event);
    if (candidate.integrity != TradingJournalIntegrity.unverified) {
      merged = candidate;
    }
  }
  return merged;
""",
    'safe event import',
)

# 3) Journal exit classification must not depend exclusively on Bitunix's
# reduceOnly flag. Protection order identity and opposite-side fills are also
# authoritative for an already-owned position.
observer = ROOT / 'lib/features/trading_journal/application/local_live_journal_observer.dart'
text = observer.read_text(encoding='utf-8')
text = text.replace(
    """    final exitFills = fills.where((fill) => fill.reduceOnly).toList();
""",
    """    final exitFills = fills
        .where((fill) => _isExitFill(managed: managed, fill: fill))
        .toList();
""",
    1,
)
text = text.replace(
    """    for (final fill in fills) {
      if (fill.reduceOnly) cumulativeExitQuantity += fill.quantity;
      final targetIndex = managed.targetOrderIds.indexOf(fill.orderId);
      final isTarget = targetIndex >= 0;
      final isFinalExit = fill.reduceOnly && fill.tradeId == finalExitTradeId;
""",
    """    for (final fill in fills) {
      final isExit = _isExitFill(managed: managed, fill: fill);
      if (isExit) cumulativeExitQuantity += fill.quantity;
      final targetIndex = managed.targetOrderIds.indexOf(fill.orderId);
      final isTarget = targetIndex >= 0;
      final isFinalExit = isExit && fill.tradeId == finalExitTradeId;
""",
    1,
)
text = text.replace(
    """          type: !fill.reduceOnly
              ? TradingJournalEventType.entryPartiallyFilled
              : isTarget
""",
    """          type: !isExit
              ? TradingJournalEventType.entryPartiallyFilled
              : isTarget
""",
    1,
)
needle = """  static TradingJournalCloseReason _closeReasonForFill({
"""
helper = """  static bool _isExitFill({
    required LocalLiveManagedPosition managed,
    required ExchangePnlFill fill,
  }) {
    if (fill.reduceOnly) return true;
    if (managed.targetOrderIds.contains(fill.orderId)) return true;
    if (managed.stopOrderId != null && fill.orderId == managed.stopOrderId) {
      return true;
    }
    final side = fill.side.trim().toUpperCase();
    return switch (managed.direction) {
      TradeDirection.long => side == 'SELL',
      TradeDirection.short => side == 'BUY',
      TradeDirection.wait => false,
    };
  }

  Future<void> recordExchangeClosureObserved({
    required LocalLiveManagedPosition managed,
    required bool closedHistoryAvailable,
    DateTime? observedAt,
  }) {
    final at = (observedAt ?? DateTime.now()).toUtc();
    return _append(
      TradingJournalEvent(
        eventId: 'exchange-close-observed:${managed.positionId}',
        journalTradeId: journalTradeId(managed.positionId),
        type: TradingJournalEventType.positionClosed,
        occurredAt: at,
        recordedAt: at,
        source: TradingJournalFactSource.exchange,
        quality: TradingJournalFactQuality.confirmed,
        scope: TradingJournalScope.position,
        currency: 'USDT',
        asOf: at,
        exchangeEventId: 'exchange-close-observed:${managed.positionId}',
        positionId: managed.positionId,
        remainingQuantity: 0,
        details: {
          'closeReason': TradingJournalCloseReason.unknown.name,
          'economicsPending': true,
          'closedHistoryAvailable': closedHistoryAvailable,
          'message':
              'Bitunix no longer reports this position as open. Final fill-level economics and close classification are being reconciled.',
        },
      ),
    );
  }

"""
if text.count(needle) != 1:
    raise RuntimeError('observer helper insertion point not unique')
observer.write_text(text.replace(needle, helper + needle, 1), encoding='utf-8')

# 4) Mark exchange closure in the journal immediately even if fill-level PnL is
# still pending. This prevents the UI from claiming the trade is open.
service = ROOT / 'lib/features/auto_trade/application/local_live_trade_service.dart'
replace_once(
    service,
    """        if (!journalReconciled &&
            !_pendingJournalClosures.any(
              (item) => item.positionId == managed.positionId,
            )) {
          _pendingJournalClosures.add(managed);
        }
""",
    """        if (!journalReconciled) {
          await _journalObserver.recordExchangeClosureObserved(
            managed: managed,
            closedHistoryAvailable: closedHistoryAvailable,
          );
          if (!_pendingJournalClosures.any(
            (item) => item.positionId == managed.positionId,
          )) {
            _pendingJournalClosures.add(managed);
          }
        }
""",
    'immediate exchange closure journal fact',
)

# 5) Include the complete immutable journal plan/events in the sanitized Local
# Live diagnostic export. This gives support the strategy, timeframe,
# confidence/confluence, risk, leverage and lifecycle facts without credentials.
page = ROOT / 'lib/features/owner_alpha/presentation/owner_alpha_page.dart'
replace_once(
    page,
    """import '../../trading_journal/data/database_trading_journal_store.dart';
""",
    """import '../../trading_journal/data/database_trading_journal_store.dart';
import '../../trading_journal/data/trading_journal_store.dart';
""",
    'journal mirror import',
)

tools = ROOT / 'lib/features/owner_alpha/presentation/owner_alpha_local_live_tools.dart'
replace_once(
    tools,
    """      final persisted = <String, Object?>{
""",
    """      final journalLedger = await SharedPreferencesTradingJournalStore().load();
      final persisted = <String, Object?>{
""",
    'load journal mirror for diagnostics',
)
replace_once(
    tools,
    """          'auditEvents': events.map((item) => item.toJson()).toList(),
          'persistedLocalServiceState': persisted,
""",
    """          'auditEvents': events.map((item) => item.toJson()).toList(),
          'tradingJournal': journalLedger.toJson(),
          'persistedLocalServiceState': persisted,
""",
    'journal diagnostics section',
)

# Regression/source tests.
test = ROOT / 'test/issue_170_journal_closure_test.dart'
test.write_text(r'''import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/auto_trade/domain/trading_pnl_projection.dart';

void main() {
  test('closed position can verify from complete local evidence despite unrelated source warning', () {
    final now = DateTime.utc(2026, 8, 7, 15, 0);
    final projection = TradingPnlProjection.reconcile(
      currency: 'USDT',
      asOf: now,
      unrealizedByPosition: const {},
      fills: [
        ExchangePnlFill(
          tradeId: 'entry',
          orderId: 'entry-order',
          positionId: 'p1',
          symbol: 'SOLUSDT',
          quantity: 0.23,
          price: 74,
          realizedPnl: 0,
          fee: 0.010212,
          reduceOnly: false,
          occurredAt: now.subtract(const Duration(minutes: 25)),
          side: 'BUY',
        ),
        ExchangePnlFill(
          tradeId: 'exit',
          orderId: 'stop-order',
          positionId: 'p1',
          symbol: 'SOLUSDT',
          quantity: 0.23,
          price: 73.62,
          realizedPnl: -0.0874,
          fee: 0.01015956,
          reduceOnly: true,
          occurredAt: now,
          side: 'SELL',
        ),
      ],
      settlements: [
        ExchangePositionSettlement(
          positionId: 'p1',
          symbol: 'SOLUSDT',
          funding: 0,
          realizedPnl: -0.0874,
          fee: 0.02037156,
          openedAt: now.subtract(const Duration(minutes: 25)),
          closedAt: now,
        ),
      ],
      sourceVerified: false,
      warning: 'An unrelated historical trade was ambiguous.',
    );
    final position = projection.forPositionId('p1');
    expect(position, isNotNull);
    expect(position!.isVerified, isTrue);
    expect(position.netRealized.value, closeTo(-0.10777156, 0.00000001));
  });

  test('journal source hardens closure and diagnostic export', () {
    final observer = File(
      'lib/features/trading_journal/application/local_live_journal_observer.dart',
    ).readAsStringSync();
    final service = File(
      'lib/features/auto_trade/application/local_live_trade_service.dart',
    ).readAsStringSync();
    final store = File(
      'lib/features/trading_journal/data/database_trading_journal_store.dart',
    ).readAsStringSync();
    final tools = File(
      'lib/features/owner_alpha/presentation/owner_alpha_local_live_tools.dart',
    ).readAsStringSync();

    expect(observer, contains('_isExitFill'));
    expect(observer, contains("TradeDirection.long => side == 'SELL'"));
    expect(observer, contains('recordExchangeClosureObserved'));
    expect(service, contains('recordExchangeClosureObserved'));
    expect(store, contains('final candidate = merged.appendEvent(event)'));
    expect(tools, contains("'tradingJournal': journalLedger.toJson()"));
  });
}
''', encoding='utf-8')
