from pathlib import Path

ROOT = Path('src/client/quantara_app')


def replace_once(path: Path, old: str, new: str, label: str) -> None:
    text = path.read_text(encoding='utf-8')
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f'{label}: expected one match, found {count}')
    path.write_text(text.replace(old, new, 1), encoding='utf-8')


# Legacy exchange backfill is position-scoped. An unrelated old ledger warning
# must not keep an exchange-confirmed closed position open.
backfill = ROOT / 'lib/features/trading_journal/application/trading_journal_exchange_backfill.dart'
replace_once(
    backfill,
    """    if (ledger.integrity == TradingJournalIntegrity.unverified ||
        !pnlProjection.fillsAvailable ||
        !pnlProjection.settlementsAvailable) {
""",
    """    if (!pnlProjection.fillsAvailable ||
        !pnlProjection.settlementsAvailable) {
""",
    'allow position-scoped legacy backfill',
)
replace_once(
    backfill,
    """      final exits = [...position!.exitFills]
        ..sort((left, right) => left.occurredAt.compareTo(right.occurredAt));
""",
    """      final exits = position!.fills
          .where((fill) => _isExitFill(plan, fill))
          .toList(growable: false)
        ..sort((left, right) => left.occurredAt.compareTo(right.occurredAt));
""",
    'derive exits without reduceOnly dependency',
)
replace_once(
    backfill,
    """      if (appended.integrity == TradingJournalIntegrity.unverified) {
        return TradingJournalExchangeBackfillResult(
          ledger: ledger,
          closedTradeIds: const [],
        );
      }
      next = appended;
      closedTradeIds.add(plan.journalTradeId);
""",
    """      final introducedWarning = appended.warnings.length > next.warnings.length;
      final introducedUnverified =
          next.integrity != TradingJournalIntegrity.unverified &&
          appended.integrity == TradingJournalIntegrity.unverified;
      if (introducedWarning || introducedUnverified) {
        continue;
      }
      next = appended;
      closedTradeIds.add(plan.journalTradeId);
""",
    'reject only newly ambiguous backfill facts',
)
replace_once(
    backfill,
    """  static bool _isVerifiedClosedPosition(
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

""",
    """  static bool _isVerifiedClosedPosition(
    PositionPnlProjection? position,
    TradingJournalPlan plan,
  ) {
    if (position == null ||
        !position.isVerified ||
        position.settlement == null ||
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
    final exits = position.fills
        .where((fill) => _isExitFill(plan, fill))
        .toList(growable: false);
    if (exits.isEmpty) return false;
    return exits.every(
      (fill) =>
          fill.positionId.trim() == position.positionId.trim() &&
          fill.tradeId.trim().isNotEmpty &&
          fill.quantity.isFinite &&
          fill.quantity > 0 &&
          fill.price.isFinite &&
          fill.price > 0,
    );
  }

  static bool _isExitFill(
    TradingJournalPlan plan,
    ExchangePnlFill fill,
  ) {
    if (fill.reduceOnly) return true;
    final side = fill.side.trim().toUpperCase();
    return switch (plan.direction) {
      TradingJournalDirection.long => side == 'SELL',
      TradingJournalDirection.short => side == 'BUY',
      TradingJournalDirection.wait => false,
    };
  }

""",
    'verified close evidence rules',
)

# Lifecycle truth is scoped to the trade. Global journal integrity remains
# visible as data quality, but must not turn an exchange-confirmed close into an
# Open/Unverified lifecycle state.
projector = ROOT / 'lib/features/trading_journal/domain/trading_journal_projection.dart'
replace_once(
    projector,
    """    if (ledger.integrity == TradingJournalIntegrity.unverified ||
        timeline.any(
          (item) => item.quality == TradingJournalFactQuality.unverified,
        )) {
      return TradingJournalTradeState.unverified;
    }
    if (hasClose) return TradingJournalTradeState.closed;
    if (hasEntry) return TradingJournalTradeState.open;
""",
    """    if (timeline.any(
      (item) => item.quality == TradingJournalFactQuality.unverified,
    )) {
      return TradingJournalTradeState.unverified;
    }
    if (hasClose) return TradingJournalTradeState.closed;
    if (hasEntry) return TradingJournalTradeState.open;
    if (ledger.integrity == TradingJournalIntegrity.unverified) {
      return TradingJournalTradeState.unverified;
    }
""",
    'position lifecycle before global data quality',
)

