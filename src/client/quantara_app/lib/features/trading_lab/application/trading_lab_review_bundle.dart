import 'dart:convert';

import '../../owner_alpha/domain/owner_alpha_models.dart';
import '../domain/trading_lab_models.dart';

const _redactedValue = '[REDACTED]';
const _sensitiveKeyFragments = <String>{
  'apikey',
  'api_key',
  'secret',
  'signature',
  'authorization',
  'cookie',
  'token',
  'credential',
  'password',
  'privatekey',
  'private_key',
};

Map<String, Object?> buildTradingLabAiReviewBundle(TradingLabRun run) {
  final closed = run.closedPositions;
  final evidenceAt = run.lastSnapshotAtUtc ?? run.manifest.startedAtUtc;
  final totalFees = [
    ...run.openPositions,
    ...closed,
  ].fold<double>(0, (sum, item) => sum + item.entryFee + item.exitFees);
  final totalFunding = [
    ...run.openPositions,
    ...closed,
  ].fold<double>(0, (sum, item) => sum + item.funding);
  final totalSlippage = [
    ...run.openPositions,
    ...closed,
  ].fold<double>(0, (sum, item) => sum + item.slippageCost);
  final rejectionCounts = <String, int>{};
  final eventCounts = <String, int>{};
  for (final event in run.events) {
    eventCounts[event.kind.name] = (eventCounts[event.kind.name] ?? 0) + 1;
    if (event.kind == TradingLabEventKind.candidateRejected) {
      final code = event.attributes['rejectionReason'] ?? event.reason;
      rejectionCounts[code] = (rejectionCounts[code] ?? 0) + 1;
    }
  }

  final raw = <String, Object?>{
    'schema': 'quantara.trading_lab.ai_review.v1',
    'evidenceAtUtc': evidenceAt.toUtc().toIso8601String(),
    'manifest': run.manifest.toJson(),
    'summary': {
      'status': run.status.name,
      'startingEquity': run.manifest.startingEquity,
      'balance': run.balance,
      'currentEquity': run.currentEquity,
      'returnPercent': run.returnPercent,
      'maximumDrawdownPercent': run.maximumDrawdownPercent,
      'openPositions': run.openPositions.length,
      'pendingCandidates': run.pendingCandidates.length,
      'closedTrades': run.tradeCount,
      'wins': run.wins,
      'losses': run.losses,
      'winRatePercent': run.winRatePercent,
      'averageR': run.averageR,
      'profitFactor': run.profitFactor?.isFinite == true
          ? run.profitFactor
          : null,
      'grossProfit': run.grossProfit,
      'grossLoss': run.grossLoss,
      'totalFees': totalFees,
      'totalFunding': totalFunding,
      'totalSlippage': totalSlippage,
      'eventCount': run.events.length,
      'eventsByKind': eventCounts,
      'processedDecisionCount': run.processedDecisionKeys.length,
      'lastSnapshotAtUtc': run.lastSnapshotAtUtc?.toIso8601String(),
      'whyNoTrade': run.lastWhyNoTrade,
      'rejectionsByReason': rejectionCounts,
      'sampleWarning': run.tradeCount < 30
          ? 'Small sample: do not promote or rank a strategy from this run alone.'
          : null,
    },
    'strategyScorecards': _strategyScorecards(closed),
    'openPositions': run.openPositions
        .map((item) => _positionEvidence(item, evidenceAt: evidenceAt))
        .toList(growable: false),
    'closedTrades': closed
        .map((item) => _positionEvidence(item, evidenceAt: evidenceAt))
        .toList(growable: false),
    'pendingCandidates': run.pendingCandidates
        .map((item) => item.toJson())
        .toList(growable: false),
    'decisionStream': run.events
        .map((item) => item.toJson())
        .toList(growable: false),
  };
  return sanitizeTradingLabExport(raw) as Map<String, Object?>;
}

String buildTradingLabAiReviewJson(TradingLabRun run) =>
    const JsonEncoder.withIndent(
      '  ',
    ).convert(buildTradingLabAiReviewBundle(run));

Object? sanitizeTradingLabExport(Object? value) {
  if (value is Map<Object?, Object?>) {
    final result = <String, Object?>{};
    for (final entry in value.entries) {
      final key = entry.key.toString();
      final normalized = key.toLowerCase().replaceAll(
        RegExp(r'[^a-z0-9_]'),
        '',
      );
      if (_sensitiveKeyFragments.any(normalized.contains)) {
        result[key] = _redactedValue;
      } else {
        result[key] = sanitizeTradingLabExport(entry.value);
      }
    }
    return result;
  }
  if (value is Iterable) {
    return value.map(sanitizeTradingLabExport).toList(growable: false);
  }
  return value;
}

