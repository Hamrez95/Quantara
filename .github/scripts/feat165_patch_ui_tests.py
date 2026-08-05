from pathlib import Path

root = Path('src/client/quantara_app')


def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text()
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{path}: expected one anchor, found {count}')
    path.write_text(text.replace(old, new, 1))


page = root / 'lib/features/owner_alpha/presentation/owner_alpha_page.dart'
text = page.read_text()
if '_autoTradeViewKey' not in text:
    replace_once(
        page,
        '''  late final OwnerAlphaController _controller = OwnerAlphaController(
    repository: widget.repository,
    settingsStore: widget.settingsStore,
    opportunityStateStore: widget.opportunityStateStore,
    notificationGateway: widget.notificationGateway,
    backgroundScanGateway: widget.backgroundScanGateway,
    languageCode: widget.locale.languageCode,
  );
  int _destination = 0;''',
        '''  late final OwnerAlphaController _controller = OwnerAlphaController(
    repository: widget.repository,
    settingsStore: widget.settingsStore,
    opportunityStateStore: widget.opportunityStateStore,
    notificationGateway: widget.notificationGateway,
    backgroundScanGateway: widget.backgroundScanGateway,
    languageCode: widget.locale.languageCode,
  );
  final GlobalKey<_AutoTradeViewState> _autoTradeViewKey =
      GlobalKey<_AutoTradeViewState>();
  int _destination = 0;''',
    )
    marker = '  Future<void> _showAddSymbolDialog() async {'
    method = '''  Future<void> _refreshCurrentDestination() async {
    switch (_destination) {
      case 5:
        final state = _autoTradeViewKey.currentState;
        if (state != null) {
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
        return;
      default:
        await _controller.refresh();
        return;
    }
  }

'''
    if marker not in page.read_text():
        raise SystemExit('owner page add symbol marker missing')
    page.write_text(page.read_text().replace(marker, method + marker, 1))
    replace_once(page, '            onRefresh: _controller.refresh,', '            onRefresh: _refreshCurrentDestination,')
    replace_once(
        page,
        '''            showTopBar: desktop,
            realtimeMonitor: widget.realtimeMonitor,
          ),''',
        '''            showTopBar: desktop,
            realtimeMonitor: widget.realtimeMonitor,
            autoTradeViewKey: _autoTradeViewKey,
            onRefresh: _refreshCurrentDestination,
          ),''',
    )
    replace_once(
        page,
        '''    required this.showTopBar,
    required this.realtimeMonitor,
  });''',
        '''    required this.showTopBar,
    required this.realtimeMonitor,
    required this.autoTradeViewKey,
    required this.onRefresh,
  });''',
    )
    replace_once(
        page,
        '''  final bool showTopBar;
  final ValueListenable<RealtimeMarketMonitorSnapshot>? realtimeMonitor;

  @override''',
        '''  final bool showTopBar;
  final ValueListenable<RealtimeMarketMonitorSnapshot>? realtimeMonitor;
  final GlobalKey<_AutoTradeViewState> autoTradeViewKey;
  final Future<void> Function() onRefresh;

  @override''',
    )
    replace_once(page, '      onRefresh: controller.refresh,', '      onRefresh: onRefresh,')
    replace_once(
        page,
        '''                  else if (destination == 5)
                    _AutoTradeView(
                      controller: autoTradeController,''',
        '''                  else if (destination == 5)
                    _AutoTradeView(
                      key: autoTradeViewKey,
                      controller: autoTradeController,''',
    )
    replace_once(page, '  final VoidCallback onRefresh;', '  final Future<void> Function() onRefresh;')
    replace_once(
        page,
        '          onPressed: controller.isLoading ? null : onRefresh,',
        '''          onPressed: controller.isLoading
              ? null
              : () => unawaited(onRefresh()),''',
    )

auto_trade = root / 'lib/features/owner_alpha/presentation/owner_alpha_auto_trade.dart'
text = auto_trade.read_text()
if 'Future<void> refreshAll()' not in text:
    replace_once(
        auto_trade,
        '''  const _AutoTradeView({
    required this.controller,
    required this.unattendedController,
    required this.analysisController,
  });''',
        '''  const _AutoTradeView({
    required this.controller,
    required this.unattendedController,
    required this.analysisController,
    super.key,
  });''',
    )
    replace_once(
        auto_trade,
        '''  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _localController.dispose();
    super.dispose();
  }

  Future<void> _showConnectionDialog() async {''',
        '''  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _localController.dispose();
    super.dispose();
  }

  Future<void> refreshAll() async {
    await widget.controller.reconcile(
      reason: PrivateAccountRefreshReason.manual,
      force: true,
    );
    await _localController.refresh();
  }

  Future<void> _showConnectionDialog() async {''',
    )

