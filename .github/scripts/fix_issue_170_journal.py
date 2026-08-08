from pathlib import Path

ROOT = Path('src/client/quantara_app')


def replace_once(path: Path, old: str, new: str, label: str) -> None:
    text = path.read_text(encoding='utf-8')
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f'{label}: expected one match, found {count}')
    path.write_text(text.replace(old, new, 1), encoding='utf-8')


# Projection keeps the immutable decision-time plan beside derived execution
# facts so the UI can explain what was known at entry without reconstructing it.
projection = ROOT / 'lib/features/trading_journal/domain/trading_journal_projection.dart'
replace_once(
    projection,
    """    required this.integrity,
    this.positionId,
""",
    """    required this.integrity,
    this.plan,
    this.positionId,
""",
    'projection plan constructor',
)
replace_once(
    projection,
    """  final TradingJournalIntegrity integrity;
  final String? positionId;
""",
    """  final TradingJournalIntegrity integrity;
  final TradingJournalPlan? plan;
  final String? positionId;

  bool get economicsPending =>
      state == TradingJournalTradeState.closed &&
      netPnl == null &&
      timeline.any(
        (event) =>
            event.type == TradingJournalEventType.positionClosed &&
            event.details['economicsPending'] == true,
      );
""",
    'projection plan/economics fields',
)
replace_once(
    projection,
    """      integrity: integrity,
      positionId: positionId,
""",
    """      integrity: integrity,
      plan: plan,
      positionId: positionId,
""",
    'projection populate plan',
)

