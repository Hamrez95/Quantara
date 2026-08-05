from pathlib import Path

ROOT = Path("src/client/quantara_app")


def replace_exact(path: Path, old: str, new: str, count: int = 1) -> None:
    text = path.read_text()
    actual = text.count(old)
    if actual != count:
        raise SystemExit(
            f"{path}: expected {count} occurrences, found {actual}: {old[:120]!r}"
        )
    path.write_text(text.replace(old, new, count))


mapper = ROOT / "lib/features/auto_trade/data/bitunix_pnl_mapper.dart"
replace_exact(
    mapper,
    "  static const _minimumNearestSeparation = Duration(seconds: 5);\n",
    "  static const _minimumNearestSeparation = Duration(seconds: 5);\n"
    "  static const unassignedPositionPrefix = 'unassigned-trade:';\n",
)
marker = "  static BitunixPnlParseResult<ExchangePnlFill> fills(\n"
text = mapper.read_text()
start = text.index(marker)
head, tail = text[:start], text[start:]
old = "    final values = <ExchangePnlFill>[];\n    final warnings = <String>[];\n"
if tail.count(old) != 1:
    raise SystemExit("mapper fills warning declaration changed")
tail = tail.replace(
    old,
    "    final values = <ExchangePnlFill>[];\n"
    "    final warnings = <String>[];\n"
    "    final attributionWarnings = <String>[];\n",
    1,
)
old = (
    "      if (resolved == null) {\n"
    "        warnings.add(\n"
    "          'Trade $tradeId could not be assigned to one exchange position.',\n"
    "        );\n"
    "      }\n"
)
if tail.count(old) != 1:
    raise SystemExit("mapper unresolved warning block changed")
tail = tail.replace(
    old,
    "      if (resolved == null) {\n"
    "        attributionWarnings.add(\n"
    "          'Trade $tradeId could not be assigned to one exchange position.',\n"
    "        );\n"
    "      }\n",
    1,
)
old = "          positionId: resolved ?? '',\n"
if tail.count(old) != 1:
    raise SystemExit("mapper position assignment changed")
tail = tail.replace(
    old,
    "          positionId:\n"
    "              resolved ?? '$unassignedPositionPrefix$tradeId',\n",
    1,
)
old = (
    "    return BitunixPnlParseResult(\n"
    "      values: List.unmodifiable(values),\n"
    "      verified: warnings.isEmpty,\n"
    "      warning: warnings.isEmpty ? null : warnings.toSet().join(' '),\n"
    "    );\n"
)
if tail.count(old) != 1:
    raise SystemExit("mapper fills result block changed")
tail = tail.replace(
    old,
    "    final allWarnings = [...warnings, ...attributionWarnings];\n"
    "    return BitunixPnlParseResult(\n"
    "      values: List.unmodifiable(values),\n"
    "      verified: warnings.isEmpty,\n"
    "      warning: allWarnings.isEmpty\n"
    "          ? null\n"
    "          : allWarnings.toSet().join(' '),\n"
    "    );\n",
    1,
)
mapper.write_text(head + tail)

pnl = ROOT / "lib/features/auto_trade/domain/trading_pnl_projection.dart"
replace_exact(
    pnl,
    "      final positionConflict = conflicts.any(\n"
    "        (item) =>\n"
    "            positionFills.any((fill) => fill.tradeId == item) ||\n"
    "            item == 'settlement:$key' ||\n"
    "            item == 'missing tradeId',\n"
    "      );\n"
    "      final verified = !positionConflict && sourceVerified;\n",
    "      final unassignedAttribution = key.startsWith(\n"
    "        'unassigned-trade:',\n"
    "      );\n"
    "      final positionConflict =\n"
    "          unassignedAttribution ||\n"
    "          conflicts.any(\n"
    "            (item) =>\n"
    "                positionFills.any((fill) => fill.tradeId == item) ||\n"
    "                item == 'settlement:$key' ||\n"
    "                item == 'missing tradeId',\n"
    "          );\n"
    "      final verified = !positionConflict && sourceVerified;\n",
)
replace_exact(
    pnl,
    "      final positionWarning = totalsMismatch\n"
    "          ? 'Trade-history totals diverge from the Bitunix position totals.'\n"
    "          : positionConflict\n"
    "          ? 'Conflicting exchange event identity for $key.'\n"
    "          : warning;\n",
    "      final positionWarning = unassignedAttribution\n"
    "          ? 'A valid exchange trade remains quarantined because it could not be assigned to one position.'\n"
    "          : totalsMismatch\n"
    "          ? 'Trade-history totals diverge from the Bitunix position totals.'\n"
    "          : positionConflict\n"
    "          ? 'Conflicting exchange event identity for $key.'\n"
    "          : warning;\n",
)
replace_exact(
    pnl,
    "      sourceVerified: isVerified,\n"
    "      stale: positions.any(\n",
    "      sourceVerified: includedPositions.every(\n"
    "        (position) => position.isVerified,\n"
    "      ),\n"
    "      stale: includedPositions.any(\n",
)

