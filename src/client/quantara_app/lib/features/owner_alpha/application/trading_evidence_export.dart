import 'dart:convert';

import '../../auto_trade/application/local_live_diagnostic_bundle.dart';
import '../../auto_trade/domain/trading_pnl_projection.dart';
import '../domain/owner_alpha_models.dart';

abstract final class TradingEvidenceExport {
  static String encode({
    required DateTime generatedAt,
    required List<SignalJournalEntry> setups,
    TradingPnlProjection? exchangePnl,
  }) {
    final byStrategy = <String, Map<String, Object?>>{};
    for (final entry in setups) {
      final evaluationVersion =
          entry.outcomeEvaluationVersion ?? 'legacy-unversioned';
      final key =
          '${entry.strategy.name}/${entry.strategyVersion}|$evaluationVersion';
      final bucket = byStrategy.putIfAbsent(
        key,
        () => {
          'evaluationVersion': evaluationVersion,
          'count': 0,
          'terminalCount': 0,
          'wins': 0,
          'losses': 0,
          'breakeven': 0,
          'netSimulatedPnl': 0.0,
        },
      );
      bucket['count'] = (bucket['count'] as int) + 1;
      // TP1/TP2 are interim marks, not fully closed trade returns.
      if (!entry.hasTerminalOutcome ||
          entry.outcome == SignalOutcome.expiredUntriggered ||
          entry.simulatedPnl == null ||
          !entry.simulatedPnl!.isFinite) {
        continue;
      }
      final pnl = entry.simulatedPnl!;
      bucket['terminalCount'] = (bucket['terminalCount'] as int) + 1;
      final result = pnl > 0
          ? 'wins'
          : pnl < 0
          ? 'losses'
          : 'breakeven';
      bucket[result] = (bucket[result] as int) + 1;
      bucket['netSimulatedPnl'] = (bucket['netSimulatedPnl'] as double) + pnl;
    }
    final payload = LocalLiveDiagnosticBundle.build(
      generatedAt: generatedAt,
      sections: {
        'evaluationContract': {
          'version': 'closed-candle-replay/2',
          'type': 'simulated-setups-not-exchange-executions',
          'intrabarPolicy': 'stop-first-when-order-is-unknown',
          'legacyResults':
              'Stored terminal results are preserved and grouped separately as legacy-unversioned.',
          'coverage':
              'All setup records currently retained on this device; not a claim of complete market history.',
        },
        'setupHistory': [
          for (final entry in setups)
            Map<String, Object?>.of(entry.toJson())..remove('note'),
        ],
        'strategySummary': byStrategy,
        if (exchangePnl != null) 'exchangeAccounting': exchangePnl.toJson(),
      },
    );
    payload['scope'] = 'trading-evidence';
    return const JsonEncoder.withIndent('  ').convert(payload);
  }
}
