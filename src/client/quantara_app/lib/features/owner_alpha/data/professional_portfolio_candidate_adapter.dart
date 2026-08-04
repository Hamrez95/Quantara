import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';

import '../../portfolio_risk/domain/portfolio_risk_models.dart';
import '../domain/owner_alpha_models.dart';

final class ProfessionalExchangeRules {
  const ProfessionalExchangeRules({
    required this.symbol,
    required this.minimumQuantity,
    required this.minimumNotional,
    required this.quantityPrecision,
    required this.contractMultiplier,
    required this.entryFeeRate,
    required this.exitFeeRate,
    required this.slippageRate,
    required this.fundingReserveRate,
    required this.maximumLeverage,
  });

  final String symbol;
  final double minimumQuantity;
  final double minimumNotional;
  final int quantityPrecision;
  final double contractMultiplier;
  final double entryFeeRate;
  final double exitFeeRate;
  final double slippageRate;
  final double fundingReserveRate;
  final int maximumLeverage;

  bool get valid =>
      RegExp(r'^[A-Z0-9]{5,24}$').hasMatch(symbol.toUpperCase()) &&
      minimumQuantity.isFinite &&
      minimumQuantity > 0 &&
      minimumNotional.isFinite &&
      minimumNotional > 0 &&
      quantityPrecision >= 0 &&
      quantityPrecision <= 12 &&
      contractMultiplier.isFinite &&
      contractMultiplier > 0 &&
      entryFeeRate.isFinite &&
      entryFeeRate >= 0 &&
      exitFeeRate.isFinite &&
      exitFeeRate >= 0 &&
      slippageRate.isFinite &&
      slippageRate >= 0 &&
      fundingReserveRate.isFinite &&
      fundingReserveRate >= 0 &&
      maximumLeverage > 0;
}

final class ProfessionalCandidateException implements Exception {
  const ProfessionalCandidateException(this.message);

  final String message;

  @override
  String toString() => 'ProfessionalCandidateException: $message';
}

abstract final class ProfessionalPortfolioCandidateAdapter {
  static PortfolioEntryCandidate fromIdea({
    required TradeIdea idea,
    required ProfessionalExchangeRules rules,
    int? selectedLeverage,
  }) {
    if (!idea.isActionable ||
        idea.entryLower == null ||
        idea.entryUpper == null ||
        idea.stopLoss == null ||
        idea.positionSize == null ||
        idea.notionalValue == null ||
        idea.maximumSafeLeverage == null ||
        idea.requiredMargin == null) {
      throw const ProfessionalCandidateException(
        'Only a complete actionable idea can become a portfolio candidate.',
      );
    }
    if (!rules.valid ||
        rules.symbol.toUpperCase() != idea.symbol.toUpperCase()) {
      throw const ProfessionalCandidateException(
        'Exchange rules are invalid or belong to another symbol.',
      );
    }
    final long = idea.direction == TradeDirection.long;
    final conservativeEntry = long ? idea.entryUpper! : idea.entryLower!;
    final leverage = (selectedLeverage ?? idea.recommendedLeverage ?? 1)
        .clamp(1, math.min(rules.maximumLeverage, idea.maximumSafeLeverage!))
        .toInt();
    final quantity = _roundDown(idea.positionSize!, rules.quantityPrecision);
    final notional = quantity * conservativeEntry * rules.contractMultiplier;
    if (!quantity.isFinite ||
        quantity < rules.minimumQuantity ||
        !notional.isFinite ||
        notional < rules.minimumNotional) {
      throw const ProfessionalCandidateException(
        'Rounded quantity or notional is below exchange minimums.',
      );
    }
    final requiredMargin = notional / leverage;
    if (!requiredMargin.isFinite || requiredMargin <= 0) {
      throw const ProfessionalCandidateException(
        'Calculated leverage margin is invalid.',
      );
    }
    final fundingReserve = notional * rules.fundingReserveRate;
    final identity = _identity(idea.setupId);
    return PortfolioEntryCandidate(
      reservationId: identity.reservationId,
      journalTradeId: identity.journalTradeId,
      candidateId: idea.setupId,
      symbol: idea.symbol.toUpperCase(),
      assetGroup: _assetGroup(idea.symbol),
      side: long ? PortfolioSide.long : PortfolioSide.short,
      strategy: idea.strategyVersion,
      plannedQuantity: quantity,
      entryPrice: conservativeEntry,
      stopPrice: idea.stopLoss!,
      contractMultiplier: rules.contractMultiplier,
      entryFeeRate: rules.entryFeeRate,
      exitFeeRate: rules.exitFeeRate,
      slippageRate: rules.slippageRate,
      fundingReserve: fundingReserve,
      requiredMargin: requiredMargin,
      leverage: leverage,
      minimumQuantity: rules.minimumQuantity,
      minimumNotional: rules.minimumNotional,
    );
  }

  static _CandidateIdentity _identity(String setupId) {
    if (setupId.trim().isEmpty) {
      throw const ProfessionalCandidateException('Setup identity is empty.');
    }
    String digest(String role) => sha256
        .convert(utf8.encode('$role|$setupId|professional-portfolio/1.0'))
        .toString();
    return _CandidateIdentity(
      reservationId: 'strategy-reservation-${digest('reservation')}',
      journalTradeId: 'strategy-journal-${digest('journal')}',
    );
  }

  static String _assetGroup(String symbol) {
    final normalized = symbol.toUpperCase();
    if (normalized.startsWith('BTC') || normalized.startsWith('ETH')) {
      return 'crypto-major';
    }
    return 'crypto-alt';
  }

  static double _roundDown(double value, int precision) {
    final factor = math.pow(10, precision).toDouble();
    return (value * factor).floor() / factor;
  }
}

final class _CandidateIdentity {
  const _CandidateIdentity({
    required this.reservationId,
    required this.journalTradeId,
  });

  final String reservationId;
  final String journalTradeId;
}
