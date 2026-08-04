import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/portfolio_risk/application/portfolio_risk_coordinator.dart';
import 'package:quantara_app/features/portfolio_risk/application/portfolio_risk_simulation_controller.dart';
import 'package:quantara_app/features/portfolio_risk/data/portfolio_risk_ledger_store.dart';
import 'package:quantara_app/features/portfolio_risk/domain/portfolio_risk_models.dart';

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

  test('freshness transition publishes a stale fail-closed snapshot', () async {
    final simulation = controller();
    addTearDown(simulation.dispose);
    var notifications = 0;
    simulation.addListener(() => notifications++);

    await simulation.initialize();
    await simulation.toggleFreshness();

    expect(simulation.accountFresh, isFalse);
    expect(
      simulation.snapshot?.blockReason,
      PortfolioEntryBlockReason.staleAccount,
    );
    expect(notifications, greaterThan(0));
  });

  test('rejected reservation publishes the exact risk decision', () async {
    final simulation = controller();
    addTearDown(simulation.dispose);

    await simulation.initialize();
    await simulation.reserveExample(3);
    await simulation.reserveExample(8);

    expect(simulation.lastDecision?.allowed, isFalse);
    expect(
      simulation.lastDecision?.reason,
      PortfolioEntryBlockReason.riskBudgetInsufficient,
    );
    expect(simulation.snapshot?.dailyRisk.available, 7);
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