backfill = (
    ROOT
    / "lib/features/trading_journal/application/trading_journal_exchange_backfill.dart"
)
replace_exact(
    backfill,
    "    if (ledger.integrity == TradingJournalIntegrity.unverified ||\n"
    "        !pnlProjection.isVerified ||\n"
    "        !pnlProjection.fillsAvailable ||\n",
    "    if (ledger.integrity == TradingJournalIntegrity.unverified ||\n"
    "        !pnlProjection.fillsAvailable ||\n",
)

observer = (
    ROOT / "lib/features/trading_journal/application/local_live_journal_observer.dart"
)
replace_exact(
    observer,
    "    for (var index = 0; index < managed.targetOrderIds.length; index++) {\n"
    "      final orderId = managed.targetOrderIds[index];\n"
    "      await _append(\n",
    "    for (var index = 0; index < managed.targetOrderIds.length; index++) {\n"
    "      final orderId = managed.targetOrderIds[index];\n"
    "      final quantity = managed.targetQuantities[index];\n"
    "      if (orderId.trim().isEmpty || quantity <= 0) continue;\n"
    "      await _append(\n",
)
replace_exact(
    observer,
    "          quantity: managed.targetQuantities[index],\n"
    "          price: managed.targets[index],\n",
    "          quantity: quantity,\n"
    "          price: managed.targets[index],\n",
    count=1,
)
replace_exact(
    observer,
    "    for (var index = 0; index < managed.targetOrderIds.length; index++) {\n"
    "      await _append(\n"
    "        TradingJournalEvent(\n"
    "          eventId: 'recovered-tp:${managed.targetOrderIds[index]}',\n",
    "    for (var index = 0; index < managed.targetOrderIds.length; index++) {\n"
    "      final orderId = managed.targetOrderIds[index];\n"
    "      final quantity = managed.targetQuantities[index];\n"
    "      if (orderId.trim().isEmpty || quantity <= 0) continue;\n"
    "      await _append(\n"
    "        TradingJournalEvent(\n"
    "          eventId: 'recovered-tp:$orderId',\n",
)
replace_exact(
    observer,
    "          exchangeEventId: 'tp-order:${managed.targetOrderIds[index]}',\n"
    "          positionId: managed.positionId,\n"
    "          orderId: managed.targetOrderIds[index],\n"
    "          quantity: managed.targetQuantities[index],\n",
    "          exchangeEventId: 'tp-order:$orderId',\n"
    "          positionId: managed.positionId,\n"
    "          orderId: orderId,\n"
    "          quantity: quantity,\n",
)

