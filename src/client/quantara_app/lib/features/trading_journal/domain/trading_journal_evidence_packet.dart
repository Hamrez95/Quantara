import 'trading_journal_models.dart';
import 'trading_journal_projection.dart';

abstract final class TradingJournalEvidencePacketBuilder {
  static List<Map<String, Object?>> buildAll(TradingJournalLedger ledger) =>
      ledger.plans.map((plan) => build(ledger, plan)).toList(growable: false);

  static Map<String, Object?> build(
    TradingJournalLedger ledger,
    TradingJournalPlan plan,
  ) {
    final projection = TradingJournalProjector.project(
      ledger: ledger,
      journalTradeId: plan.journalTradeId,
    );
    final events = ledger.events
        .where((event) => event.journalTradeId == plan.journalTradeId)
        .toList(growable: false);
    final close = _authoritativeClose(events);
    final entry = events
        .where(
          (event) =>
              event.type == TradingJournalEventType.entryFilled ||
              event.type == TradingJournalEventType.entryPartiallyFilled,
        )
        .firstOrNull;
    final initialStopDistancePercent = plan.plannedEntry <= 0
        ? null
        : (plan.plannedEntry - plan.originalStopLoss).abs() /
              plan.plannedEntry *
              100;
    final stopSlippagePercent =
        close?.price == null ||
            plan.originalStopLoss <= 0 ||
            projection.closeReason != TradingJournalCloseReason.stop
        ? null
        : switch (plan.direction) {
            TradingJournalDirection.long =>
              (plan.originalStopLoss - close!.price!) /
                  plan.originalStopLoss *
                  100,
            TradingJournalDirection.short =>
              (close!.price! - plan.originalStopLoss) /
                  plan.originalStopLoss *
                  100,
            TradingJournalDirection.wait => null,
          };

    return {
      'schemaVersion': 1,
      'journalTradeId': plan.journalTradeId,
      'rawFacts': {
        'plan': plan.toJson(),
        'events': events.map((event) => event.toJson()).toList(growable: false),
      },
      'decisionTime': {
        'symbol': plan.symbol,
        'timeframe': plan.timeframe,
        'direction': plan.direction.name,
        'setupId': plan.setupId,
        'strategy': plan.strategy,
        'strategyVersion': plan.strategyRulesVersion,
        'analysisVersion': plan.analysisVersion,
        'cadence': plan.cadence,
        'marketRegime': plan.regime,
        'confidencePercent': plan.confidencePercent,
        'reasons': plan.confluence,
        'rationale': plan.rationale,
        'invalidation': plan.invalidation,
      },
      'indicatorSnapshot': {
        'captured': plan.indicatorSnapshot.isNotEmpty,
        'values': plan.indicatorSnapshot,
        'note': plan.indicatorSnapshot.isEmpty
            ? 'Indicator values were not persisted at this journal boundary; no values were fabricated.'
            : 'Technical indicators captured from the closed-candle decision snapshot.',
      },
      'executionPlan': {
        'decisionPrice': plan.decisionPrice,
        'entryZone': {'lower': plan.entryLower, 'upper': plan.entryUpper},
        'plannedEntry': plan.plannedEntry,
        'actualEntry': projection.entryPrice,
        'originalStopLoss': plan.originalStopLoss,
        'targets': plan.targets,
        'expectedRMultiples': plan.expectedRMultiples,
        'configuredRiskPercent': plan.riskPercent,
        'riskBudgetUsdt': plan.riskBudget,
        'accountEquityAtEntry': plan.accountEquity,
        'configuredLeverage': plan.leverage,
        'expectedMargin': plan.expectedMargin,
        'actualQuantity': projection.initialQuantity ?? entry?.quantity,
      },
      'admissionGates': {
        'passed': plan.passedGates,
        'blocked': plan.blockedGates,
      },
      'postTrade': {
        'closed': projection.state == TradingJournalTradeState.closed,
        'economicsPending': projection.economicsPending,
        'actualExit': close?.price,
        'closedAt': projection.closedAt?.toUtc().toIso8601String(),
        'closeReason': projection.closeReason?.name,
        'grossPnl': projection.grossPnl,
        'fees': projection.fees,
        'funding': projection.funding,
        'netPnl': projection.netPnl,
        'actualR': projection.realizedR,
        'durationSeconds': projection.holdingDuration?.inSeconds,
        'returnOnMarginPercent': projection.returnOnMarginPercent,
        'returnOnEquityPercent': projection.returnOnEquityPercent,
        'priceMovePercent': projection.priceMovePercent,
        'mfePercent': projection.mfe,
        'maePercent': projection.mae,
        'maximumOpenProfit': projection.maximumOpenProfit,
        'maximumOpenLoss': projection.maximumOpenLoss,
        'highestTargetReached': projection.highestTargetReached,
        'profitLockConfirmed': projection.profitLockConfirmed,
      },
      'reviewFacts': {
        'initialStopDistancePercent': initialStopDistancePercent,
        'stopSlippagePercent': stopSlippagePercent,
        'sampleSizeClaimMade': false,
      },
      'dataQuality': {
        'integrity': projection.integrity.name,
        'warning': projection.warning,
        'factsCount': events.length,
      },
    };
  }

  static TradingJournalEvent? _authoritativeClose(
    List<TradingJournalEvent> events,
  ) {
    final closes =
        events
            .where(
              (event) =>
                  event.type == TradingJournalEventType.positionClosed ||
                  event.type == TradingJournalEventType.liquidation,
            )
            .toList(growable: false)
          ..sort((a, b) => a.occurredAt.compareTo(b.occurredAt));
    final authoritative = closes
        .where((event) => event.details['economicsPending'] != true)
        .toList(growable: false);
    if (authoritative.isNotEmpty) return authoritative.last;
    return closes.isEmpty ? null : closes.last;
  }
}
