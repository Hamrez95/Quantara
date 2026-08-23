import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/core/persistence/quantara_durable_database.dart';
import 'package:quantara_app/features/auto_trade/application/local_live_capital_guardian_monitor.dart';
import 'package:quantara_app/features/portfolio_risk/data/portfolio_risk_ledger_store.dart';
import 'package:quantara_app/features/portfolio_risk/domain/capital_guardian.dart';
import 'package:quantara_app/features/portfolio_risk/domain/portfolio_risk_models.dart';
import 'package:sembast/sembast_memory.dart';

void main() {
  final now = DateTime.utc(2026, 8, 19, 12);

  Future<
    ({
      SembastQuantaraDurableDatabase database,
      DatabasePortfolioRiskLedgerStore store,
      LocalLiveCapitalGuardianMonitor monitor,
    })
  >
  harness(String path) async {
    final database = SembastQuantaraDurableDatabase(
      factory: databaseFactoryMemory,
      path: path,
    );
    await database.initialize();
    final factory = () async => database;
    final store = DatabasePortfolioRiskLedgerStore(
      databaseFactory: factory,
      recordKey: localLivePortfolioRiskLedgerRecordKey,
    );
    await store.save(
      PortfolioRiskLedger.initial(
        now: now,
        dailyRiskLimit: 10,
        timezoneOffsetMinutes: 0,
      ),
    );
    return (
      database: database,
      store: store,
      monitor: LocalLiveCapitalGuardianMonitor(
        databaseFactory: factory,
        riskStore: store,
      ),
    );
  }

  test('live equity drawdown drives soft and hard Guardian tiers', () async {
    final testHarness = await harness('local-live-capital-tiers.db');
    final monitor = testHarness.monitor;

    final initial = await monitor.refresh(accountEquity: 1000, now: now);
    expect(initial.currentEquity, 1000);
    expect(initial.peakEquity, 1000);
    expect(initial.drawdownFraction, 0);
    expect(initial.drawdownTier, CapitalGuardianDrawdownTier.normal);
    expect(initial.riskMultiplier, 1);
    expect(initial.asOf.isUtc, isTrue);

    final soft = await monitor.refresh(
      accountEquity: 940,
      now: now.add(const Duration(minutes: 1)),
    );
    expect(soft.peakEquity, 1000);
    expect(soft.drawdownFraction, closeTo(0.06, 1e-12));
    expect(soft.drawdownTier, CapitalGuardianDrawdownTier.soft);
    expect(soft.riskMultiplier, 0.5);

    final hard = await monitor.refresh(
      accountEquity: 890,
      now: now.add(const Duration(minutes: 2)),
    );
    expect(hard.drawdownFraction, closeTo(0.11, 1e-12));
    expect(hard.drawdownTier, CapitalGuardianDrawdownTier.hardStop);
    expect(hard.riskMultiplier, 0);
  });

  test('restart preserves the high-water mark and recovery state', () async {
    final testHarness = await harness('local-live-capital-restart.db');
    final factory = () async => testHarness.database;
    await testHarness.monitor.refresh(accountEquity: 1000, now: now);
    await testHarness.monitor.refresh(
      accountEquity: 890,
      now: now.add(const Duration(minutes: 1)),
    );

    final restarted = LocalLiveCapitalGuardianMonitor(
      databaseFactory: factory,
      riskStore: DatabasePortfolioRiskLedgerStore(
        databaseFactory: factory,
        recordKey: localLivePortfolioRiskLedgerRecordKey,
      ),
    );
    final restored = await restarted.load();
    expect(restored, isNotNull);
    expect(restored!.peakEquity, 1000);
    expect(restored.currentEquity, 890);
    expect(restored.drawdownTier, CapitalGuardianDrawdownTier.hardStop);
    expect(restored.asOf.isUtc, isTrue);

    final recovering = await restarted.refresh(
      accountEquity: 950,
      now: now.add(const Duration(minutes: 2)),
    );
    expect(recovering.peakEquity, 1000);
    expect(recovering.drawdownFraction, closeTo(0.05, 1e-12));
    expect(recovering.drawdownTier, CapitalGuardianDrawdownTier.recovery);
    expect(recovering.riskMultiplier, 0.25);
  });

  test(
    'a new equity high advances the durable peak without adding risk',
    () async {
      final testHarness = await harness('local-live-capital-peak.db');
      await testHarness.monitor.refresh(accountEquity: 1000, now: now);
      final higher = await testHarness.monitor.refresh(
        accountEquity: 1100,
        now: now.add(const Duration(minutes: 1)),
      );

      expect(higher.currentEquity, 1100);
      expect(higher.peakEquity, 1100);
      expect(higher.drawdownFraction, 0);
      expect(higher.openRisk, 0);
      expect(higher.remainingRisk, 10);
    },
  );

  test('invalid account equity fails closed', () async {
    final testHarness = await harness('local-live-capital-invalid.db');

    await expectLater(
      testHarness.monitor.refresh(accountEquity: 0, now: now),
      throwsFormatException,
    );
    await expectLater(
      testHarness.monitor.refresh(accountEquity: double.nan, now: now),
      throwsFormatException,
    );
  });
}