List<Map<String, Object?>> _strategyScorecards(
  List<TradingLabPosition> closed,
) {
  final groups = <String, List<TradingLabPosition>>{};
  for (final position in closed) {
    final confidenceBucket = switch (position.confidencePercent) {
      < 60 => '<60',
      < 70 => '60-69',
      < 80 => '70-79',
      < 90 => '80-89',
      _ => '90-100',
    };
    final key = [
      '${position.strategy}@${position.strategyVersion}',
      position.symbol,
      position.timeframe,
      position.marketRegime,
      position.direction.name,
      confidenceBucket,
    ].join('|');
    (groups[key] ??= <TradingLabPosition>[]).add(position);
  }

  final scorecards = <Map<String, Object?>>[];
  for (final entry in groups.entries) {
    final parts = entry.key.split('|');
    final trades = entry.value;
    final wins = trades.where((item) => item.netRealizedPnl > 0).length;
    final losses = trades.where((item) => item.netRealizedPnl < 0).length;
    final grossProfit = trades
        .where((item) => item.netRealizedPnl > 0)
        .fold<double>(0, (sum, item) => sum + item.netRealizedPnl);
    final grossLoss = trades
        .where((item) => item.netRealizedPnl < 0)
        .fold<double>(0, (sum, item) => sum + item.netRealizedPnl.abs());
    final netPnl = trades.fold<double>(
      0,
      (sum, item) => sum + item.netRealizedPnl,
    );
    final averageR = trades.fold<double>(
          0,
          (sum, item) => sum + item.realizedR,
        ) /
        trades.length;
    scorecards.add({
      'strategyVersion': parts[0],
      'symbol': parts[1],
      'timeframe': parts[2],
      'marketRegime': parts[3],
      'direction': parts[4],
      'confidenceBucket': parts[5],
      'sampleSize': trades.length,
      'wins': wins,
      'losses': losses,
      'winRatePercent': wins / trades.length * 100,
      'netPnl': netPnl,
      'expectancyUsdt': netPnl / trades.length,
      'averageR': averageR,
      'profitFactor': grossLoss <= 0
          ? (grossProfit > 0 ? null : 0)
          : grossProfit / grossLoss,
      'insufficientSample': trades.length < 30,
    });
  }
  scorecards.sort((left, right) {
    final strategy = (left['strategyVersion'] as String).compareTo(
      right['strategyVersion'] as String,
    );
    if (strategy != 0) return strategy;
    final symbol = (left['symbol'] as String).compareTo(right['symbol'] as String);
    if (symbol != 0) return symbol;
    return (left['timeframe'] as String).compareTo(right['timeframe'] as String);
  });
  return List.unmodifiable(scorecards);
}

Map<String, Object?> _positionEvidence(
  TradingLabPosition position, {
  required DateTime evidenceAt,
}) {
  final favorableMove = switch (position.direction) {
    TradeDirection.long =>
      (position.maximumFavorablePrice ?? position.entryPrice) -
          position.entryPrice,
    TradeDirection.short =>
      position.entryPrice -
          (position.maximumFavorablePrice ?? position.entryPrice),
    TradeDirection.wait => 0.0,
  };
  final adverseMove = switch (position.direction) {
    TradeDirection.long =>
      position.entryPrice -
          (position.maximumAdversePrice ?? position.entryPrice),
    TradeDirection.short =>
      (position.maximumAdversePrice ?? position.entryPrice) -
          position.entryPrice,
    TradeDirection.wait => 0.0,
  };
  final initialRisk = position.initialRisk;
  final mfePnl = favorableMove * position.initialQuantity;
  final maePnl = adverseMove * position.initialQuantity;
  final effectiveEnd = position.closedAtUtc ?? evidenceAt;
  return {
    ...position.toJson(),
    'mfePnl': mfePnl,
    'maePnl': maePnl,
    'mfeR': initialRisk <= 0 ? 0 : mfePnl / initialRisk,
    'maeR': initialRisk <= 0 ? 0 : maePnl / initialRisk,
    'holdingSeconds': effectiveEnd.isBefore(position.openedAtUtc)
        ? 0
        : effectiveEnd.difference(position.openedAtUtc).inSeconds,
  };
}