models = ROOT / "lib/features/trading_journal/domain/trading_journal_models.dart"
replace_exact(
    models,
    "  bool sameEconomicEvent(TradingJournalEvent other) =>\n"
    "      journalTradeId == other.journalTradeId &&\n"
    "      type == other.type &&\n"
    "      occurredAt.toUtc() == other.occurredAt.toUtc() &&\n"
    "      source == other.source &&\n"
    "      quality == other.quality &&\n"
    "      scope == other.scope &&\n"
    "      currency == other.currency &&\n"
    "      exchangeEventId == other.exchangeEventId &&\n"
    "      positionId == other.positionId &&\n"
    "      orderId == other.orderId &&\n"
    "      clientId == other.clientId &&\n"
    "      tradeId == other.tradeId &&\n"
    "      quantity == other.quantity &&\n"
    "      price == other.price &&\n"
    "      grossPnl == other.grossPnl &&\n"
    "      fee == other.fee &&\n"
    "      funding == other.funding &&\n"
    "      remainingQuantity == other.remainingQuantity &&\n"
    "      _deepEquals(details, other.details);\n",
    "  bool sameEconomicEvent(TradingJournalEvent other) {\n"
    "    final replayableProtectionConfirmation =\n"
    "        type == other.type &&\n"
    "        (type == TradingJournalEventType.stopConfirmed ||\n"
    "            type == TradingJournalEventType.takeProfitConfirmed);\n"
    "    return journalTradeId == other.journalTradeId &&\n"
    "        type == other.type &&\n"
    "        (replayableProtectionConfirmation ||\n"
    "            occurredAt.toUtc() == other.occurredAt.toUtc()) &&\n"
    "        source == other.source &&\n"
    "        quality == other.quality &&\n"
    "        scope == other.scope &&\n"
    "        currency == other.currency &&\n"
    "        exchangeEventId == other.exchangeEventId &&\n"
    "        positionId == other.positionId &&\n"
    "        orderId == other.orderId &&\n"
    "        clientId == other.clientId &&\n"
    "        tradeId == other.tradeId &&\n"
    "        quantity == other.quantity &&\n"
    "        price == other.price &&\n"
    "        grossPnl == other.grossPnl &&\n"
    "        fee == other.fee &&\n"
    "        funding == other.funding &&\n"
    "        remainingQuantity == other.remainingQuantity &&\n"
    "        _deepEquals(details, other.details);\n"
    "  }\n",
)
replace_exact(
    models,
    "  TradingJournalLedger withRecoveryWarning(String warning) => _copy(\n",
    "  TradingJournalLedger repairKnownProtectionReplayConflicts() {\n"
    "    if (warnings.isEmpty) return this;\n"
    "    final remainingWarnings = <String>[];\n"
    "    var repaired = false;\n"
    "    const prefix = 'Conflicting journal event identity ';\n"
    "    for (final warning in warnings) {\n"
    "      if (!warning.startsWith(prefix)) {\n"
    "        remainingWarnings.add(warning);\n"
    "        continue;\n"
    "      }\n"
    "      var identity = warning.substring(prefix.length).trim();\n"
    "      if (identity.endsWith('.')) {\n"
    "        identity = identity.substring(0, identity.length - 1);\n"
    "      }\n"
    "      final protectionIdentity =\n"
    "          identity.startsWith('exchange:tp-order:') ||\n"
    "          identity.startsWith('exchange:stop-order:');\n"
    "      final matching = events.where(\n"
    "        (event) =>\n"
    "            event.economicIdentity == identity &&\n"
    "            (event.type == TradingJournalEventType.takeProfitConfirmed ||\n"
    "                event.type == TradingJournalEventType.stopConfirmed),\n"
    "      );\n"
    "      if (protectionIdentity && matching.length == 1) {\n"
    "        repaired = true;\n"
    "      } else {\n"
    "        remainingWarnings.add(warning);\n"
    "      }\n"
    "    }\n"
    "    if (!repaired) return this;\n"
    "    return _copy(\n"
    "      generation: generation + 1,\n"
    "      integrity: remainingWarnings.isEmpty\n"
    "          ? TradingJournalIntegrity.verified\n"
    "          : TradingJournalIntegrity.unverified,\n"
    "      warnings: remainingWarnings,\n"
    "    );\n"
    "  }\n\n"
    "  TradingJournalLedger withRecoveryWarning(String warning) => _copy(\n",
)
old_factory = """  factory TradingJournalLedger.fromJson(Map<String, Object?> json) =>
      TradingJournalLedger._(
        schemaVersion: _int(json['schemaVersion'], fallback: 1),
        generation: _int(json['generation']),
        plans: List.unmodifiable(
          _mapList(json['plans']).map(TradingJournalPlan.fromJson),
        ),
        events: List.unmodifiable(
          _mapList(json['events']).map(TradingJournalEvent.fromJson),
        ),
        integrity: _enumValue(
          TradingJournalIntegrity.values,
          json['integrity'],
          TradingJournalIntegrity.unverified,
        ),
        warnings: List.unmodifiable(_stringList(json['warnings'])),
      );
"""
new_factory = """  factory TradingJournalLedger.fromJson(Map<String, Object?> json) {
    final ledger = TradingJournalLedger._(
      schemaVersion: _int(json['schemaVersion'], fallback: 1),
      generation: _int(json['generation']),
      plans: List.unmodifiable(
        _mapList(json['plans']).map(TradingJournalPlan.fromJson),
      ),
      events: List.unmodifiable(
        _mapList(json['events']).map(TradingJournalEvent.fromJson),
      ),
      integrity: _enumValue(
        TradingJournalIntegrity.values,
        json['integrity'],
        TradingJournalIntegrity.unverified,
      ),
      warnings: List.unmodifiable(_stringList(json['warnings'])),
    );
    return ledger.repairKnownProtectionReplayConflicts();
  }
"""
replace_exact(models, old_factory, new_factory)

