from pathlib import Path

root = Path('src/client/quantara_app')


def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text()
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{path}: expected one anchor, found {count}')
    path.write_text(text.replace(old, new, 1))


models = root / 'lib/features/auto_trade/domain/local_live_trade_models.dart'
text = models.read_text()
if 'final class LocalLivePortfolioBudgetStatus' not in text:
    marker = '\nfinal class LocalLiveTradeStatus {'
    budget = '''

final class LocalLivePortfolioBudgetStatus {
  const LocalLivePortfolioBudgetStatus({
    required this.asOf,
    required this.riskLimit,
    required this.riskConsumed,
    required this.riskAvailable,
    required this.openRisk,
    required this.pendingRisk,
    required this.ambiguousRisk,
    required this.reservedMargin,
    required this.spendableMargin,
    required this.accountFresh,
    required this.allPositionsProtected,
    required this.liveExecutionAllowed,
    required this.blockReason,
  });

  final DateTime asOf;
  final double riskLimit;
  final double riskConsumed;
  final double riskAvailable;
  final double openRisk;
  final double pendingRisk;
  final double ambiguousRisk;
  final double reservedMargin;
  final double spendableMargin;
  final bool accountFresh;
  final bool allPositionsProtected;
  final bool liveExecutionAllowed;
  final String blockReason;

  Map<String, Object?> toJson() => {
    'asOf': asOf.toUtc().toIso8601String(),
    'riskLimit': riskLimit,
    'riskConsumed': riskConsumed,
    'riskAvailable': riskAvailable,
    'openRisk': openRisk,
    'pendingRisk': pendingRisk,
    'ambiguousRisk': ambiguousRisk,
    'reservedMargin': reservedMargin,
    'spendableMargin': spendableMargin,
    'accountFresh': accountFresh,
    'allPositionsProtected': allPositionsProtected,
    'liveExecutionAllowed': liveExecutionAllowed,
    'blockReason': blockReason,
  };

  factory LocalLivePortfolioBudgetStatus.fromJson(
    Map<String, Object?> json,
  ) => LocalLivePortfolioBudgetStatus(
    asOf:
        DateTime.tryParse(json['asOf']?.toString() ?? '')?.toUtc() ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    riskLimit: (json['riskLimit'] as num?)?.toDouble() ?? 0,
    riskConsumed: (json['riskConsumed'] as num?)?.toDouble() ?? 0,
    riskAvailable: (json['riskAvailable'] as num?)?.toDouble() ?? 0,
    openRisk: (json['openRisk'] as num?)?.toDouble() ?? 0,
    pendingRisk: (json['pendingRisk'] as num?)?.toDouble() ?? 0,
    ambiguousRisk: (json['ambiguousRisk'] as num?)?.toDouble() ?? 0,
    reservedMargin: (json['reservedMargin'] as num?)?.toDouble() ?? 0,
    spendableMargin: (json['spendableMargin'] as num?)?.toDouble() ?? 0,
    accountFresh: json['accountFresh'] == true,
    allPositionsProtected: json['allPositionsProtected'] == true,
    liveExecutionAllowed: json['liveExecutionAllowed'] == true,
    blockReason: json['blockReason']?.toString() ?? 'unknown',
  );
}
'''
    if marker not in text:
        raise SystemExit('LocalLiveTradeStatus marker missing')
    models.write_text(text.replace(marker, budget + marker, 1))
    replace_once(
        models,
        '''    this.pnlProjection,
    this.consecutiveFailures = 0,''',
        '''    this.pnlProjection,
    this.portfolioBudget,
    this.consecutiveFailures = 0,''',
    )
    replace_once(
        models,
        '''  final TradingPnlProjection? pnlProjection;

  double? get effectiveSessionNetPnl =>''',
        '''  final TradingPnlProjection? pnlProjection;
  final LocalLivePortfolioBudgetStatus? portfolioBudget;

  double? get effectiveSessionNetPnl =>''',
    )
    replace_once(
        models,
        '''    'pnlProjection': pnlProjection?.toJson(),
    'consecutiveFailures': consecutiveFailures,''',
        '''    'pnlProjection': pnlProjection?.toJson(),
    'portfolioBudget': portfolioBudget?.toJson(),
    'consecutiveFailures': consecutiveFailures,''',
    )
    replace_once(
        models,
        '''    pnlProjection: _pnlProjectionFromJson(json['pnlProjection']),
    consecutiveFailures: (json['consecutiveFailures'] as num?)?.toInt() ?? 0,''',
        '''    pnlProjection: _pnlProjectionFromJson(json['pnlProjection']),
    portfolioBudget: _portfolioBudgetFromJson(json['portfolioBudget']),
    consecutiveFailures: (json['consecutiveFailures'] as num?)?.toInt() ?? 0,''',
    )
    text = models.read_text()
    marker = '\nTradingPnlProjection? _pnlProjectionFromJson(Object? value) {'
    helper = '''

LocalLivePortfolioBudgetStatus? _portfolioBudgetFromJson(Object? value) {
  if (value is Map<String, Object?>) {
    return LocalLivePortfolioBudgetStatus.fromJson(value);
  }
  if (value is Map<Object?, Object?>) {
    return LocalLivePortfolioBudgetStatus.fromJson(
      value.map((key, item) => MapEntry(key.toString(), item)),
    );
  }
  return null;
}
'''
    if marker not in text:
        raise SystemExit('PnL decoder marker missing')
    models.write_text(text.replace(marker, helper + marker, 1))

