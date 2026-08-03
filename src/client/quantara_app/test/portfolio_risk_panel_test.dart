import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/portfolio_risk/application/portfolio_risk_coordinator.dart';
import 'package:quantara_app/features/portfolio_risk/application/portfolio_risk_simulation_controller.dart';
import 'package:quantara_app/features/portfolio_risk/data/portfolio_risk_ledger_store.dart';
import 'package:quantara_app/features/portfolio_risk/domain/portfolio_risk_models.dart';
import 'package:quantara_app/features/portfolio_risk/presentation/portfolio_risk_panel.dart';

void main() {
  PortfolioRiskSimulationController controller() =>
      PortfolioRiskSimulationController(
        coordinator: PortfolioRiskCoordinator(
          store: _MemoryPortfolioRiskStore(),
          policy: const PortfolioRiskPolicy(maximumDirectionRiskFraction: 1),
          defaultDailyRiskLimit: 10,
        ),
        account: PortfolioAccountTruth(
          asOf: DateTime.utc(2026, 8, 4),
          fresh: true,
          allOpenPositionsProtected: true,
          marginMode: 'isolated',
          freeMargin: 100,
          usedMargin: 0,
          maintenanceMargin: 0,
          pendingMarginReservations: 0,
          safetyBuffer: 10,
          feeReserve: 1,
        ),
      );

  Widget harness({
    required TextDirection direction,
    required PortfolioRiskSimulationController controller,
    double textScale = 1,
    Size size = const Size(430, 900),
  }) => MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(
        size: size,
        textScaler: TextScaler.linear(textScale),
      ),
      child: Directionality(
        textDirection: direction,
        child: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(8),
            child: PortfolioRiskPanel(controller: controller),
          ),
        ),
      ),
    ),
  );

  testWidgets('Persian RTL panel demonstrates 10, 3, 7 budgeting', (
    tester,
  ) async {
    final simulation = controller();
    addTearDown(simulation.dispose);
    await tester.pumpWidget(
      harness(direction: TextDirection.rtl, controller: simulation),
    );
    await tester.pumpAndSettle();

    expect(find.text('بودجه ریسک پرتفوی'), findsOneWidget);
    expect(find.text('شبیه‌سازی'), findsOneWidget);
    expect(find.text('10.00 USDT'), findsAtLeastNWidgets(1));

    await tester.tap(find.text('رزرو ۳ USDT'));
    await tester.pumpAndSettle();
    expect(find.text('7.00 USDT'), findsAtLeastNWidgets(1));

    await tester.tap(find.text('رزرو ۴ USDT'));
    await tester.pumpAndSettle();
    expect(find.text('3.00 USDT'), findsAtLeastNWidgets(1));
    expect(find.text('BTCUSDT'), findsOneWidget);
    expect(find.text('ETHUSDT'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('English LTR panel shows stale and blocked states', (
    tester,
  ) async {
    final simulation = controller();
    addTearDown(simulation.dispose);
    await tester.pumpWidget(
      harness(direction: TextDirection.ltr, controller: simulation),
    );
    await tester.pumpAndSettle();

    expect(find.text('Portfolio risk budget'), findsOneWidget);
    expect(find.text('Simulation'), findsOneWidget);
    await tester.tap(find.text('Simulate stale data'));
    await tester.pumpAndSettle();
    expect(
      find.text('Private account truth is stale; new entry is blocked.'),
      findsOneWidget,
    );
    expect(find.text('Restore fresh data'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('large text mobile and wide desktop layouts do not overflow', (
    tester,
  ) async {
    final mobile = controller();
    addTearDown(mobile.dispose);
    await tester.pumpWidget(
      harness(
        direction: TextDirection.rtl,
        controller: mobile,
        textScale: 2,
        size: const Size(360, 1000),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(PortfolioRiskPanel), findsOneWidget);
    expect(tester.takeException(), isNull);

    final desktop = controller();
    addTearDown(desktop.dispose);
    await tester.pumpWidget(
      harness(
        direction: TextDirection.ltr,
        controller: desktop,
        textScale: 1.4,
        size: const Size(1200, 900),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Portfolio risk budget'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('risk rejection and reset remain visible and deterministic', (
    tester,
  ) async {
    final simulation = controller();
    addTearDown(simulation.dispose);
    await tester.pumpWidget(
      harness(direction: TextDirection.ltr, controller: simulation),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Reserve 3 USDT'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Try rejected 8'));
    await tester.pumpAndSettle();
    expect(
      find.text('The remaining risk budget is insufficient.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Reset example'));
    await tester.pumpAndSettle();
    expect(find.text('There are no active reservations yet.'), findsOneWidget);
    expect(find.text('10.00 USDT'), findsAtLeastNWidgets(1));
  });
}

final class _MemoryPortfolioRiskStore implements PortfolioRiskLedgerStore {
  PortfolioRiskLedger? _ledger;

  @override
  Future<PortfolioRiskLedger?> load() async => _ledger;

  @override
  Future<void> save(PortfolioRiskLedger ledger) async {
    _ledger = PortfolioRiskLedger.fromJson(ledger.toJson());
  }
}
