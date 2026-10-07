import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/owner_alpha/application/trading_evidence_export.dart';
import 'package:quantara_app/features/owner_alpha/domain/owner_alpha_models.dart';

void main() {
  test(
    'export distinguishes interim targets from terminal net results and omits notes',
    () {
      final setups = [
        _entry('winner', SignalOutcome.tp3, 4),
        _entry('loser', SignalOutcome.stopped, -3),
        _entry('protected-runner', SignalOutcome.stopped, 1),
        _entry('interim', SignalOutcome.tp1, 20),
        _entry('never-entered', SignalOutcome.expiredUntriggered, null),
      ];
      final json = TradingEvidenceExport.encode(
        generatedAt: _at,
        setups: setups,
      );
      final payload = jsonDecode(json) as Map<String, dynamic>;
      expect(payload['scope'], 'trading-evidence');
      final sections = payload['sections'] as Map<String, dynamic>;
      final history = sections['setupHistory'] as List<dynamic>;
      expect(history, hasLength(5));
      expect(json, isNot(contains('private-user-note')));
      expect(history.first['entryLower'], 99);
      expect(history.first['stopLoss'], 98);
      expect(history.first['strategyVersion'], 'fixture/1');
      final summary =
          (sections['strategySummary'] as Map<String, dynamic>).values.single;
      expect(summary['terminalCount'], 3);
      expect(summary['wins'], 2);
      expect(summary['losses'], 1);
      expect(summary['netSimulatedPnl'], 2);
      expect(
        sections['evaluationContract']['type'],
        'simulated-setups-not-exchange-executions',
      );
    },
  );
}

final _at = DateTime.utc(2026, 10, 4);
SignalJournalEntry _entry(String id, SignalOutcome outcome, double? pnl) =>
    SignalJournalEntry(
      setupId: id,
      symbol: 'BTCUSDT',
      timeframe: '15m',
      direction: TradeDirection.long,
      strategy: AnalysisStrategy.structureZones,
      strategyVersion: 'fixture/1',
      createdAt: _at,
      validUntil: _at.add(const Duration(hours: 1)),
      entryLower: 99,
      entryUpper: 100,
      stopLoss: 98,
      targets: const [102, 104, 106],
      maximumLoss: 10,
      positionSize: 5,
      notionalValue: 500,
      estimatedRoundTripCosts: 1,
      recommendedLeverage: 5,
      maximumSafeLeverage: 8,
      selectedLeverage: 5,
      summary: 'fixture',
      invalidation: 'fixture',
      note: 'private-user-note',
      outcome: outcome,
      simulatedPnl: pnl,
      resolvedAt: _at,
    );