service = root / 'lib/features/auto_trade/application/local_live_trade_service.dart'
text = service.read_text()
if 'LocalLivePortfolioBudgetStatus? _portfolioBudget;' not in text:
    replace_once(
        service,
        '''  TradingPnlProjection? _sessionPnlProjection;
  String? _sessionId;''',
        '''  TradingPnlProjection? _sessionPnlProjection;
  LocalLivePortfolioBudgetStatus? _portfolioBudget;
  String? _sessionId;''',
    )
    replace_once(
        service,
        '''          _sessionPnlProjection = null;
          _portfolioGuard = null;''',
        '''          _sessionPnlProjection = null;
          _portfolioBudget = null;
          _portfolioGuard = null;''',
    )
    replace_once(
        service,
        '''        try {
          await _portfolioGuard!.reconcileRestartAndClosedPositions(
            managed: _managed,
            exchangePositions: positions,
            pnlProjection: account.authoritativePnl,
            now: DateTime.now().toUtc(),
          );
        } on LocalLiveTradeSafeException catch (error) {
          _entriesEnabled = false;
          cycleWarning = error.message;
          _auditEvent('portfolio_ledger_block', error.message);
        }''',
        '''        try {
          final now = DateTime.now().toUtc();
          final allOpenPositionsProtected =
              _managed.length ==
                  positions.where((item) => item.quantity > 0).length &&
              _managed.every(
                (item) => item.profitLockProgress.warning == null,
              );
          await _portfolioGuard!.reconcileRestartAndClosedPositions(
            managed: _managed,
            exchangePositions: positions,
            pnlProjection: account.authoritativePnl,
            now: now,
          );
          final snapshot = await _portfolioGuard!.snapshot(
            account: account,
            allOpenPositionsProtected: allOpenPositionsProtected,
            now: now,
          );
          _portfolioBudget = LocalLivePortfolioBudgetStatus(
            asOf: now,
            riskLimit: snapshot.dailyRisk.limit,
            riskConsumed: snapshot.dailyRisk.consumed,
            riskAvailable: snapshot.dailyRisk.available,
            openRisk: snapshot.dailyRisk.openRisk,
            pendingRisk: snapshot.dailyRisk.pendingRisk,
            ambiguousRisk: snapshot.dailyRisk.ambiguousRisk,
            reservedMargin: snapshot.margin.reservedMargin,
            spendableMargin: snapshot.margin.spendable,
            accountFresh: snapshot.accountFresh,
            allPositionsProtected: snapshot.allPositionsProtected,
            liveExecutionAllowed: snapshot.liveExecutionAllowed,
            blockReason: snapshot.blockReason.name,
          );
        } on LocalLiveTradeSafeException catch (error) {
          _entriesEnabled = false;
          cycleWarning = error.message;
          _auditEvent('portfolio_ledger_block', error.message);
        }''',
    )
    replace_once(
        service,
        '''      pnlProjection: _sessionPnlProjection,
      consecutiveFailures: _consecutiveFailures,''',
        '''      pnlProjection: _sessionPnlProjection,
      portfolioBudget: _portfolioBudget,
      consecutiveFailures: _consecutiveFailures,''',
    )