# Evidence packet: raw exchange/journal facts are separated from derived
# metrics. Missing indicator snapshots are explicitly marked not captured.
evidence = ROOT / 'lib/features/trading_journal/domain/trading_journal_evidence_packet.dart'
evidence.write_text(r'''import 'trading_journal_models.dart';
import 'trading_journal_projection.dart';

abstract final class TradingJournalEvidencePacketBuilder {
  static List<Map<String, Object?>> buildAll(TradingJournalLedger ledger) =>
      ledger.plans.map((plan) => build(ledger, plan)).toList(growable: false);

  static Map<String, Object?> build(
    TradingJournalLedger ledger,
    TradingJournalPlan plan,
  ) {
    final projection = TradingJournalProjector.project(
      ledger: ledger,
      journalTradeId: plan.journalTradeId,
    );
    final events = ledger.events
        .where((event) => event.journalTradeId == plan.journalTradeId)
        .toList(growable: false);
    final close = _authoritativeClose(events);
    final entry = events
        .where(
          (event) =>
              event.type == TradingJournalEventType.entryFilled ||
              event.type == TradingJournalEventType.entryPartiallyFilled,
        )
        .firstOrNull;
    final initialStopDistancePercent = plan.plannedEntry <= 0
        ? null
        : (plan.plannedEntry - plan.originalStopLoss).abs() /
              plan.plannedEntry *
              100;
    final stopSlippagePercent =
        close?.price == null ||
            plan.originalStopLoss <= 0 ||
            projection.closeReason != TradingJournalCloseReason.stop
        ? null
        : switch (plan.direction) {
            TradingJournalDirection.long =>
              (plan.originalStopLoss - close!.price!) /
                  plan.originalStopLoss *
                  100,
            TradingJournalDirection.short =>
              (close!.price! - plan.originalStopLoss) /
                  plan.originalStopLoss *
                  100,
            TradingJournalDirection.wait => null,
          };

    return {
      'schemaVersion': 1,
      'journalTradeId': plan.journalTradeId,
      'rawFacts': {
        'plan': plan.toJson(),
        'events': events.map((event) => event.toJson()).toList(growable: false),
      },
      'decisionTime': {
        'symbol': plan.symbol,
        'timeframe': plan.timeframe,
        'direction': plan.direction.name,
        'setupId': plan.setupId,
        'strategy': plan.strategy,
        'strategyVersion': plan.strategyRulesVersion,
        'analysisVersion': plan.analysisVersion,
        'cadence': plan.cadence,
        'marketRegime': plan.regime,
        'confidencePercent': plan.confidencePercent,
        'reasons': plan.confluence,
        'rationale': plan.rationale,
        'invalidation': plan.invalidation,
      },
      'indicatorSnapshot': {
        'captured': false,
        'values': <String, Object?>{},
        'note':
            'Indicator values were not persisted at this journal boundary; no values were fabricated.',
      },
      'executionPlan': {
        'decisionPrice': plan.decisionPrice,
        'entryZone': {'lower': plan.entryLower, 'upper': plan.entryUpper},
        'plannedEntry': plan.plannedEntry,
        'actualEntry': projection.entryPrice,
        'originalStopLoss': plan.originalStopLoss,
        'targets': plan.targets,
        'expectedRMultiples': plan.expectedRMultiples,
        'configuredRiskPercent': plan.riskPercent,
        'riskBudgetUsdt': plan.riskBudget,
        'accountEquityAtEntry': plan.accountEquity,
        'configuredLeverage': plan.leverage,
        'expectedMargin': plan.expectedMargin,
        'actualQuantity': projection.initialQuantity ?? entry?.quantity,
      },
      'admissionGates': {
        'passed': plan.passedGates,
        'blocked': plan.blockedGates,
      },
      'postTrade': {
        'closed': projection.state == TradingJournalTradeState.closed,
        'economicsPending': projection.economicsPending,
        'actualExit': close?.price,
        'closedAt': projection.closedAt?.toUtc().toIso8601String(),
        'closeReason': projection.closeReason?.name,
        'grossPnl': projection.grossPnl,
        'fees': projection.fees,
        'funding': projection.funding,
        'netPnl': projection.netPnl,
        'actualR': projection.realizedR,
        'durationSeconds': projection.holdingDuration?.inSeconds,
        'returnOnMarginPercent': projection.returnOnMarginPercent,
        'returnOnEquityPercent': projection.returnOnEquityPercent,
        'priceMovePercent': projection.priceMovePercent,
        'mfePercent': projection.mfe,
        'maePercent': projection.mae,
        'maximumOpenProfit': projection.maximumOpenProfit,
        'maximumOpenLoss': projection.maximumOpenLoss,
        'highestTargetReached': projection.highestTargetReached,
        'profitLockConfirmed': projection.profitLockConfirmed,
      },
      'reviewFacts': {
        'initialStopDistancePercent': initialStopDistancePercent,
        'stopSlippagePercent': stopSlippagePercent,
        'sampleSizeClaimMade': false,
      },
      'dataQuality': {
        'integrity': projection.integrity.name,
        'warning': projection.warning,
        'factsCount': events.length,
      },
    };
  }

  static TradingJournalEvent? _authoritativeClose(
    List<TradingJournalEvent> events,
  ) {
    final closes = events
        .where(
          (event) =>
              event.type == TradingJournalEventType.positionClosed ||
              event.type == TradingJournalEventType.liquidation,
        )
        .toList(growable: false)
      ..sort((a, b) => a.occurredAt.compareTo(b.occurredAt));
    final authoritative = closes
        .where((event) => event.details['economicsPending'] != true)
        .toList(growable: false);
    if (authoritative.isNotEmpty) return authoritative.last;
    return closes.isEmpty ? null : closes.last;
  }
}
''', encoding='utf-8')