# Export the durable journal authority, not the foreground rollback mirror.
tools = ROOT / 'lib/features/owner_alpha/presentation/owner_alpha_local_live_tools.dart'
replace_once(
    tools,
    "      final journalLedger = await SharedPreferencesTradingJournalStore().load();\n",
    "      final journalLedger = await DatabaseTradingJournalStore().load();\n",
    'durable journal diagnostic source',
)
page = ROOT / 'lib/features/owner_alpha/presentation/owner_alpha_page.dart'
replace_once(
    page,
    "import '../../trading_journal/data/trading_journal_store.dart';\n",
    '',
    'remove foreground mirror import',
)

# Recursive sanitizer also catches prefixed/suffixed future credential keys.
diag = ROOT / 'lib/features/auto_trade/application/local_live_diagnostic_bundle.dart'
replace_once(
    diag,
    """  static bool _sensitiveKey(String key) {
    final normalized = key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    return const {
      'apikey',
      'apisecret',
      'secretkey',
      'secret',
      'authorization',
      'password',
      'accesstoken',
      'refreshtoken',
      'credentials',
      'credential',
      'privatekey',
      'signature',
    }.contains(normalized);
  }
""",
    """  static bool _sensitiveKey(String key) {
    final normalized = key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    const exact = {
      'secret',
      'authorization',
      'password',
      'credentials',
      'credential',
      'signature',
    };
    if (exact.contains(normalized)) return true;
    const sensitiveSuffixes = {
      'apikey',
      'apisecret',
      'secretkey',
      'password',
      'accesstoken',
      'refreshtoken',
      'sessiontoken',
      'credentials',
      'credential',
      'privatekey',
      'signature',
    };
    return sensitiveSuffixes.any(normalized.endsWith);
  }
""",
    'prefixed credential keys',
)
replace_once(
    diag,
    r"refresh\s*[_-]?\s*token)\s*[:=]",
    r"refresh\s*[_-]?\s*token|session\s*[_-]?\s*token|private\s*[_-]?\s*key|request\s*[_-]?\s*signature|signature)\s*[:=]",
    'credential-like string sanitizer',
)