service = ROOT / "lib/features/auto_trade/application/local_live_trade_service.dart"
replace_exact(
    service,
    "  String? _lastAuditFingerprint;\n  DateTime? _lastAuditAt;\n",
    "  final Map<String, DateTime> _auditFingerprintSeenAt = {};\n",
)
replace_exact(
    service,
    "      final readiness = LocalLiveCycleReadinessPolicy.evaluate(\n"
    "        hasManagedExposure: _managed.isNotEmpty,\n"
    "        hasUnmanagedExchangeExposure: hasUnmanagedExchangeExposure,\n"
    "        pnlVerified: account.authoritativePnl.isVerified,\n",
    "      final managedHistoryVerified = _managed.every((managed) {\n"
    "        final positionPnl = account.authoritativePnl.forPositionId(\n"
    "          managed.positionId,\n"
    "        );\n"
    "        return positionPnl != null && positionPnl.isVerified;\n"
    "      });\n"
    "      final readiness = LocalLiveCycleReadinessPolicy.evaluate(\n"
    "        hasManagedExposure: _managed.isNotEmpty,\n"
    "        hasUnmanagedExchangeExposure: hasUnmanagedExchangeExposure,\n"
    "        pnlVerified: managedHistoryVerified,\n",
)
replace_exact(
    service,
    "        final history = await exchange.fetchClosedPositions(\n"
    "          positionId: managed.positionId,\n"
    "          credentials: credentials,\n"
    "        );\n",
    "        var closedHistoryAvailable = false;\n"
    "        try {\n"
    "          final history = await exchange.fetchClosedPositions(\n"
    "            positionId: managed.positionId,\n"
    "            credentials: credentials,\n"
    "          );\n"
    "          closedHistoryAvailable = history.isNotEmpty;\n"
    "        } on Object catch (error) {\n"
    "          _auditEvent(\n"
    "            'closed_history_deferred',\n"
    "            'The exchange position is closed; closed-position history will be retried (${_safeError(error)}).',\n"
    "            symbol: managed.symbol,\n"
    "          );\n"
    "        }\n",
)
replace_exact(
    service,
    "        if (history.isEmpty || !journalReconciled) {\n",
    "        if (!closedHistoryAvailable || !journalReconciled) {\n",
)
old_audit = """  void _auditEvent(String type, String message, {String? symbol}) {
    final now = DateTime.now().toUtc();
    final fingerprint = '$type|${symbol ?? ''}|$message';
    if (_lastAuditFingerprint == fingerprint &&
        _lastAuditAt != null &&
        now.difference(_lastAuditAt!) < const Duration(minutes: 10)) {
      return;
    }
    _lastAuditFingerprint = fingerprint;
    _lastAuditAt = now;
    _audit.add(
"""
new_audit = """  void _auditEvent(String type, String message, {String? symbol}) {
    final now = DateTime.now().toUtc();
    final fingerprint = '$type|${symbol ?? ''}|$message';
    _auditFingerprintSeenAt.removeWhere(
      (_, seenAt) => now.difference(seenAt) >= const Duration(minutes: 30),
    );
    final lastSeenAt = _auditFingerprintSeenAt[fingerprint];
    if (lastSeenAt != null &&
        now.difference(lastSeenAt) < const Duration(minutes: 10)) {
      return;
    }
    _auditFingerprintSeenAt[fingerprint] = now;
    if (_auditFingerprintSeenAt.length > 256) {
      _auditFingerprintSeenAt.remove(_auditFingerprintSeenAt.keys.first);
    }
    _audit.add(
"""
replace_exact(service, old_audit, new_audit)

mapper_test = ROOT / "test/bitunix_pnl_mapper_physical_canary_test.dart"
replace_exact(
    mapper_test,
    "    expect(fills.verified, isFalse);\n"
    "    expect(fills.values.single.positionId, isEmpty);\n",
    "    expect(fills.verified, isTrue);\n"
    "    expect(\n"
    "      fills.values.single.positionId,\n"
    "      '${BitunixPnlMapper.unassignedPositionPrefix}ambiguous',\n"
    "    );\n",
)

