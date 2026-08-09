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
  final totalFees = [...run.openPositions, ...closed]
      .fold<double>(0, (sum, item) => sum + item.entryFee + item.exitFees);
  final totalFunding = [...run.openPositions, ...closed]
      .fold<double>(0, (sum, item) => sum + item.funding);
  final totalSlippage = [...run.openPositions, ...closed]
      .fold<double>(0, (sum, item) => sum + item.slippageCost);
  final rejectionCounts = <String, int>{};
  for (final event in run.events.where((item) => item.kind == TradingLabEventKind.candidateRejected)) {
    final code = event.attributes['rejectionReason'] ?? event.reason;
    rejectionCounts[code] = (rejectionCounts[code] ?? 0) + 1;
  }

  final raw = <String, Object?>{
    'schema': 'quantara.trading_lab.ai_review.v1',
    'generatedAtUtc': DateTime.now().toUtc().toIso8601String(),
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
      'profitFactor': run.profitFactor?.isFinite == true ? run.profitFactor : null,
      'grossProfit': run.grossProfit,
      'grossLoss': run.grossLoss,
      'totalFees': totalFees,
      'totalFunding': totalFunding,
      'totalSlippage': totalSlippage,
      'eventCount': run.events.length,
      'processedDecisionCount': run.processedDecisionKeys.length,
      'lastSnapshotAtUtc': run.lastSnapshotAtUtc?.toIso8601String(),
      'whyNoTrade': run.lastWhyNoTrade,
      'rejectionsByReason': rejectionCounts,
      'sampleWarning': run.tradeCount < 30
          ? 'Small sample: do not promote or rank a strategy from this run alone.'
          : null,
    },
    'openPositions': run.openPositions.map(_positionEvidence).toList(growable: false),
    'closedTrades': closed.map(_positionEvidence).toList(growable: false),
    'pendingCandidates': run.pendingCandidates.map((item) => item.toJson()).toList(growable: false),
    'decisionStream': run.events.map((item) => item.toJson()).toList(growable: false),
  };
  return sanitizeTradingLabExport(raw) as Map<String, Object?>;
}

String buildTradingLabAiReviewJson(TradingLabRun run) =>
    const JsonEncoder.withIndent('  ').convert(buildTradingLabAiReviewBundle(run));

Object? sanitizeTradingLabExport(Object? value) {
  if (value is Map<Object?, Object?>) {
    final result = <String, Object?>{};
    for (final entry in value.entries) {
      final key = entry.key.toString();
      final normalized = key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]'), '');
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

Map<String, Object?> _positionEvidence(TradingLabPosition position) {
  final favorableMove = switch (position.direction) {
    TradeDirection.long => (position.maximumFavorablePrice ?? position.entryPrice) - position.entryPrice,
    TradeDirection.short => position.entryPrice - (position.maximumFavorablePrice ?? position.entryPrice),
    TradeDirection.wait => 0.0,
  };
  final adverseMove = switch (position.direction) {
    TradeDirection.long => position.entryPrice - (position.maximumAdversePrice ?? position.entryPrice),
    TradeDirection.short => (position.maximumAdversePrice ?? position.entryPrice) - position.entryPrice,
    TradeDirection.wait => 0.0,
  };
  final initialRisk = position.initialRisk;
  final mfePnl = favorableMove * position.initialQuantity;
  final maePnl = adverseMove * position.initialQuantity;
  return {
    ...position.toJson(),
    'mfePnl': mfePnl,
    'maePnl': maePnl,
    'mfeR': initialRisk <= 0 ? 0 : mfePnl / initialRisk,
    'maeR': initialRisk <= 0 ? 0 : maePnl / initialRisk,
    'holdingSeconds': (position.closedAtUtc ?? DateTime.now().toUtc())
        .difference(position.openedAtUtc)
        .inSeconds,
  };
}