ui = root / 'lib/features/owner_alpha/presentation/owner_alpha_auto_trade.dart'
text = ui.read_text()
if "'ریسک آزاد" not in text:
    old = '''              StatusPill(
                label: _t(
                  '${status.openPositionCount}/$_maximumConcurrentPositions پوزیشن باز',
                  '${status.openPositionCount}/$_maximumConcurrentPositions open',
                ),
                color: status.openPositionCount > 0
                    ? QuantaraColors.warning
                    : QuantaraColors.cyan,
              ),
              StatusPill(
                label: status.effectiveSessionNetPnl == null'''
    new = '''              StatusPill(
                label: _t(
                  '${status.openPositionCount}/$_maximumConcurrentPositions پوزیشن باز',
                  '${status.openPositionCount}/$_maximumConcurrentPositions open',
                ),
                color: status.openPositionCount > 0
                    ? QuantaraColors.warning
                    : QuantaraColors.cyan,
              ),
              if (status.portfolioBudget != null)
                StatusPill(
                  label: _t(
                    'ریسک آزاد ${status.portfolioBudget!.riskAvailable.toStringAsFixed(3)} / ${status.portfolioBudget!.riskLimit.toStringAsFixed(3)} USDT',
                    'Risk free ${status.portfolioBudget!.riskAvailable.toStringAsFixed(3)} / ${status.portfolioBudget!.riskLimit.toStringAsFixed(3)} USDT',
                  ),
                  color: status.portfolioBudget!.ambiguousRisk > 0
                      ? QuantaraColors.danger
                      : status.portfolioBudget!.riskAvailable > 0
                      ? QuantaraColors.cyan
                      : QuantaraColors.warning,
                ),
              if (status.portfolioBudget != null)
                StatusPill(
                  label: _t(
                    'مارجین رزرو ${status.portfolioBudget!.reservedMargin.toStringAsFixed(2)} · قابل‌استفاده ${status.portfolioBudget!.spendableMargin.toStringAsFixed(2)}',
                    'Margin reserved ${status.portfolioBudget!.reservedMargin.toStringAsFixed(2)} · spendable ${status.portfolioBudget!.spendableMargin.toStringAsFixed(2)}',
                  ),
                  color: status.portfolioBudget!.accountFresh &&
                          status.portfolioBudget!.allPositionsProtected
                      ? QuantaraColors.violet
                      : QuantaraColors.warning,
                ),
              StatusPill(
                label: status.effectiveSessionNetPnl == null'''
    if old not in text:
        raise SystemExit('Auto Trade status pills anchor missing')
    ui.write_text(text.replace(old, new, 1))

(root / 'test/local_live_portfolio_budget_status_test.dart').write_text('''import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/auto_trade/domain/local_live_trade_models.dart';

void main() {
  test('round-trips atomic portfolio budget status through service payload', () {
    final status = LocalLiveTradeStatus(
      state: LocalLiveTradeState.running,
      updatedAt: DateTime.utc(2026, 8, 5, 4, 45),
      message: 'running',
      openPositionCount: 1,
      entriesEnabled: true,
      portfolioBudget: LocalLivePortfolioBudgetStatus(
        asOf: DateTime.utc(2026, 8, 5, 4, 45),
        riskLimit: 0.30,
        riskConsumed: 0.075,
        riskAvailable: 0.225,
        openRisk: 0.075,
        pendingRisk: 0,
        ambiguousRisk: 0,
        reservedMargin: 1.25,
        spendableMargin: 26.40,
        accountFresh: true,
        allPositionsProtected: true,
        liveExecutionAllowed: true,
        blockReason: 'none',
      ),
    );

    final restored = LocalLiveTradeStatus.fromJson(status.toJson());

    expect(restored.portfolioBudget, isNotNull);
    expect(restored.portfolioBudget!.riskLimit, 0.30);
    expect(restored.portfolioBudget!.riskAvailable, 0.225);
    expect(restored.portfolioBudget!.openRisk, 0.075);
    expect(restored.portfolioBudget!.reservedMargin, 1.25);
    expect(restored.portfolioBudget!.spendableMargin, 26.40);
    expect(restored.portfolioBudget!.liveExecutionAllowed, isTrue);
    expect(restored.portfolioBudget!.blockReason, 'none');
  });
}
''')