view = root / 'lib/features/trading_journal/presentation/trading_journal_view.dart'
text = view.read_text()
if 'TradingJournalTradeState.closed => QuantaraColors.success' in text:
    text = text.replace(
        'TradingJournalTradeState.closed => QuantaraColors.success',
        'TradingJournalTradeState.closed => QuantaraColors.electricBlue',
        1,
    )
    text = text.replace(
        '''  TradingJournalFactQuality.confirmed => QuantaraColors.success,
  TradingJournalFactQuality.calculated => QuantaraColors.cyan,
  TradingJournalFactQuality.userEntered => QuantaraColors.violet,''',
        '''  TradingJournalFactQuality.confirmed => QuantaraColors.cyan,
  TradingJournalFactQuality.calculated => QuantaraColors.violet,
  TradingJournalFactQuality.userEntered => QuantaraColors.electricBlue,''',
        1,
    )
    old = '''    final directionColor = projection.direction == TradingJournalDirection.long
        ? QuantaraColors.success
        : projection.direction == TradingJournalDirection.short
        ? QuantaraColors.danger
        : QuantaraColors.warning;'''
    new = '''    final directionColor = projection.direction == TradingJournalDirection.long
        ? QuantaraColors.electricBlue
        : projection.direction == TradingJournalDirection.short
        ? QuantaraColors.violet
        : scheme.onSurfaceVariant;'''
    if old not in text:
        raise SystemExit('journal direction color anchor missing')
    text = text.replace(old, new, 1)
    old = '''                  (projection.realizedR ?? 0) >= 0
                      ? QuantaraColors.cyan
                      : QuantaraColors.danger,'''
    new = '''                  projection.realizedR == null
                      ? scheme.onSurfaceVariant
                      : projection.realizedR! >= 0
                      ? QuantaraColors.success
                      : QuantaraColors.danger,'''
    if old not in text:
        raise SystemExit('journal R color anchor missing')
    text = text.replace(old, new, 1)
    old = '''                  QuantaraColors.violet,
                ),
              ];'''
    new = '''                  projection.highestTargetReached > 0
                      ? QuantaraColors.success
                      : scheme.onSurfaceVariant,
                ),
              ];'''
    if old not in text:
        raise SystemExit('highest target color anchor missing')
    text = text.replace(old, new, 1)
    old = '''        (projection.returnOnMarginPercent ?? 0) >= 0
            ? QuantaraColors.success
            : QuantaraColors.danger,'''
    new = '''        projection.returnOnMarginPercent == null
            ? Theme.of(context).colorScheme.onSurfaceVariant
            : projection.returnOnMarginPercent! >= 0
            ? QuantaraColors.success
            : QuantaraColors.danger,'''
    if old not in text:
        raise SystemExit('margin return color anchor missing')
    text = text.replace(old, new, 1)
    old = '''        (projection.priceMovePercent ?? 0) >= 0
            ? QuantaraColors.success
            : QuantaraColors.danger,'''
    new = '''        projection.priceMovePercent == null
            ? Theme.of(context).colorScheme.onSurfaceVariant
            : projection.priceMovePercent! >= 0
            ? QuantaraColors.success
            : QuantaraColors.danger,'''
    if old not in text:
        raise SystemExit('price move color anchor missing')
    text = text.replace(old, new, 1)
    replace = '''        Icons.logout_rounded,
        QuantaraColors.electricBlue,'''
    if replace not in text:
        raise SystemExit('close reason color anchor missing')
    text = text.replace(
        replace,
        '''        Icons.logout_rounded,
        _closeReasonColor(context, projection.closeReason),''',
        1,
    )
    marker = 'String _closeReasonLabel(bool persian, TradingJournalCloseReason? reason) {'
    helper = '''Color _closeReasonColor(
  BuildContext context,
  TradingJournalCloseReason? reason,
) => switch (reason) {
  TradingJournalCloseReason.takeProfit1 ||
  TradingJournalCloseReason.takeProfit2 ||
  TradingJournalCloseReason.takeProfit3 => QuantaraColors.success,
  TradingJournalCloseReason.stop ||
  TradingJournalCloseReason.liquidation => QuantaraColors.danger,
  TradingJournalCloseReason.emergency => QuantaraColors.warning,
  _ => Theme.of(context).colorScheme.onSurfaceVariant,
};

'''
    if marker not in text:
        raise SystemExit('close reason label marker missing')
    view.write_text(text.replace(marker, helper + marker, 1))