# Local-only architecture for a future support transport. No exchange client,
# no trading capability, default OFF, scoped to sanitized diagnostic reads.
support = ROOT / 'lib/features/auto_trade/application/read_only_support_session.dart'
support.write_text(r'''import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

final class ReadOnlySupportSessionGrant {
  const ReadOnlySupportSessionGrant({
    required this.token,
    required this.expiresAt,
    required this.scope,
  });

  final String token;
  final DateTime expiresAt;
  final String scope;
}

final class ReadOnlySupportSessionSnapshot {
  const ReadOnlySupportSessionSnapshot({
    required this.createdAt,
    required this.expiresAt,
    required this.scope,
    required this.tokenFingerprint,
  });

  final DateTime createdAt;
  final DateTime expiresAt;
  final String scope;
  final String tokenFingerprint;

  Map<String, Object?> toDiagnosticJson(DateTime now) => {
    'active': now.toUtc().isBefore(expiresAt),
    'scope': scope,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'expiresAt': expiresAt.toUtc().toIso8601String(),
    'tokenFingerprint': tokenFingerprint,
    'transportImplemented': false,
    'exchangeCredentialsExposed': false,
    'tradingPermission': false,
  };
}

final class ReadOnlySupportSessionManager {
  ReadOnlySupportSessionManager({
    DateTime Function()? clock,
    Random? random,
  }) : _clock = clock ?? (() => DateTime.now().toUtc()),
       _random = random ?? Random.secure();

  static const scope = 'diagnostics.read';
  final DateTime Function() _clock;
  final Random _random;
  ReadOnlySupportSessionSnapshot? _snapshot;

  ReadOnlySupportSessionSnapshot? get current {
    final snapshot = _snapshot;
    if (snapshot == null) return null;
    if (!_clock().toUtc().isBefore(snapshot.expiresAt)) {
      _snapshot = null;
      return null;
    }
    return snapshot;
  }

  bool get isActive => current != null;

  ReadOnlySupportSessionGrant enable({Duration ttl = const Duration(minutes: 45)}) {
    if (ttl < const Duration(minutes: 30) ||
        ttl > const Duration(minutes: 60)) {
      throw ArgumentError.value(ttl, 'ttl', 'must be between 30 and 60 minutes');
    }
    final now = _clock().toUtc();
    final bytes = List<int>.generate(32, (_) => _random.nextInt(256));
    final token = base64UrlEncode(bytes).replaceAll('=', '');
    final fingerprint = sha256.convert(utf8.encode(token)).toString().substring(0, 16);
    final expiresAt = now.add(ttl);
    _snapshot = ReadOnlySupportSessionSnapshot(
      createdAt: now,
      expiresAt: expiresAt,
      scope: scope,
      tokenFingerprint: fingerprint,
    );
    return ReadOnlySupportSessionGrant(
      token: token,
      expiresAt: expiresAt,
      scope: scope,
    );
  }

  void revoke() => _snapshot = null;

  static Map<String, Object?> architectureDescriptor() => const {
    'defaultEnabled': false,
    'scope': scope,
    'readOnly': true,
    'sanitizedDiagnosticsOnly': true,
    'revocable': true,
    'ttlMinutes': {'minimum': 30, 'default': 45, 'maximum': 60},
    'backendTransportImplemented': false,
    'exchangeCredentialsAllowed': false,
    'tradingWritesAllowed': false,
  };
}
''', encoding='utf-8')

# Diagnostic export includes normalized evidence packets and an explicit,
# inactive support-session architecture descriptor.
page = ROOT / 'lib/features/owner_alpha/presentation/owner_alpha_page.dart'
replace_once(
    page,
    """import '../../trading_journal/domain/trading_journal_models.dart';
""" if "import '../../trading_journal/domain/trading_journal_models.dart';\n" in page.read_text(encoding='utf-8') else """import '../../trading_journal/data/database_trading_journal_store.dart';
""",
    """import '../../trading_journal/data/database_trading_journal_store.dart';
import '../../trading_journal/domain/trading_journal_evidence_packet.dart';
""" if "import '../../trading_journal/domain/trading_journal_models.dart';\n" not in page.read_text(encoding='utf-8') else """import '../../trading_journal/domain/trading_journal_models.dart';
import '../../trading_journal/domain/trading_journal_evidence_packet.dart';
""",
    'evidence import',
)
# add support import near auto-trade app imports
replace_once(
    page,
    """import '../../auto_trade/application/local_live_trade_service.dart';
""",
    """import '../../auto_trade/application/local_live_trade_service.dart';
import '../../auto_trade/application/read_only_support_session.dart';
""",
    'support import',
)
tools = ROOT / 'lib/features/owner_alpha/presentation/owner_alpha_local_live_tools.dart'
replace_once(
    tools,
    """          'tradingJournal': journalLedger.toJson(),
          'persistedLocalServiceState': persisted,
""",
    """          'tradingJournal': journalLedger.toJson(),
          'tradeEvidencePackets':
              TradingJournalEvidencePacketBuilder.buildAll(journalLedger),
          'supportSessionFoundation':
              ReadOnlySupportSessionManager.architectureDescriptor(),
          'persistedLocalServiceState': persisted,
""",
    'diagnostic evidence/support sections',
)