regression = ROOT / "test/eth_stop_hotfix_regression_test.dart"
regression.write_text(
    r"""import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/auto_trade/domain/trading_pnl_projection.dart';
import 'package:quantara_app/features/trading_journal/application/trading_journal_exchange_backfill.dart';
import 'package:quantara_app/features/trading_journal/domain/trading_journal_models.dart';
import 'package:quantara_app/features/trading_journal/domain/trading_journal_projection.dart';

void main() {
  test('unassigned historical trade does not poison a verified ETH closure', () {
    final pnl = _positionScopedPnl();

    expect(pnl.isVerified, isFalse);
    expect(pnl.forPositionId('eth-position')?.isVerified, isTrue);
    expect(
      pnl.forPositionId('unassigned-trade:old-gram')?.isVerified,
      isFalse,
    );

    final result = TradingJournalExchangeBackfill.reconcileVerifiedClosures(
      ledger: TradingJournalLedger.empty()
          .appendPlan(_ethPlan())
          .appendEvent(_ethEntry()),
      pnlProjection: pnl,
      openPositionIds: const {},
      recordedAt: DateTime.utc(2026, 8, 5, 17),
    );
    final journal = TradingJournalProjector.project(
      ledger: result.ledger,
      journalTradeId: 'local-live:eth-position',
    );

    expect(result.closedTradeIds, ['local-live:eth-position']);
    expect(journal.state, TradingJournalTradeState.closed);
    expect(journal.closeReason, TradingJournalCloseReason.stop);
    expect(journal.remainingQuantity, 0);
    expect(journal.grossPnl, closeTo(-0.18645, 0.00000001));
    expect(journal.fees, closeTo(0.0132, 0.00000001));
    expect(journal.netPnl, closeTo(-0.19965, 0.00000001));
    expect(journal.timeline.last.quantity, 0.011);
    expect(journal.timeline.last.price, 1884.25);
  });

  test('replayed protection confirmation is idempotent across timestamps', () {
    final first = _tpConfirmation(DateTime.utc(2026, 8, 5, 14, 30));
    final replay = _tpConfirmation(DateTime.utc(2026, 8, 5, 14, 31));
    final ledger = TradingJournalLedger.empty().appendEvent(first);
    final afterReplay = ledger.appendEvent(replay);

    expect(afterReplay.generation, ledger.generation);
    expect(afterReplay.integrity, TradingJournalIntegrity.verified);
    expect(afterReplay.warnings, isEmpty);
  });

  test('loads and repairs the legacy benign TP replay warning', () {
    final event = _tpConfirmation(DateTime.utc(2026, 8, 5, 14, 30));
    final json = TradingJournalLedger.empty().appendEvent(event).toJson()
      ..['integrity'] = TradingJournalIntegrity.unverified.name
      ..['warnings'] = [
        'Conflicting journal event identity exchange:tp-order:tp-2.',
      ];

    final repaired = TradingJournalLedger.fromJson(json);

    expect(repaired.integrity, TradingJournalIntegrity.verified);
    expect(repaired.warnings, isEmpty);
    expect(repaired.events, hasLength(1));
  });
}

TradingPnlProjection _positionScopedPnl() => TradingPnlProjection.reconcile(
  currency: 'USDT',
  asOf: DateTime.utc(2026, 8, 5, 16, 45),
  unrealizedByPosition: const {},
  fills: [
    ExchangePnlFill(
      tradeId: 'eth-stop-trade',
      orderId: 'eth-stop-order',
      positionId: 'eth-position',
      symbol: 'ETHUSDT',
      quantity: 0.011,
      price: 1884.25,
      realizedPnl: -0.18645,
      fee: 0.0132,
      reduceOnly: true,
      occurredAt: DateTime.utc(2026, 8, 5, 16, 40),
      side: 'BUY',
    ),
    ExchangePnlFill(
      tradeId: 'old-gram',
      orderId: 'old-gram-order',
      positionId: 'unassigned-trade:old-gram',
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
      positionId: 'eth-position',
      symbol: 'ETHUSDT',
      funding: 0,
      openedAt: DateTime.utc(2026, 8, 5, 14, 30),
      closedAt: DateTime.utc(2026, 8, 5, 16, 40),
      realizedPnl: -0.18645,
      fee: 0.0132,
    ),
  ],
  sourceVerified: true,
  warning: 'Trade old-gram could not be assigned to one exchange position.',
);

TradingJournalPlan _ethPlan() => TradingJournalPlan(
  journalTradeId: 'local-live:eth-position',
  setupId: 'eth-setup',
  analysisVersion: 'v1',
  symbol: 'ETHUSDT',
  market: 'USDT_PERPETUAL',
  timeframe: '1h',
  direction: TradingJournalDirection.short,
  strategy: 'structureZones',
  cadence: 'local-live',
  source: TradingJournalSource.localLive,
  decidedAt: DateTime.utc(2026, 8, 5, 14, 30),
  decisionPrice: 1867.3,
  entryLower: 1867.3,
  entryUpper: 1867.3,
  plannedEntry: 1867.3,
  originalStopLoss: 1884.25,
  targets: const [1807.539003938152, 1830.039844424859, 1845],
  expectedRMultiples: const [3, 2, 1],
  confidencePercent: 70,
  confluence: const ['1h'],
  regime: 'transition',
  rationale: 'physical ETH canary',
  invalidation: 'stop',
  accountEquity: 29.73,
  riskPercent: 0.1,
  riskBudget: 0.02973,
  leverage: 10,
  expectedMargin: 2.05403,
  passedGates: const ['isolated-margin'],
  blockedGates: const [],
  appVersion: '1.2.0-rc.2',
  strategyRulesVersion: 'v1',
  positionId: 'eth-position',
  entryOrderId: 'eth-entry-order',
  clientId: 'q-local-eth',
);

TradingJournalEvent _ethEntry() => TradingJournalEvent(
  eventId: 'eth-entry',
  journalTradeId: 'local-live:eth-position',
  type: TradingJournalEventType.entryFilled,
  occurredAt: DateTime.utc(2026, 8, 5, 14, 30),
  recordedAt: DateTime.utc(2026, 8, 5, 14, 30),
  source: TradingJournalFactSource.exchange,
  quality: TradingJournalFactQuality.confirmed,
  scope: TradingJournalScope.position,
  currency: 'USDT',
  asOf: DateTime.utc(2026, 8, 5, 14, 30),
  exchangeEventId: 'entry-order:eth-entry-order',
  positionId: 'eth-position',
  orderId: 'eth-entry-order',
  quantity: 0.011,
  price: 1867.3,
  remainingQuantity: 0.011,
);

TradingJournalEvent _tpConfirmation(DateTime occurredAt) => TradingJournalEvent(
  eventId: 'tp-confirmed:tp-2',
  journalTradeId: 'local-live:eth-position',
  type: TradingJournalEventType.takeProfitConfirmed,
  occurredAt: occurredAt,
  recordedAt: occurredAt,
  source: TradingJournalFactSource.exchange,
  quality: TradingJournalFactQuality.confirmed,
  scope: TradingJournalScope.position,
  currency: 'USDT',
  asOf: occurredAt,
  exchangeEventId: 'tp-order:tp-2',
  positionId: 'eth-position',
  orderId: 'tp-2',
  quantity: 0.011,
  price: 1830.039844424859,
  details: const {'targetIndex': 2},
);
"""
)

source_test = ROOT / "test/local_live_eth_stop_source_test.dart"
source_test.write_text(
    r"""import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('closed positions detach even when optional history fetch fails', () {
    final source = File(
      'lib/features/auto_trade/application/local_live_trade_service.dart',
    ).readAsStringSync();

    expect(source, contains('var closedHistoryAvailable = false;'));
    expect(source, contains("'closed_history_deferred'"));
    expect(source, contains('_managed.remove(managed);'));
    expect(source, contains('pnlVerified: managedHistoryVerified'));
    expect(source, contains('_auditFingerprintSeenAt[fingerprint]'));
  });

  test('inactive adaptive target slots are not journalled as TP orders', () {
    final source = File(
      'lib/features/trading_journal/application/local_live_journal_observer.dart',
    ).readAsStringSync();

    expect(
      RegExp(
        r"if \(orderId\.trim\(\)\.isEmpty \|\| quantity <= 0\) continue;",
      ).allMatches(source),
      hasLength(2),
    );
  });
}
"""
)
