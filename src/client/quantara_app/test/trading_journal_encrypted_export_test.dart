import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/trading_journal/data/trading_journal_export.dart';
import 'package:quantara_app/features/trading_journal/domain/trading_journal_models.dart';

void main() {
  test('AES-GCM encrypted export round-trips with passphrase', () async {
    final plan = TradingJournalPlan(
      journalTradeId: 'encrypted-1',
      setupId: 'setup-1',
      analysisVersion: 'v1',
      symbol: 'XRPUSDT',
      market: 'USDT_PERPETUAL',
      timeframe: '15m',
      direction: TradingJournalDirection.short,
      strategy: 'structure',
      cadence: 'balanced',
      source: TradingJournalSource.localLive,
      decidedAt: DateTime.utc(2026, 8, 3),
      decisionPrice: 1.0665,
      entryLower: 1.066,
      entryUpper: 1.067,
      plannedEntry: 1.0665,
      originalStopLoss: 1.0691,
      targets: const [1.0603, 1.0567, 1.0531],
      expectedRMultiples: const [2.38, 3.77, 5.15],
      confidencePercent: 82,
      confluence: const ['15m', '1h'],
      regime: 'trend',
      rationale: 'fixture',
      invalidation: 'fixture',
      accountEquity: 100,
      riskPercent: 0.5,
      riskBudget: 0.5,
      leverage: 10,
      expectedMargin: 2.3,
      passedGates: const ['isolated'],
      blockedGates: const [],
      appVersion: '1.2.0',
      strategyRulesVersion: 'rules-1',
      clientId: 'private-correlation-id',
    );
    final ledger = TradingJournalLedger.empty().appendPlan(plan);

    final encrypted = await TradingJournalExport.toEncryptedJson(
      ledger,
      passphrase: 'correct horse battery staple',
    );
    final restored = await TradingJournalExport.fromEncryptedJson(
      encrypted,
      passphrase: 'correct horse battery staple',
    );

    expect(encrypted, isNot(contains('XRPUSDT')));
    expect(encrypted, isNot(contains('private-correlation-id')));
    expect(restored.plans.single.symbol, 'XRPUSDT');
    expect(restored.plans.single.clientId, isNull);
  });

  test('wrong passphrase cannot authenticate encrypted export', () async {
    final ledger = TradingJournalLedger.empty();
    final encrypted = await TradingJournalExport.toEncryptedJson(
      ledger,
      passphrase: 'first-passphrase',
    );

    await expectLater(
      TradingJournalExport.fromEncryptedJson(
        encrypted,
        passphrase: 'wrong-passphrase',
      ),
      throwsA(isA<Object>()),
    );
  });
}