# Journal UI: CLOSED is never presented as unavailable/open merely because the
# economic backfill is pending; cards expose reason and duration.
view = ROOT / 'lib/features/trading_journal/presentation/trading_journal_view.dart'
replace_once(
    view,
    """    final netText = net == null
        ? (persian ? 'ناموجود' : 'Unavailable')
        : '${net >= 0 ? '+' : ''}${QuantaraNumberFormat.marketValue(net, unit: 'USDT')}';
""",
    """    final netText = net == null
        ? projection.economicsPending
              ? (persian ? 'تطبیق PnL در انتظار' : 'PnL reconciliation pending')
              : (persian ? 'ناموجود' : 'Unavailable')
        : '${net >= 0 ? '+' : ''}${QuantaraNumberFormat.marketValue(net, unit: 'USDT')}';
""",
    'card pending economics label',
)
replace_once(
    view,
    """              if (projection.realizedR != null)
                StatusPill(
""",
    """              if (projection.state == TradingJournalTradeState.closed)
                StatusPill(
                  label: _closeReasonLabel(persian, projection.closeReason),
                  color: _closeReasonColor(context, projection.closeReason),
                  icon: Icons.logout_rounded,
                ),
              if (projection.holdingDuration != null)
                StatusPill(
                  label: _formatHoldingDuration(projection.holdingDuration!),
                  color: QuantaraColors.violet,
                  icon: Icons.timer_outlined,
                ),
              if (projection.realizedR != null)
                StatusPill(
""",
    'card reason duration',
)
replace_once(
    view,
    """                  net == null
                      ? (persian ? 'ناموجود' : 'Unavailable')
                      : '${net >= 0 ? '+' : ''}${QuantaraNumberFormat.marketValue(net, unit: 'USDT')}',
""",
    """                  net == null
                      ? projection.economicsPending
                            ? (persian
                                  ? 'تطبیق PnL در انتظار'
                                  : 'PnL reconciliation pending')
                            : (persian ? 'ناموجود' : 'Unavailable')
                      : '${net >= 0 ? '+' : ''}${QuantaraNumberFormat.marketValue(net, unit: 'USDT')}',
""",
    'detail pending economics label',
)
replace_once(
    view,
    """        _ProjectionSummary(projection: projection, persian: _persian),
        const SizedBox(height: 16),
        SectionHeading(
""",
    """        _ProjectionSummary(projection: projection, persian: _persian),
        const SizedBox(height: 16),
        _TradeEvidencePanel(projection: projection, persian: _persian),
        const SizedBox(height: 16),
        SectionHeading(
""",
    'detail evidence panel',
)
insert_marker = "final class _TimelineEventTile extends StatelessWidget {"
panel = r'''final class _TradeEvidencePanel extends StatelessWidget {
  const _TradeEvidencePanel({required this.projection, required this.persian});

  final TradingJournalProjection projection;
  final bool persian;

  @override
  Widget build(BuildContext context) {
    final plan = projection.plan;
    if (plan == null) return const SizedBox.shrink();
    final stopDistance = plan.plannedEntry <= 0
        ? null
        : (plan.plannedEntry - plan.originalStopLoss).abs() /
              plan.plannedEntry *
              100;
    final whyEntered = <String>[
      if (plan.rationale.trim().isNotEmpty) plan.rationale,
      ...plan.confluence.where((item) => item.trim().isNotEmpty),
    ];
    final whyExited = projection.economicsPending
        ? (persian
              ? 'صرافی بسته‌شدن پوزیشن را تأیید کرده است؛ جزئیات مالی هنوز در حال تطبیق هستند.'
              : 'The exchange confirmed the position is closed; economics are still reconciling.')
        : projection.state == TradingJournalTradeState.closed
        ? (persian
              ? 'خروج ثبت‌شده: ${_closeReasonLabel(true, projection.closeReason)}.'
              : 'Recorded exit: ${_closeReasonLabel(false, projection.closeReason)}.')
        : (persian ? 'هنوز خروج نهایی ثبت نشده است.' : 'No final exit is recorded yet.');
    final review = stopDistance == null
        ? (persian
              ? 'فاصله استاپ اولیه قابل محاسبه نیست.'
              : 'Initial stop distance cannot be calculated.')
        : (persian
              ? 'استاپ اولیه ${stopDistance.toStringAsFixed(3)}٪ از ورود برنامه‌ریزی‌شده فاصله داشته است. برای قضاوت درباره مناسب‌بودن آن به نمونه کافی و داده ATR نیاز است.'
              : 'The initial stop was ${stopDistance.toStringAsFixed(3)}% from planned entry. Judging whether it was appropriate requires enough samples and captured ATR data.');

    Widget facts(String title, List<String> lines, Color color) => SectionCard(
      accentColor: color,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          for (final line in lines) ...[
            Text('• $line'),
            const SizedBox(height: 4),
          ],
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeading(
          title: persian ? 'شواهد معامله' : 'Trade evidence',
          subtitle: persian
              ? 'واقعیت‌های تصمیم، اجرا و نتیجه؛ بدون نتیجه‌گیری بدون داده'
              : 'Decision, execution and outcome facts without unsupported claims',
        ),
        const SizedBox(height: 12),
        facts(
          persian ? 'پلن و اجرا' : 'Plan & execution',
          [
            'setup ${plan.setupId}',
            '${plan.strategy} · v${plan.strategyRulesVersion} · ${plan.timeframe}',
            'regime ${plan.regime} · confidence ${plan.confidencePercent.toStringAsFixed(0)}%',
            'entry ${plan.plannedEntry} · SL ${plan.originalStopLoss} · targets ${plan.targets.join(', ')}',
            'risk ${plan.riskBudget.toStringAsFixed(4)} USDT · ${plan.leverage}x · margin ${plan.expectedMargin.toStringAsFixed(4)} USDT',
          ],
          QuantaraColors.cyan,
        ),
        const SizedBox(height: 10),
        facts(
          persian ? 'چرا وارد شد؟' : 'Why entered?',
          whyEntered.isEmpty
              ? [persian ? 'دلیل ثبت‌شده‌ای موجود نیست.' : 'No persisted entry reason is available.']
              : whyEntered,
          QuantaraColors.violet,
        ),
        const SizedBox(height: 10),
        facts(persian ? 'چرا خارج شد؟' : 'Why exited?', [whyExited], _closeReasonColor(context, projection.closeReason)),
        const SizedBox(height: 10),
        facts(
          persian ? 'چه چیزی باید بررسی شود؟' : 'What to review?',
          [
            review,
            persian
                ? 'ATR/EMA/ADX/DMI در این نسخه داخل مرز ژورنال ذخیره نشده‌اند؛ برای این معامله عددی جعل نمی‌شود.'
                : 'ATR/EMA/ADX/DMI were not persisted at this journal boundary; no values are fabricated for this trade.',
          ],
          QuantaraColors.warning,
        ),
        const SizedBox(height: 10),
        facts(
          persian ? 'کیفیت داده' : 'Data quality',
          [
            'integrity ${projection.integrity.name}',
            'passed gates ${plan.passedGates.join(', ')}',
            if (plan.blockedGates.isNotEmpty) 'blocked gates ${plan.blockedGates.join(', ')}',
            if (projection.warning != null) projection.warning!,
          ],
          projection.integrity == TradingJournalIntegrity.unverified
              ? QuantaraColors.warning
              : QuantaraColors.success,
        ),
      ],
    );
  }
}

'''
text = view.read_text(encoding='utf-8')
if text.count(insert_marker) != 1:
    raise RuntimeError('timeline marker mismatch')