# Dedicated regressions avoid weakening or rewriting existing safety tests.
(ROOT / 'test/issue_170_legacy_backfill_regression_test.dart').write_text(r'''import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/auto_trade/domain/trading_pnl_projection.dart';
import 'package:quantara_app/features/trading_journal/application/trading_journal_exchange_backfill.dart';
import 'package:quantara_app/features/trading_journal/domain/trading_journal_models.dart';
import 'package:quantara_app/features/trading_journal/domain/trading_journal_projection.dart';

void main() {
  test('opposite-side Bitunix stop fill closes even when reduceOnly is false', () {
    final result = TradingJournalExchangeBackfill.reconcileVerifiedClosures(
      ledger: TradingJournalLedger.empty().appendPlan(_plan()).appendEvent(_entry()),
      pnlProjection: _pnl(reduceOnly: false),
      openPositionIds: const {},
      recordedAt: DateTime.utc(2026, 8, 7, 15, 30),
    );
    final projection = TradingJournalProjector.project(
      ledger: result.ledger,
      journalTradeId: 'local-live:sol-position',
    );

    expect(result.closedTradeIds, ['local-live:sol-position']);
    expect(projection.state, TradingJournalTradeState.closed);
    expect(projection.closeReason, TradingJournalCloseReason.stop);
    expect(projection.netPnl, closeTo(-0.10777156, 0.00000001));
  });

  test('unrelated legacy journal warning cannot keep confirmed SOL close open', () {
    final ledger = TradingJournalLedger.empty()
        .appendPlan(_plan())
        .appendEvent(_entry())
        .withIntegrityWarning('Legacy warning for an unrelated historical trade.');
    final result = TradingJournalExchangeBackfill.reconcileVerifiedClosures(
      ledger: ledger,
      pnlProjection: _pnl(),
      openPositionIds: const {},
      recordedAt: DateTime.utc(2026, 8, 7, 15, 30),
    );
    final projection = TradingJournalProjector.project(
      ledger: result.ledger,
      journalTradeId: 'local-live:sol-position',
    );

    expect(result.closedTradeIds, ['local-live:sol-position']);
    expect(projection.state, TradingJournalTradeState.closed);
    expect(projection.integrity, TradingJournalIntegrity.unverified);
    expect(result.ledger.warnings, contains('Legacy warning for an unrelated historical trade.'));
  });
}

TradingPnlProjection _pnl({bool reduceOnly = true}) => TradingPnlProjection.reconcile(
  currency: 'USDT',
  asOf: DateTime.utc(2026, 8, 7, 15, 25),
  unrealizedByPosition: const {},
  fills: [
    ExchangePnlFill(
      tradeId: 'sol-stop-fill',
      orderId: 'sol-stop-order',
      positionId: 'sol-position',
      symbol: 'SOLUSDT',
      quantity: 0.23,
      price: 73.62,
      realizedPnl: -0.0874,
      fee: 0.02037156,
      reduceOnly: reduceOnly,
      occurredAt: DateTime.utc(2026, 8, 7, 15, 25),
      side: 'SELL',
    ),
  ],
  settlements: [
    ExchangePositionSettlement(
      positionId: 'sol-position',
      symbol: 'SOLUSDT',
      funding: 0,
      openedAt: DateTime.utc(2026, 8, 7, 15),
      closedAt: DateTime.utc(2026, 8, 7, 15, 25),
      realizedPnl: -0.0874,
      fee: 0.02037156,
    ),
  ],
);

TradingJournalPlan _plan() => TradingJournalPlan(
  journalTradeId: 'local-live:sol-position',
  setupId: 'sol-5m-trend-pullback',
  analysisVersion: 'v1',
  symbol: 'SOLUSDT',
  market: 'USDT_PERPETUAL',
  timeframe: '5m',
  direction: TradingJournalDirection.long,
  strategy: 'trendPullback',
  cadence: 'local-live',
  source: TradingJournalSource.localLive,
  decidedAt: DateTime.utc(2026, 8, 7, 15),
  decisionPrice: 74.00,
  entryLower: 74.00,
  entryUpper: 74.00,
  plannedEntry: 74.00,
  originalStopLoss: 73.69,
  targets: const [74.9022],
  expectedRMultiples: const [1],
  confidencePercent: 70,
  confluence: const ['trendPullback'],
  regime: 'trend',
  rationale: 'physical SOL canary',
  invalidation: 'planned stop',
  accountEquity: 29.81,
  riskPercent: 0.1,
  riskBudget: 0.10,
  leverage: 10,
  expectedMargin: 1.702,
  passedGates: const ['isolated-margin', 'protection-ready'],
  blockedGates: const [],
  appVersion: '1.2.0-rc.2',
  strategyRulesVersion: 'v1',
  positionId: 'sol-position',
  entryOrderId: 'sol-entry-order',
  clientId: 'q-local-sol',
);

TradingJournalEvent _entry() => TradingJournalEvent(
  eventId: 'sol-entry',
  journalTradeId: 'local-live:sol-position',
  type: TradingJournalEventType.entryFilled,
  occurredAt: DateTime.utc(2026, 8, 7, 15),
  recordedAt: DateTime.utc(2026, 8, 7, 15),
  source: TradingJournalFactSource.exchange,
  quality: TradingJournalFactQuality.confirmed,
  scope: TradingJournalScope.position,
  currency: 'USDT',
  asOf: DateTime.utc(2026, 8, 7, 15),
  positionId: 'sol-position',
  orderId: 'sol-entry-order',
  quantity: 0.23,
  price: 74.00,
  remainingQuantity: 0.23,
);
''', encoding='utf-8')

(ROOT / 'test/issue_170_diagnostic_sanitizer_regression_test.dart').write_text(r'''import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/auto_trade/application/local_live_diagnostic_bundle.dart';

void main() {
  test('prefixed credential and support-session keys never leak', () {
    final encoded = LocalLiveDiagnosticBundle.encode(
      generatedAt: DateTime.utc(2026, 8, 8),
      sections: const {
        'nested': {
          'bitunixApiKey': 'bitunix-key-leak',
          'exchangeApiSecret': 'exchange-secret-leak',
          'supportSessionToken': 'support-token-leak',
          'requestSignature': 'signature-leak',
          'safeSymbol': 'SOLUSDT',
        },
        'messages': [
          'session_token=support-token-in-string',
          'request_signature=signed-string',
          'safe diagnostic',
        ],
      },
    );

    for (final secret in const [
      'bitunix-key-leak',
      'exchange-secret-leak',
      'support-token-leak',
      'signature-leak',
      'support-token-in-string',
      'signed-string',
    ]) {
      expect(encoded, isNot(contains(secret)));
    }
    expect(encoded, contains('SOLUSDT'));
    expect(encoded, contains('safe diagnostic'));
  });
}
''', encoding='utf-8')
