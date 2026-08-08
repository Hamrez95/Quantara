from pathlib import Path

ROOT = Path('src/client/quantara_app')


def replace_once(path: Path, old: str, new: str, label: str) -> None:
    text = path.read_text(encoding='utf-8')
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f'{label}: expected one match, found {count}')
    path.write_text(text.replace(old, new, 1), encoding='utf-8')

# Stage 2: legacy exchange backfill must operate per position/trade. A stale
# unrelated ledger warning is data-quality metadata; it must not keep a
# confirmed exchange-closed trade open.
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
start = """  static bool _isVerifiedClosedPosition(
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

"""
replacement = """  static bool _isVerifiedClosedPosition(
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

"""
replace_once(backfill, start, replacement, 'verified close evidence rules')

# Trade lifecycle state is position-scoped. A global ledger warning remains
# visible through integrity/warning but does not turn an exchange-confirmed
# CLOSED trade back into an Unverified/Open-looking lifecycle state.
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

# Diagnostic export must read the durable journal authority rather than the
# rollback/foreground mirror.
tools = ROOT / 'lib/features/owner_alpha/presentation/owner_alpha_local_live_tools.dart'
replace_once(
    tools,
    """      final journalLedger = await SharedPreferencesTradingJournalStore().load();
""",
    """      final journalLedger = await DatabaseTradingJournalStore().load();
""",
    'durable journal diagnostic source',
)
page = ROOT / 'lib/features/owner_alpha/presentation/owner_alpha_page.dart'
replace_once(
    page,
    """import '../../trading_journal/data/trading_journal_store.dart';
""",
    """,
    'remove temporary mirror import',
)

# Recursive secret sanitizer: protect prefixed/suffixed credential keys too,
# including future support-session tokens and request signatures.
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
text = diag.read_text(encoding='utf-8')
old = r"refresh\s*[_-]?\s*token)\s*[:=]"
new = r"refresh\s*[_-]?\s*token|session\s*[_-]?\s*token|private\s*[_-]?\s*key|request\s*[_-]?\s*signature|signature)\s*[:=]"
if text.count(old) != 1:
    raise RuntimeError(f'diagnostic string sanitizer: expected one match, found {text.count(old)}')
diag.write_text(text.replace(old, new, 1), encoding='utf-8')

# Behavioral regressions for Bitunix rows where reduceOnly is missing/false and
# for unrelated legacy ledger warnings.
backfill_test = ROOT / 'test/trading_journal_exchange_backfill_test.dart'
replace_once(
    backfill_test,
    """}\n\nTradingPnlProjection _verifiedPnl() => TradingPnlProjection.reconcile(
""",
    """  test('closes from opposite-side stop fill when reduceOnly is false', () {
    final ledger = TradingJournalLedger.empty()
        .appendPlan(_plan())
        .appendEvent(_entry());
    final result = TradingJournalExchangeBackfill.reconcileVerifiedClosures(
      ledger: ledger,
      pnlProjection: _verifiedPnl(reduceOnly: false),
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
  });

  test('unrelated legacy ledger warning cannot keep verified trade open', () {
    final ledger = TradingJournalLedger.empty()
        .appendPlan(_plan())
        .appendEvent(_entry())
        .withIntegrityWarning('Legacy warning for unrelated trade.');
    final result = TradingJournalExchangeBackfill.reconcileVerifiedClosures(
      ledger: ledger,
      pnlProjection: _verifiedPnl(),
      openPositionIds: const {},
      recordedAt: DateTime.utc(2026, 8, 5, 5),
    );
    final projection = TradingJournalProjector.project(
      ledger: result.ledger,
      journalTradeId: 'local-live:gram-position',
    );

    expect(result.closedTradeIds, ['local-live:gram-position']);
    expect(projection.state, TradingJournalTradeState.closed);
    expect(projection.integrity, TradingJournalIntegrity.unverified);
    expect(result.ledger.warnings, contains('Legacy warning for unrelated trade.'));
  });
}\n\nTradingPnlProjection _verifiedPnl({bool reduceOnly = true}) => TradingPnlProjection.reconcile(
""",
    'issue170 backfill behavioral tests',
)
replace_once(
    backfill_test,
    """      reduceOnly: true,
      occurredAt: DateTime.utc(2026, 8, 5, 3, 19, 14),
      side: 'SELL',
""",
    """      reduceOnly: reduceOnly,
      occurredAt: DateTime.utc(2026, 8, 5, 3, 19, 14),
      side: 'SELL',
""",
    'parameterize reduceOnly backfill fixture',
)

# Sanitizer regression for prefixed future keys and nested session tokens.
diag_test = ROOT / 'test/local_live_diagnostic_bundle_test.dart'
replace_once(
    diag_test,
    """            'nested': {
              'Authorization': 'Bearer token-value',
              'safe': 'BTCUSDT',
            },
""",
    """            'nested': {
              'Authorization': 'Bearer token-value',
              'bitunixApiKey': 'prefixed-key-value',
              'exchangeApiSecret': 'prefixed-secret-value',
              'supportSessionToken': 'support-session-value',
              'requestSignature': 'signed-request-value',
              'safe': 'BTCUSDT',
            },
""",
    'nested prefixed secret fixture',
)
replace_once(
    diag_test,
    """      expect(encoded, isNot(contains('dXNlcjpwYXNz')));
      expect(encoded, isNot(contains('secretKey')));
      expect(encoded, contains('BTCUSDT'));
""",
    """      expect(encoded, isNot(contains('dXNlcjpwYXNz')));
      expect(encoded, isNot(contains('prefixed-key-value')));
      expect(encoded, isNot(contains('prefixed-secret-value')));
      expect(encoded, isNot(contains('support-session-value')));
      expect(encoded, isNot(contains('signed-request-value')));
      expect(encoded, isNot(contains('secretKey')));
      expect(encoded, contains('BTCUSDT'));
""",
    'prefixed secret assertions',
)