view.write_text(text.replace(insert_marker, panel + insert_marker, 1), encoding='utf-8')
# duration helper before date formatter
text = view.read_text(encoding='utf-8')
marker = 'String _formatDate(DateTime value) {'
helper = r'''String _formatHoldingDuration(Duration value) {
  final hours = value.inHours;
  final minutes = value.inMinutes.remainder(60);
  if (hours > 0) return '${hours}h ${minutes}m';
  if (value.inMinutes > 0) return '${value.inMinutes}m';
  return '${value.inSeconds}s';
}

'''
if text.count(marker) != 1:
    raise RuntimeError('date formatter marker mismatch')
view.write_text(text.replace(marker, helper + marker, 1), encoding='utf-8')

# Evidence regression uses the physical SOL facts and validates raw/derived split.
(ROOT / 'test/trading_journal_evidence_packet_test.dart').write_text(r'''import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/trading_journal/domain/trading_journal_evidence_packet.dart';
import 'package:quantara_app/features/trading_journal/domain/trading_journal_models.dart';

void main() {
  test('evidence packet separates raw facts and derived SOL diagnostics', () {
    var ledger = TradingJournalLedger.empty().appendPlan(_plan());
    ledger = ledger.appendEvent(_entry()).appendEvent(_close()).appendEvent(_funding());
    final packet = TradingJournalEvidencePacketBuilder.buildAll(ledger).single;
    final indicator = packet['indicatorSnapshot']! as Map<String, Object?>;
    final post = packet['postTrade']! as Map<String, Object?>;
    final review = packet['reviewFacts']! as Map<String, Object?>;

    expect(packet['rawFacts'], isA<Map<String, Object?>>());
    expect(indicator['captured'], isFalse);
    expect((indicator['values']! as Map).isEmpty, isTrue);
    expect(post['closed'], isTrue);
    expect(post['closeReason'], 'stop');
    expect(post['netPnl'], closeTo(-0.10777156, 0.00000001));
    expect(post['durationSeconds'], 1500);
    expect(review['initialStopDistancePercent'], closeTo(0.4189189, 0.000001));
    expect(review['stopSlippagePercent'], closeTo(0.0949939, 0.000001));
    expect(review['sampleSizeClaimMade'], isFalse);
  });
}

TradingJournalPlan _plan() => TradingJournalPlan(
  journalTradeId: 'local-live:sol-position', setupId: 'sol-5m', analysisVersion: 'v1',
  symbol: 'SOLUSDT', market: 'USDT_PERPETUAL', timeframe: '5m',
  direction: TradingJournalDirection.long, strategy: 'trendPullback', cadence: 'balanced',
  source: TradingJournalSource.localLive, decidedAt: DateTime.utc(2026, 8, 7, 15),
  decisionPrice: 74, entryLower: 74, entryUpper: 74, plannedEntry: 74,
  originalStopLoss: 73.69, targets: const [74.9022], expectedRMultiples: const [2.91],
  confidencePercent: 70, confluence: const ['Trend aligned', 'Pullback'], regime: 'trend',
  rationale: 'Trend aligned pullback', invalidation: 'Stop invalidates setup', accountEquity: 29.81,
  riskPercent: 0.1, riskBudget: 0.10, leverage: 10, expectedMargin: 1.702,
  passedGates: const ['isolated-margin', 'protection-ready'], blockedGates: const [],
  appVersion: '1.2.0-rc.2', strategyRulesVersion: '1.1', positionId: 'sol-position',
);

TradingJournalEvent _entry() => TradingJournalEvent(
  eventId: 'entry', journalTradeId: 'local-live:sol-position', type: TradingJournalEventType.entryFilled,
  occurredAt: DateTime.utc(2026, 8, 7, 15), recordedAt: DateTime.utc(2026, 8, 7, 15),
  source: TradingJournalFactSource.exchange, quality: TradingJournalFactQuality.confirmed,
  scope: TradingJournalScope.position, currency: 'USDT', asOf: DateTime.utc(2026, 8, 7, 15),
  positionId: 'sol-position', quantity: 0.23, price: 74, remainingQuantity: 0.23,
);

TradingJournalEvent _close() => TradingJournalEvent(
  eventId: 'stop-fill', journalTradeId: 'local-live:sol-position', type: TradingJournalEventType.positionClosed,
  occurredAt: DateTime.utc(2026, 8, 7, 15, 25), recordedAt: DateTime.utc(2026, 8, 7, 15, 26),
  source: TradingJournalFactSource.exchange, quality: TradingJournalFactQuality.confirmed,
  scope: TradingJournalScope.position, currency: 'USDT', asOf: DateTime.utc(2026, 8, 7, 15, 26),
  exchangeEventId: 'stop-fill', positionId: 'sol-position', orderId: 'stop-order', tradeId: 'stop-fill',
  quantity: 0.23, price: 73.62, grossPnl: -0.0874, fee: 0.02037156, remainingQuantity: 0,
  details: const {'closeReason': 'stop'},
);

TradingJournalEvent _funding() => TradingJournalEvent(
  eventId: 'funding', journalTradeId: 'local-live:sol-position', type: TradingJournalEventType.fundingApplied,
  occurredAt: DateTime.utc(2026, 8, 7, 15, 25), recordedAt: DateTime.utc(2026, 8, 7, 15, 26),
  source: TradingJournalFactSource.exchange, quality: TradingJournalFactQuality.confirmed,
  scope: TradingJournalScope.position, currency: 'USDT', asOf: DateTime.utc(2026, 8, 7, 15, 26),
  exchangeEventId: 'funding', positionId: 'sol-position', funding: 0,
);
''', encoding='utf-8')

