import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/auto_trade/domain/auto_trade_models.dart';
import 'package:quantara_app/features/auto_trade/domain/private_account_reconciliation.dart';
import 'package:quantara_app/features/auto_trade/presentation/private_account_reconciliation_banner.dart';

void main() {
  testWidgets(
    'stale banner explains fail-closed entry and ongoing management',
    (tester) async {
      final syncedAt = DateTime.utc(2026, 8, 3, 11, 27);
      final snapshot = AutoTradeAccountSnapshot(
        marginCoin: 'USDT',
        available: 27.85,
        frozen: 0,
        positionMargin: 2.30,
        crossUnrealizedPnl: 0,
        isolatedUnrealizedPnl: 0.0021,
        positionMode: 'HEDGE',
        positions: const [
          AutoTradePosition(
            positionId: 'xrp-position-1',
            symbol: 'XRPUSDT',
            quantity: 21.4,
            side: 'SHORT',
            marginMode: 'ISOLATION',
            positionMode: 'HEDGE',
            leverage: 10,
            margin: 2.30,
            unrealizedPnl: 0.0021,
            liquidationPrice: 1.12,
            averageOpenPrice: 1.0665,
          ),
        ],
        orders: const [],
        syncedAt: syncedAt,
      );
      final stale =
          PrivateAccountReconciliationState.fresh(
            snapshot: snapshot,
            cycleId: 'cycle-physical-xrp',
            completedAt: syncedAt,
          ).evaluateFreshness(
            now: syncedAt.add(const Duration(minutes: 2)),
            staleAfter: const Duration(seconds: 45),
          );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PrivateAccountReconciliationBanner(
              state: stale,
              persian: false,
            ),
          ),
        ),
      );

      expect(find.textContaining('Private account truth is stale'), findsOne);
      expect(find.textContaining('New entries are blocked'), findsOne);
      expect(find.textContaining('management continues'), findsOne);
      expect(find.byIcon(Icons.sync_problem_rounded), findsOne);
    },
  );

  testWidgets('fresh truth renders no warning banner', (tester) async {
    final syncedAt = DateTime.utc(2026, 8, 3, 11, 27);
    final snapshot = AutoTradeAccountSnapshot(
      marginCoin: 'USDT',
      available: 30,
      frozen: 0,
      positionMargin: 0,
      crossUnrealizedPnl: 0,
      isolatedUnrealizedPnl: 0,
      positionMode: 'HEDGE',
      positions: const [],
      orders: const [],
      syncedAt: syncedAt,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PrivateAccountReconciliationBanner(
            state: PrivateAccountReconciliationState.fresh(
              snapshot: snapshot,
              cycleId: 'fresh-cycle',
              completedAt: syncedAt,
            ),
            persian: false,
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.sync_problem_rounded), findsNothing);
  });
}
