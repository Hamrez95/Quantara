import 'dart:math' as math;

import '../../auto_trade/domain/auto_trade_models.dart';
import '../../auto_trade/domain/manual_trade_execution.dart';
import '../../owner_alpha/domain/owner_alpha_models.dart';
import '../data/database_trading_journal_store.dart';
import '../data/trading_journal_store.dart';
import '../domain/trading_journal_models.dart';

final class ManualTradeJournalObserver {
  ManualTradeJournalObserver({TradingJournalStore? store})
    : _store = store ?? DatabaseTradingJournalStore();

  final TradingJournalStore _store;

  static String journalTradeId(String positionId) =>
      'manual-live:${positionId.trim()}';

  Future<void> recordProtectedTrade({
    required SignalJournalEntry setup,
    required ManualTradePlan plan,
    required AutoTradeAccountSnapshot account,
    required String positionId,
    required String entryOrderId,
    required String clientId,
    required double actualEntryPrice,
    required String stopOrderId,
    required List<String> targetOrderIds,
    required DateTime openedAtUtc,
  }) async {
    final journalId = journalTradeId(positionId);
    final riskPerUnit = (actualEntryPrice - plan.stopLoss).abs();
    final expectedR = plan.targets
        .map(
          (target) => riskPerUnit <= 0
              ? 0.0
              : (target - actualEntryPrice).abs() / riskPerUnit,
        )
        .toList(growable: false);
    final direction = switch (setup.direction) {
      TradeDirection.long => TradingJournalDirection.long,
      TradeDirection.short => TradingJournalDirection.short,
      TradeDirection.wait => TradingJournalDirection.wait,
    };
    final planRecord = TradingJournalPlan(
      journalTradeId: journalId,
      setupId: setup.setupId,
      analysisVersion: setup.strategyVersion,
      symbol: setup.symbol,
      market: 'USDT_PERPETUAL',
      timeframe: setup.timeframe,
      direction: direction,
      strategy: setup.strategy.name,
      cadence: 'manual-confirmed',
      source: TradingJournalSource.manual,
      decidedAt: openedAtUtc.toUtc(),
      decisionPrice: actualEntryPrice,
      entryLower: setup.entryLower ?? actualEntryPrice,
      entryUpper: setup.entryUpper ?? actualEntryPrice,
      plannedEntry: plan.entryPrice,
      originalStopLoss: plan.stopLoss,
      targets: List.unmodifiable(plan.targets),
      expectedRMultiples: List.unmodifiable(expectedR),
      confidencePercent: setup.confidencePercent.toDouble(),
      confluence: <String>[
        'manual-user-confirmation',
        'manual-sizing:${plan.policyVersion}',
        'setup-quality:${plan.qualityScore}',
        'tp-count:${plan.targetCount}',
        if (setup.contextVersion.trim().isNotEmpty)
          'context:${setup.contextVersion}',
      ],
      regime: setup.marketRegime.name,
      rationale: setup.summary,
      invalidation: setup.invalidation,
      accountEquity: account.estimatedEquity,
      riskPercent: plan.riskPercentOfEquity,
      riskBudget: plan.maximumLoss,
      leverage: plan.leverage,
      expectedMargin: plan.margin,
      passedGates: const [
        'explicit-user-confirmation',
        'fresh-account-projection',
        'isolated-margin',
        'confirmed-entry-fill',
        'confirmed-full-stop',
        'confirmed-selected-target-ladder',
      ],
      blockedGates: const [],
      appVersion: '1.2.0-rc.3+127',
      strategyRulesVersion: setup.strategyVersion,
      positionId: positionId,
      entryOrderId: entryOrderId,
      clientId: clientId,
      notes:
          'Manual setup execution. Quantara does not manage this position after initial exchange-native SL/TP protection is confirmed.',
      indicatorSnapshot: setup.evidenceBreakdown,
    );
    await _store.appendPlan(planRecord);

    final recordedAt = DateTime.now().toUtc();
    await _store.appendEvent(
      TradingJournalEvent(
        eventId: 'manual-entry:$entryOrderId',
        journalTradeId: journalId,
        type: TradingJournalEventType.entryFilled,
        occurredAt: openedAtUtc.toUtc(),
        recordedAt: recordedAt,
        source: TradingJournalFactSource.exchange,
        quality: TradingJournalFactQuality.confirmed,
        scope: TradingJournalScope.position,
        currency: account.marginCoin,
        asOf: account.syncedAt.toUtc(),
        exchangeEventId: 'entry-order:$entryOrderId',
        positionId: positionId,
        orderId: entryOrderId,
        clientId: clientId,
        quantity: plan.quantity,
        price: actualEntryPrice,
        remainingQuantity: plan.quantity,
        details: {
          'manualExecution': true,
          'margin': plan.margin,
          'leverage': plan.leverage,
          'maximumLoss': plan.maximumLoss,
          'policyVersion': plan.policyVersion,
        },
      ),
    );
    await _store.appendEvent(
      TradingJournalEvent(
        eventId: 'manual-stop:$stopOrderId',
        journalTradeId: journalId,
        type: TradingJournalEventType.stopConfirmed,
        occurredAt: recordedAt,
        recordedAt: recordedAt,
        source: TradingJournalFactSource.exchange,
        quality: TradingJournalFactQuality.confirmed,
        scope: TradingJournalScope.position,
        currency: account.marginCoin,
        asOf: recordedAt,
        exchangeEventId: 'stop-order:$stopOrderId',
        positionId: positionId,
        orderId: stopOrderId,
        quantity: plan.quantity,
        price: plan.stopLoss,
      ),
    );
    for (var index = 0; index < targetOrderIds.length; index++) {
      final orderId = targetOrderIds[index].trim();
      if (orderId.isEmpty) continue;
      await _store.appendEvent(
        TradingJournalEvent(
          eventId: 'manual-tp:$orderId',
          journalTradeId: journalId,
          type: TradingJournalEventType.takeProfitConfirmed,
          occurredAt: recordedAt,
          recordedAt: recordedAt,
          source: TradingJournalFactSource.exchange,
          quality: TradingJournalFactQuality.confirmed,
          scope: TradingJournalScope.position,
          currency: account.marginCoin,
          asOf: recordedAt,
          exchangeEventId: 'tp-order:$orderId',
          positionId: positionId,
          orderId: orderId,
          quantity: plan.targetQuantities[index],
          price: plan.targets[index],
          details: {'targetIndex': index + 1, 'manualExecution': true},
        ),
      );
    }

    final allocated = plan.targetQuantities.fold<double>(
      0,
      (sum, value) => sum + value,
    );
    if ((allocated - plan.quantity).abs() >
        math.max(1e-9, plan.quantity.abs() * 1e-6)) {
      throw StateError('Manual trade journal target quantity mismatch.');
    }
  }
}