(ROOT / 'test/read_only_support_session_test.dart').write_text(r'''import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/auto_trade/application/read_only_support_session.dart';

void main() {
  test('support session is default off, read-only, expiring and revocable', () {
    var now = DateTime.utc(2026, 8, 8, 8);
    final manager = ReadOnlySupportSessionManager(clock: () => now, random: Random(7));
    expect(manager.isActive, isFalse);
    final descriptor = ReadOnlySupportSessionManager.architectureDescriptor();
    expect(descriptor['defaultEnabled'], isFalse);
    expect(descriptor['tradingWritesAllowed'], isFalse);
    expect(descriptor['exchangeCredentialsAllowed'], isFalse);

    final grant = manager.enable();
    expect(grant.scope, 'diagnostics.read');
    expect(grant.expiresAt, now.add(const Duration(minutes: 45)));
    expect(grant.token.length, greaterThan(30));
    final diagnostic = manager.current!.toDiagnosticJson(now);
    expect(diagnostic.toString(), isNot(contains(grant.token)));
    expect(diagnostic['tradingPermission'], isFalse);

    now = now.add(const Duration(minutes: 46));
    expect(manager.isActive, isFalse);

    now = DateTime.utc(2026, 8, 8, 9);
    manager.enable(ttl: const Duration(minutes: 30));
    expect(manager.isActive, isTrue);
    manager.revoke();
    expect(manager.isActive, isFalse);
  });

  test('support TTL outside 30-60 minute boundary is rejected', () {
    final manager = ReadOnlySupportSessionManager(random: Random(1));
    expect(() => manager.enable(ttl: const Duration(minutes: 29)), throwsArgumentError);
    expect(() => manager.enable(ttl: const Duration(minutes: 61)), throwsArgumentError);
  });
}
''', encoding='utf-8')

(ROOT / 'test/issue_170_journal_ui_source_test.dart').write_text(r'''import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('journal UI exposes closed pending economics and evidence review sections', () {
    final source = File('lib/features/trading_journal/presentation/trading_journal_view.dart').readAsStringSync();
    expect(source, contains('PnL reconciliation pending'));
    expect(source, contains('Why entered?'));
    expect(source, contains('Why exited?'));
    expect(source, contains('What to review?'));
    expect(source, contains('Data quality'));
    expect(source, contains('_formatHoldingDuration'));
  });
}
''', encoding='utf-8')