(root / 'test/bitunix_pnl_mapper_physical_canary_test.dart').write_text('''import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/auto_trade/data/bitunix_pnl_mapper.dart';

void main() {
  test('attributes a stop fill just after rounded settlement close time', () {
    final openedAt = DateTime.utc(2026, 8, 5, 2);
    final closedAt = DateTime.utc(2026, 8, 5, 3, 19);
    final fillAt = DateTime.utc(2026, 8, 5, 3, 19, 14);
    final settlements = BitunixPnlMapper.settlements({
      'positionList': [
        {
          'positionId': 'gram-position',
          'symbol': 'GRAMUSDT',
          'ctime': openedAt.millisecondsSinceEpoch,
          'mtime': closedAt.millisecondsSinceEpoch,
          'realizedPNL': '-0.2574',
          'fee': '0.03575286',
          'funding': '0',
        },
      ],
    });
    final fills = BitunixPnlMapper.fills(
      {
        'tradeList': [
          {
            'tradeId': '2795413522294203930',
            'orderId': '7352379888826528074',
            'symbol': 'GRAMUSDT',
            'qty': '42.9',
            'price': '1.389',
            'realizedPNL': '-0.2574',
            'fee': '0.03575286',
            'ctime': fillAt.millisecondsSinceEpoch,
            'reduceOnly': true,
            'side': 'SELL',
          },
        ],
      },
      openPositions: const [],
      settlements: settlements.values,
    );

    expect(settlements.verified, isTrue);
    expect(fills.verified, isTrue);
    expect(fills.warning, isNull);
    expect(fills.values.single.positionId, 'gram-position');
    expect(fills.values.single.quantity, 42.9);
    expect(fills.values.single.realizedPnl, -0.2574);
    expect(fills.values.single.fee, 0.03575286);
  });

  test('keeps equal-distance same-symbol closed histories ambiguous', () {
    final fillAt = DateTime.utc(2026, 8, 5, 3, 19, 14);
    final settlements = BitunixPnlMapper.settlements({
      'positionList': [
        {
          'positionId': 'left',
          'symbol': 'GRAMUSDT',
          'ctime': DateTime.utc(2026, 8, 5, 1).millisecondsSinceEpoch,
          'mtime': DateTime.utc(2026, 8, 5, 3, 19).millisecondsSinceEpoch,
        },
        {
          'positionId': 'right',
          'symbol': 'GRAMUSDT',
          'ctime': DateTime.utc(2026, 8, 5, 1).millisecondsSinceEpoch,
          'mtime': DateTime.utc(2026, 8, 5, 3, 19, 28).millisecondsSinceEpoch,
        },
      ],
    });
    final fills = BitunixPnlMapper.fills(
      {
        'tradeList': [
          {
            'tradeId': 'ambiguous',
            'orderId': 'close-order',
            'symbol': 'GRAMUSDT',
            'qty': '1',
            'price': '1.389',
            'realizedPNL': '-0.1',
            'fee': '0.01',
            'ctime': fillAt.millisecondsSinceEpoch,
            'reduceOnly': true,
          },
        ],
      },
      openPositions: const [],
      settlements: settlements.values,
    );

    expect(fills.verified, isFalse);
    expect(fills.values.single.positionId, isEmpty);
    expect(fills.warning, contains('could not be assigned'));
  });
}
''')

