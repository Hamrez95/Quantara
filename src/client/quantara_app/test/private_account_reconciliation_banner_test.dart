import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/auto_trade/domain/auto_trade_models.dart';
import 'package:quantara_app/features/auto_trade/domain/private_account_reconciliation.dart';
import 'package:quantara_app/features/auto_trade/presentation/private_account_reconciliation_banner.dart';

void main() {
  testWidgets(
    'stale flat account does not claim existing-position management',
    (tester) async {
      final state = _staleState(openPositionCount: 0);

      await _pumpBanner(tester, state: state);

      expect(find.textContaining('Account information needs refresh'), findsOne);
      expect(find.textContaining('No open position is known'), findsOne);
      expect(find.textContaining('existing-position management'), findsNothing);
      expect(find.byIcon(Icons.sync_rounded), findsOne);
    },
  );

  testWidgets(
    'stale non-flat account keeps risk-reducing management wording',
    (tester) async {
      final state = _staleState(openPositionCount: 1);

      await _pumpBanner(tester, state: state);

      expect(find.textContaining('Private account truth is stale'), findsOne);
      expect(find.textContaining('confirmed open positions'), findsOne);
      expect(find.byIcon(Icons.sync_problem_rounded), findsOne);
    },
  );

  testWidgets(
    'divergent state stays high severity even when snapshot is flat',
    (tester) async {
      final syncedAt = DateTime.utc(2026, 8, 31, 12);
      final state = PrivateAccountReconciliationState.fresh(
        snapshot: _snapshot(syncedAt: syncedAt, openPositionCount: 0),
        cycleId: 'cycle-divergent',
        completedAt: syncedAt,
      ).observeLocalLiveOpenPositions(
        openPositionCount: 1,
        observedAt: syncedAt.add(const Duration(seconds: 1)),
      );

      await _pumpBanner(tester, state: state);

      expect(find.textContaining('disagrees with Local Live'), findsOne);
      expect(find.byIcon(Icons.sync_problem_rounded), findsOne);
    },
  );

  testWidgets(
    'Persian flat-account copy is truthful and recovery-oriented',
    (tester) async {
      final state = _staleState(openPositionCount: 0).markRefreshing(
        DateTime.utc(2026, 8, 31, 12, 2),
      );

      await _pumpBanner(tester, state: state, persian: true);

      expect(find.textContaining('اطلاعات حساب نیاز به تازه‌سازی دارد'), findsOne);
      expect(find.textContaining('هیچ پوزیشن بازی'), findsOne);
      expect(find.textContaining('در حال تازه‌سازی'), findsOne);
    },
  );

  testWidgets('fresh truth renders no warning banner', (tester) async {
    final syncedAt = DateTime.utc(2026, 8, 31, 12);

    await _pumpBanner(
      tester,
      state: PrivateAccountReconciliationState.fresh(
        snapshot: _snapshot(syncedAt: syncedAt, openPositionCount: 0),
        cycleId: 'fresh-cycle',
        completedAt: syncedAt,
      ),
    );

    expect(find.byIcon(Icons.sync_problem_rounded), findsNothing);
    expect(find.byIcon(Icons.sync_rounded), findsNothing);
  });
}

Future<void> _pumpBanner(
  WidgetTester tester, {
  required PrivateAccountReconciliationState state,
  bool persian = false,
}) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: PrivateAccountReconciliationBanner(
        state: state,
        persian: persian,
      ),
    ),
  ),
);

PrivateAccountReconciliationState _staleState({
  required int openPositionCount,
}) {
  final syncedAt = DateTime.utc(2026, 8, 31, 12);
  return PrivateAccountReconciliationState.fresh(
    snapshot: _snapshot(
      syncedAt: syncedAt,
      openPositionCount: openPositionCount,
    ),
    cycleId: 'cycle-stale',
    completedAt: syncedAt,
  ).evaluateFreshness(
    now: syncedAt.add(const Duration(minutes: 2)),
    staleAfter: const Duration(seconds: 45),
  );
}

AutoTradeAccountSnapshot _snapshot({
  required DateTime syncedAt,
  required int openPositionCount,
}) => AutoTradeAccountSnapshot(
  marginCoin: 'USDT',
  available: 29.88,
  frozen: 0,
  positionMargin: openPositionCount == 0 ? 0 : 2,
  crossUnrealizedPnl: 0,
  isolatedUnrealizedPnl: 0,
  positionMode: 'HEDGE',
  positions: List.generate(
    openPositionCount,
    (index) => AutoTradePosition(
      positionId: 'position-$index',
      symbol: 'BTCUSDT',
      quantity: 0.001,
      side: 'LONG',
      marginMode: 'ISOLATION',
      positionMode: 'HEDGE',
      leverage: 2,
      margin: 2,
      unrealizedPnl: 0,
      liquidationPrice: 10000,
      averageOpenPrice: 50000,
    ),
  ),
  orders: const [],
  syncedAt: syncedAt,
);
