import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/auto_trade/domain/local_live_trade_models.dart';

void main() {
  test('capital dashboard status round-trip preserves Guardian truth', () {
    final value = LocalLivePortfolioBudgetStatus(
      asOf: DateTime.utc(2026, 8, 23, 10),
      riskLimit: 10,
      riskConsumed: 4,
      riskAvailable: 6,
      openRisk: 3,
      pendingRisk: 1,
      ambiguousRisk: 0,
      reservedMargin: 20,
      spendableMargin: 80,
      accountFresh: true,
      allPositionsProtected: true,
      liveExecutionAllowed: true,
      blockReason: 'none',
      currentEquity: 940,
      peakEquity: 1000,
      drawdownFraction: 0.06,
      drawdownTier: 'soft',
      riskMultiplier: 0.5,
    );

    final restored = LocalLivePortfolioBudgetStatus.fromJson(value.toJson());
    expect(restored.currentEquity, 940);
    expect(restored.peakEquity, 1000);
    expect(restored.drawdownFraction, closeTo(0.06, 1e-12));
    expect(restored.drawdownTier, 'soft');
    expect(restored.riskMultiplier, 0.5);

    final legacyJson = Map<String, Object?>.from(value.toJson())
      ..remove('currentEquity')
      ..remove('peakEquity')
      ..remove('drawdownFraction')
      ..remove('drawdownTier')
      ..remove('riskMultiplier');
    final legacy = LocalLivePortfolioBudgetStatus.fromJson(legacyJson);
    expect(legacy.currentEquity, isNull);
    expect(legacy.peakEquity, isNull);
    expect(legacy.drawdownFraction, isNull);
    expect(legacy.drawdownTier, isNull);
    expect(legacy.riskMultiplier, isNull);
  });

  test('capital dashboard stays wired to the existing Local Live card', () {
    final guard = File(
      'lib/features/auto_trade/application/local_live_portfolio_execution_guard.dart',
    ).readAsStringSync();
    final service = File(
      'lib/features/auto_trade/application/local_live_trade_service.dart',
    ).readAsStringSync();
    final ui = File(
      'lib/features/owner_alpha/presentation/owner_alpha_auto_trade.dart',
    ).readAsStringSync();

    expect(
      guard,
      contains(
        '_lastCapitalGuardianSnapshot = await _capitalGuardianMonitor.refresh',
      ),
    );
    expect(service, contains('currentEquity: guardian?.currentEquity'));
    expect(service, contains('drawdownTier: guardian?.drawdownTier.name'));
    expect(ui, contains('سرمایه \${status.portfolioBudget!.currentEquity!'));
    expect(ui, contains('Equity \${status.portfolioBudget!.currentEquity!'));
    expect(ui, contains('افت سرمایه \${'));
    expect(ui, contains('Drawdown \${'));
    expect(ui, contains('openRisk.toStringAsFixed(3)'));
  });
}