(root / 'test/trading_journal_foreground_merge_test.dart').write_text('''import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/trading_journal/data/database_trading_journal_store.dart';
import 'package:quantara_app/features/trading_journal/domain/trading_journal_models.dart';
import 'package:quantara_app/features/trading_journal/domain/trading_journal_projection.dart';

void main() {
  test('imports a newer foreground close event into durable journal', () {
    final plan = _plan();
    final entry = _event(
      eventId: 'entry',
      type: TradingJournalEventType.entryFilled,
      remainingQuantity: 42.9,
      price: 1.40,
    );
    final close = _event(
      eventId: 'stop-close',
      type: TradingJournalEventType.positionClosed,
      remainingQuantity: 0,
      price: 1.389,
      grossPnl: -0.2574,
      fee: 0.03575286,
      details: const {'closeReason': 'stop'},
    );
    final durable = TradingJournalLedger.empty()
        .appendPlan(plan)
        .appendEvent(entry);
    final foreground = durable.appendEvent(close);

    final merged = mergeTradingJournalLedgers(durable, foreground);
    final projection = TradingJournalProjector.project(
      ledger: merged,
      journalTradeId: plan.journalTradeId,
    );

    expect(
      merged.events.where((item) => item.eventId == 'stop-close'),
      hasLength(1),
    );
    expect(projection.state, TradingJournalTradeState.closed);
    expect(projection.closeReason, TradingJournalCloseReason.stop);
    expect(projection.remainingQuantity, 0);
    expect(projection.grossPnl, -0.2574);
    expect(projection.fees, 0.03575286);
  });
}

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
  targets: const [1.419, 1.41005, 1.42826],
  expectedRMultiples: const [1, 2, 3],
  confidencePercent: 70,
  confluence: const ['test'],
  regime: 'transition',
  rationale: 'physical canary regression',
  invalidation: 'stop',
  accountEquity: 29.81,
  riskPercent: 0.1,
  riskBudget: 0.02981,
  leverage: 10,
  expectedMargin: 6.006,
  passedGates: const ['isolated-margin'],
  blockedGates: const [],
  appVersion: 'test',
  strategyRulesVersion: 'v1',
  positionId: 'gram-position',
  entryOrderId: 'entry-order',
  clientId: 'q-local-gram',
);

TradingJournalEvent _event({
  required String eventId,
  required TradingJournalEventType type,
  required double remainingQuantity,
  required double price,
  double? grossPnl,
  double? fee,
  Map<String, Object?> details = const {},
}) => TradingJournalEvent(
  eventId: eventId,
  journalTradeId: 'local-live:gram-position',
  type: type,
  occurredAt: type == TradingJournalEventType.positionClosed
      ? DateTime.utc(2026, 8, 5, 3, 19, 14)
      : DateTime.utc(2026, 8, 5, 2),
  recordedAt: DateTime.utc(2026, 8, 5, 3, 20),
  source: TradingJournalFactSource.exchange,
  quality: TradingJournalFactQuality.confirmed,
  scope: TradingJournalScope.position,
  currency: 'USDT',
  asOf: DateTime.utc(2026, 8, 5, 3, 20),
  exchangeEventId: eventId,
  positionId: 'gram-position',
  orderId: eventId,
  tradeId: eventId,
  quantity: 42.9,
  price: price,
  grossPnl: grossPnl,
  fee: fee,
  funding: type == TradingJournalEventType.positionClosed ? 0 : null,
  remainingQuantity: remainingQuantity,
  details: details,
);
''')

(root / 'test/physical_canary_regression_source_test.dart').write_text('''import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('closed positions queue economics without occupying an execution slot', () {
    final source = File(
      'lib/features/auto_trade/application/local_live_trade_service.dart',
    ).readAsStringSync();
    expect(source, contains('_pendingJournalClosures'));
    expect(source, contains('_reconcilePendingJournalClosures'));
    expect(source, contains('_userRequestedEntries'));
    expect(source, contains('_entriesEnabled = _userRequestedEntries'));
  });

  test('refresh routes account, local status, and journal to truth sources', () {
    final page = File(
      'lib/features/owner_alpha/presentation/owner_alpha_page.dart',
    ).readAsStringSync();
    final autoTrade = File(
      'lib/features/owner_alpha/presentation/owner_alpha_auto_trade.dart',
    ).readAsStringSync();
    expect(page, contains('_refreshCurrentDestination'));
    expect(page, contains('await state.refreshAll()'));
    expect(page, contains('await _journalController.refresh()'));
    expect(page, contains('onRefresh: _refreshCurrentDestination'));
    expect(autoTrade, contains('Future<void> refreshAll()'));
    expect(autoTrade, contains('await _localController.refresh()'));
  });

  test('journal confirmation and closed lifecycle are neutral, not profit green', () {
    final source = File(
      'lib/features/trading_journal/presentation/trading_journal_view.dart',
    ).readAsStringSync();
    expect(
      source,
      contains('TradingJournalTradeState.closed => QuantaraColors.electricBlue'),
    );
    expect(
      source,
      contains('TradingJournalFactQuality.confirmed => QuantaraColors.cyan'),
    );
    expect(source, contains('_closeReasonColor'));
  });
}
''')
