import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

enum PortfolioSide { long, short }

enum PortfolioReservationLifecycle {
  pending,
  partiallyFilled,
  open,
  ambiguous,
  released,
  closed,
}

enum PortfolioVerificationState {
  planned,
  exchangeConfirmed,
  unverified,
  stale,
}

enum PortfolioEntryBlockReason {
  none,
  invalidInput,
  staleAccount,
  incompleteProtection,
  unsupportedMarginMode,
  duplicateCandidate,
  sameSymbolOverlap,
  ambiguousReservation,
  emergencyTechnicalCeiling,
  exchangeMinimum,
  riskBudgetInsufficient,
  marginInsufficient,
  directionConcentration,
}

@immutable
final class TradingDayId {
  const TradingDayId({
    required this.value,
    required this.startedAtUtc,
    required this.timezoneOffsetMinutes,
  });

  factory TradingDayId.start({
    required DateTime now,
    required int timezoneOffsetMinutes,
  }) {
    if (timezoneOffsetMinutes < -14 * 60 || timezoneOffsetMinutes > 14 * 60) {
      throw const FormatException('Trading-day timezone offset is invalid.');
    }
    final utc = now.toUtc();
    final local = utc.add(Duration(minutes: timezoneOffsetMinutes));
    final localMidnight = DateTime.utc(local.year, local.month, local.day);
    final startUtc = localMidnight.subtract(
      Duration(minutes: timezoneOffsetMinutes),
    );
    final date =
        '${local.year.toString().padLeft(4, '0')}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
    final sign = timezoneOffsetMinutes >= 0 ? '+' : '-';
    final absolute = timezoneOffsetMinutes.abs();
    final offset =
        '$sign${(absolute ~/ 60).toString().padLeft(2, '0')}:'
        '${(absolute % 60).toString().padLeft(2, '0')}';
    return TradingDayId(
      value: '$date@$offset',
      startedAtUtc: startUtc,
      timezoneOffsetMinutes: timezoneOffsetMinutes,
    );
  }

  final String value;
  final DateTime startedAtUtc;
  final int timezoneOffsetMinutes;

  DateTime get nextBoundaryUtc => startedAtUtc.add(const Duration(days: 1));

  bool shouldRoll(DateTime now) => !now.toUtc().isBefore(nextBoundaryUtc);

  Map<String, Object?> toJson() => {
    'value': value,
    'startedAtUtc': startedAtUtc.toUtc().toIso8601String(),
    'timezoneOffsetMinutes': timezoneOffsetMinutes,
  };

  factory TradingDayId.fromJson(Map<String, Object?> json) {
    final value = json['value']?.toString().trim() ?? '';
    final startedAt = DateTime.tryParse(
      json['startedAtUtc']?.toString() ?? '',
    )?.toUtc();
    final offset = _integer(json['timezoneOffsetMinutes']);
    if (value.isEmpty ||
        startedAt == null ||
        offset < -14 * 60 ||
        offset > 14 * 60) {
      throw const FormatException('Invalid persisted trading-day identity.');
    }
    return TradingDayId(
      value: value,
      startedAtUtc: startedAt,
      timezoneOffsetMinutes: offset,
    );
  }
}

@immutable
final class DailyRiskBudget {
  const DailyRiskBudget({
    required this.limit,
    required this.realizedLoss,
    required this.openRisk,
    required this.pendingRisk,
    required this.ambiguousRisk,
  });

  final double limit;
  final double realizedLoss;
  final double openRisk;
  final double pendingRisk;
  final double ambiguousRisk;

  double get consumed => realizedLoss + openRisk + pendingRisk + ambiguousRisk;

  double get available => math.max(0, limit - consumed);

  double get overrun => math.max(0, consumed - limit);
}

@immutable
final class MarginBudget {
  const MarginBudget({
    required this.freeMargin,
    required this.usedMargin,
    required this.reservedMargin,
    required this.maintenanceMargin,
    required this.safetyBuffer,
    required this.feeReserve,
  });

  final double freeMargin;
  final double usedMargin;
  final double reservedMargin;
  final double maintenanceMargin;
  final double safetyBuffer;
  final double feeReserve;

  double get spendable => math.max(
    0,
    freeMargin - reservedMargin - maintenanceMargin - safetyBuffer - feeReserve,
  );

  bool canReserve(double requiredMargin) =>
      requiredMargin.isFinite &&
      requiredMargin >= 0 &&
      spendable >= requiredMargin;
}

@immutable
final class PortfolioAccountTruth {
  const PortfolioAccountTruth({
    required this.asOf,
    required this.fresh,
    required this.allOpenPositionsProtected,
    required this.marginMode,
    required this.freeMargin,
    required this.usedMargin,
    required this.maintenanceMargin,
    required this.pendingMarginReservations,
    required this.safetyBuffer,
    required this.feeReserve,
  });

  final DateTime asOf;
  final bool fresh;
  final bool allOpenPositionsProtected;
  final String marginMode;
  final double freeMargin;
  final double usedMargin;
  final double maintenanceMargin;
  final double pendingMarginReservations;
  final double safetyBuffer;
  final double feeReserve;

  MarginBudget get marginBudget => MarginBudget(
    freeMargin: freeMargin,
    usedMargin: usedMargin,
    reservedMargin: pendingMarginReservations,
    maintenanceMargin: maintenanceMargin,
    safetyBuffer: safetyBuffer,
    feeReserve: feeReserve,
  );
}

@immutable
final class PortfolioEntryCandidate {
  const PortfolioEntryCandidate({
    required this.reservationId,
    required this.journalTradeId,
    required this.candidateId,
    required this.symbol,
    required this.assetGroup,
    required this.side,
    required this.strategy,
    required this.plannedQuantity,
    required this.entryPrice,
    required this.stopPrice,
    required this.contractMultiplier,
    required this.entryFeeRate,
    required this.exitFeeRate,
    required this.slippageRate,
    required this.fundingReserve,
    required this.requiredMargin,
    required this.leverage,
    required this.minimumQuantity,
    required this.minimumNotional,
  });

  final String reservationId;
  final String journalTradeId;
  final String candidateId;
  final String symbol;
  final String assetGroup;
  final PortfolioSide side;
  final String strategy;
  final double plannedQuantity;
  final double entryPrice;
  final double stopPrice;
  final double contractMultiplier;
  final double entryFeeRate;
  final double exitFeeRate;
  final double slippageRate;
  final double fundingReserve;
  final double requiredMargin;
  final int leverage;
  final double minimumQuantity;
  final double minimumNotional;

  double get notional => plannedQuantity * entryPrice * contractMultiplier;
}

@immutable
final class PositionRiskReservation {
  PositionRiskReservation({
    required this.reservationId,
    required this.journalTradeId,
    required this.candidateId,
    required this.symbol,
    required this.assetGroup,
    required this.side,
    required this.strategy,
    required this.entryOrderId,
    required this.positionId,
    required this.plannedQuantity,
    required this.filledQuantity,
    required this.entryPrice,
    required this.currentExchangeConfirmedStop,
    required this.contractMultiplier,
    required this.estimatedEntryFee,
    required this.estimatedExitFee,
    required this.slippageReserve,
    required this.fundingReserve,
    required this.maximumLoss,
    required this.reservedMargin,
    required this.createdAt,
    required this.tradingDayId,
    required this.lifecycle,
    required this.verification,
    required this.revision,
  });

  final String reservationId;
  final String journalTradeId;
  final String candidateId;
  final String symbol;
  final String assetGroup;
  final PortfolioSide side;
  final String strategy;
  final String? entryOrderId;
  final String? positionId;
  final double plannedQuantity;
  final double filledQuantity;
  final double entryPrice;
  final double currentExchangeConfirmedStop;
  final double contractMultiplier;
  final double estimatedEntryFee;
  final double estimatedExitFee;
  final double slippageReserve;
  final double fundingReserve;
  final double maximumLoss;
  final double reservedMargin;
  final DateTime createdAt;
  final String tradingDayId;
  final PortfolioReservationLifecycle lifecycle;
  final PortfolioVerificationState verification;
  final int revision;

  bool get active => switch (lifecycle) {
    PortfolioReservationLifecycle.pending ||
    PortfolioReservationLifecycle.partiallyFilled ||
    PortfolioReservationLifecycle.open ||
    PortfolioReservationLifecycle.ambiguous => true,
    PortfolioReservationLifecycle.released ||
    PortfolioReservationLifecycle.closed => false,
  };

  bool get pending => switch (lifecycle) {
    PortfolioReservationLifecycle.pending ||
    PortfolioReservationLifecycle.partiallyFilled => true,
    _ => false,
  };

  bool get open => lifecycle == PortfolioReservationLifecycle.open;
  bool get ambiguous => lifecycle == PortfolioReservationLifecycle.ambiguous;

  String get checksum => sha256
      .convert(utf8.encode(_canonicalJson(toJson(includeChecksum: false))))
      .toString();

  PositionRiskReservation copyWith({
    String? entryOrderId,
    String? positionId,
    double? plannedQuantity,
    double? filledQuantity,
    double? currentExchangeConfirmedStop,
    double? estimatedEntryFee,
    double? estimatedExitFee,
    double? slippageReserve,
    double? fundingReserve,
    double? maximumLoss,
    double? reservedMargin,
    PortfolioReservationLifecycle? lifecycle,
    PortfolioVerificationState? verification,
    int? revision,
  }) => PositionRiskReservation(
    reservationId: reservationId,
    journalTradeId: journalTradeId,
    candidateId: candidateId,
    symbol: symbol,
    assetGroup: assetGroup,
    side: side,
    strategy: strategy,
    entryOrderId: entryOrderId ?? this.entryOrderId,
    positionId: positionId ?? this.positionId,
    plannedQuantity: plannedQuantity ?? this.plannedQuantity,
    filledQuantity: filledQuantity ?? this.filledQuantity,
    entryPrice: entryPrice,
    currentExchangeConfirmedStop:
        currentExchangeConfirmedStop ?? this.currentExchangeConfirmedStop,
    contractMultiplier: contractMultiplier,
    estimatedEntryFee: estimatedEntryFee ?? this.estimatedEntryFee,
    estimatedExitFee: estimatedExitFee ?? this.estimatedExitFee,
    slippageReserve: slippageReserve ?? this.slippageReserve,
    fundingReserve: fundingReserve ?? this.fundingReserve,
    maximumLoss: maximumLoss ?? this.maximumLoss,
    reservedMargin: reservedMargin ?? this.reservedMargin,
    createdAt: createdAt,
    tradingDayId: tradingDayId,
    lifecycle: lifecycle ?? this.lifecycle,
    verification: verification ?? this.verification,
    revision: revision ?? this.revision,
  );

  Map<String, Object?> toJson({bool includeChecksum = true}) => {
    'reservationId': reservationId,
    'journalTradeId': journalTradeId,
    'candidateId': candidateId,
    'symbol': symbol,
    'assetGroup': assetGroup,
    'side': side.name,
    'strategy': strategy,
    'entryOrderId': entryOrderId,
    'positionId': positionId,
    'plannedQuantity': plannedQuantity,
    'filledQuantity': filledQuantity,
    'entryPrice': entryPrice,
    'currentExchangeConfirmedStop': currentExchangeConfirmedStop,
    'contractMultiplier': contractMultiplier,
    'estimatedEntryFee': estimatedEntryFee,
    'estimatedExitFee': estimatedExitFee,
    'slippageReserve': slippageReserve,
    'fundingReserve': fundingReserve,
    'maximumLoss': maximumLoss,
    'reservedMargin': reservedMargin,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'tradingDayId': tradingDayId,
    'lifecycle': lifecycle.name,
    'verification': verification.name,
    'revision': revision,
    if (includeChecksum) 'checksum': checksum,
  };

  factory PositionRiskReservation.fromJson(Map<String, Object?> json) {
    final reservation = PositionRiskReservation(
      reservationId: json['reservationId']?.toString() ?? '',
      journalTradeId: json['journalTradeId']?.toString() ?? '',
      candidateId: json['candidateId']?.toString() ?? '',
      symbol: json['symbol']?.toString() ?? '',
      assetGroup: json['assetGroup']?.toString() ?? '',
      side: PortfolioSide.values.firstWhere(
        (item) => item.name == json['side'],
        orElse: () => throw const FormatException('Invalid reservation side.'),
      ),
      strategy: json['strategy']?.toString() ?? '',
      entryOrderId: _nullableString(json['entryOrderId']),
      positionId: _nullableString(json['positionId']),
      plannedQuantity: _number(json['plannedQuantity']),
      filledQuantity: _number(json['filledQuantity']),
      entryPrice: _number(json['entryPrice']),
      currentExchangeConfirmedStop: _number(
        json['currentExchangeConfirmedStop'],
      ),
      contractMultiplier: _number(json['contractMultiplier']),
      estimatedEntryFee: _number(json['estimatedEntryFee']),
      estimatedExitFee: _number(json['estimatedExitFee']),
      slippageReserve: _number(json['slippageReserve']),
      fundingReserve: _number(json['fundingReserve']),
      maximumLoss: _number(json['maximumLoss']),
      reservedMargin: _number(json['reservedMargin']),
      createdAt:
          DateTime.tryParse(json['createdAt']?.toString() ?? '')?.toUtc() ??
          (throw const FormatException('Invalid reservation timestamp.')),
      tradingDayId: json['tradingDayId']?.toString() ?? '',
      lifecycle: PortfolioReservationLifecycle.values.firstWhere(
        (item) => item.name == json['lifecycle'],
        orElse: () =>
            throw const FormatException('Invalid reservation lifecycle.'),
      ),
      verification: PortfolioVerificationState.values.firstWhere(
        (item) => item.name == json['verification'],
        orElse: () =>
            throw const FormatException('Invalid reservation verification.'),
      ),
      revision: _integer(json['revision']),
    );
    _validatePersistedReservation(reservation);
    if (json['checksum']?.toString() != reservation.checksum) {
      throw const FormatException('Reservation checksum mismatch.');
    }
    return reservation;
  }
}

@immutable
final class PendingOrderRiskReservation {
  const PendingOrderRiskReservation(this.value);

  final PositionRiskReservation value;

  double get maximumLoss => value.pending ? value.maximumLoss : 0;
  double get reservedMargin => value.pending ? value.reservedMargin : 0;
}

@immutable
final class ExchangeConfirmedOpenRisk {
  const ExchangeConfirmedOpenRisk(this.positions);

  final List<PositionRiskReservation> positions;

  double get total => positions
      .where(
        (item) =>
            item.open &&
            item.verification == PortfolioVerificationState.exchangeConfirmed,
      )
      .fold<double>(0, (sum, item) => sum + math.max(0, item.maximumLoss));
}

@immutable
final class PortfolioRiskSnapshot {
  const PortfolioRiskSnapshot({
    required this.tradingDay,
    required this.dailyRisk,
    required this.margin,
    required this.positions,
    required this.accountFresh,
    required this.allPositionsProtected,
    required this.blockReason,
    required this.liveExecutionAllowed,
  });

  final TradingDayId tradingDay;
  final DailyRiskBudget dailyRisk;
  final MarginBudget margin;
  final List<PositionRiskReservation> positions;
  final bool accountFresh;
  final bool allPositionsProtected;
  final PortfolioEntryBlockReason blockReason;
  final bool liveExecutionAllowed;

  int get openPositionCount => positions.where((item) => item.open).length;
}

@immutable
final class PortfolioEntryDecision {
  const PortfolioEntryDecision({
    required this.allowed,
    required this.liveExecutionAllowed,
    required this.reason,
    required this.maximumLoss,
    required this.requiredMargin,
    required this.availableRiskBefore,
    required this.availableRiskAfter,
    required this.availableMarginAfter,
  });

  final bool allowed;
  final bool liveExecutionAllowed;
  final PortfolioEntryBlockReason reason;
  final double maximumLoss;
  final double requiredMargin;
  final double availableRiskBefore;
  final double availableRiskAfter;
  final double availableMarginAfter;
}

@immutable
final class PortfolioRiskPolicy {
  const PortfolioRiskPolicy({
    this.emergencyTechnicalCeiling = 24,
    this.maximumDirectionRiskFraction = 0.75,
  });

  final int emergencyTechnicalCeiling;
  final double maximumDirectionRiskFraction;

  PortfolioEntryDecision evaluate({
    required PortfolioRiskLedger ledger,
    required PortfolioEntryCandidate candidate,
    required PortfolioAccountTruth account,
  }) {
    PortfolioEntryDecision blocked(
      PortfolioEntryBlockReason reason, {
      double maximumLoss = 0,
      double requiredMargin = 0,
    }) => PortfolioEntryDecision(
      allowed: false,
      liveExecutionAllowed: false,
      reason: reason,
      maximumLoss: maximumLoss,
      requiredMargin: requiredMargin,
      availableRiskBefore: ledger.dailyRisk.available,
      availableRiskAfter: ledger.dailyRisk.available,
      availableMarginAfter: account.marginBudget.spendable,
    );

    if (!_candidateValid(candidate) || !_accountNumbersValid(account)) {
      return blocked(PortfolioEntryBlockReason.invalidInput);
    }
    if (!account.fresh) {
      return blocked(PortfolioEntryBlockReason.staleAccount);
    }
    if (!account.allOpenPositionsProtected) {
      return blocked(PortfolioEntryBlockReason.incompleteProtection);
    }
    if (account.marginMode.toLowerCase() != 'isolated') {
      return blocked(PortfolioEntryBlockReason.unsupportedMarginMode);
    }
    if (ledger.activeReservations.any((item) => item.ambiguous)) {
      return blocked(PortfolioEntryBlockReason.ambiguousReservation);
    }
    if (ledger.reservations.any(
      (item) =>
          item.active &&
          (item.reservationId == candidate.reservationId ||
              item.candidateId == candidate.candidateId ||
              item.journalTradeId == candidate.journalTradeId),
    )) {
      return blocked(PortfolioEntryBlockReason.duplicateCandidate);
    }
    if (ledger.activeReservations.any(
      (item) => item.symbol.toUpperCase() == candidate.symbol.toUpperCase(),
    )) {
      return blocked(PortfolioEntryBlockReason.sameSymbolOverlap);
    }
    if (ledger.activeReservations.length >= emergencyTechnicalCeiling) {
      return blocked(PortfolioEntryBlockReason.emergencyTechnicalCeiling);
    }
    if (candidate.plannedQuantity < candidate.minimumQuantity ||
        candidate.notional < candidate.minimumNotional) {
      return blocked(PortfolioEntryBlockReason.exchangeMinimum);
    }

    final maximumLoss = PortfolioRiskMath.maximumLoss(
      side: candidate.side,
      entryPrice: candidate.entryPrice,
      stopPrice: candidate.stopPrice,
      quantity: candidate.plannedQuantity,
      contractMultiplier: candidate.contractMultiplier,
      entryFeeRate: candidate.entryFeeRate,
      exitFeeRate: candidate.exitFeeRate,
      slippageRate: candidate.slippageRate,
      fundingReserve: candidate.fundingReserve,
    );
    if (maximumLoss > ledger.dailyRisk.available + 1e-9) {
      return blocked(
        PortfolioEntryBlockReason.riskBudgetInsufficient,
        maximumLoss: maximumLoss,
        requiredMargin: candidate.requiredMargin,
      );
    }
    final sameDirectionRisk = ledger.activeReservations
        .where((item) => item.side == candidate.side)
        .fold<double>(0, (sum, item) => sum + item.maximumLoss);
    if (sameDirectionRisk + maximumLoss >
        ledger.dailyRisk.limit * maximumDirectionRiskFraction + 1e-9) {
      return blocked(
        PortfolioEntryBlockReason.directionConcentration,
        maximumLoss: maximumLoss,
        requiredMargin: candidate.requiredMargin,
      );
    }
    final margin = account.marginBudget;
    if (!margin.canReserve(candidate.requiredMargin)) {
      return blocked(
        PortfolioEntryBlockReason.marginInsufficient,
        maximumLoss: maximumLoss,
        requiredMargin: candidate.requiredMargin,
      );
    }
    return PortfolioEntryDecision(
      allowed: true,
      liveExecutionAllowed: false,
      reason: PortfolioEntryBlockReason.none,
      maximumLoss: maximumLoss,
      requiredMargin: candidate.requiredMargin,
      availableRiskBefore: ledger.dailyRisk.available,
      availableRiskAfter: math.max(0, ledger.dailyRisk.available - maximumLoss),
      availableMarginAfter: math.max(
        0,
        margin.spendable - candidate.requiredMargin,
      ),
    );
  }
}

abstract final class PortfolioRiskMath {
  static double maximumLoss({
    required PortfolioSide side,
    required double entryPrice,
    required double stopPrice,
    required double quantity,
    required double contractMultiplier,
    required double entryFeeRate,
    required double exitFeeRate,
    required double slippageRate,
    required double fundingReserve,
  }) {
    final values = [
      entryPrice,
      stopPrice,
      quantity,
      contractMultiplier,
      entryFeeRate,
      exitFeeRate,
      slippageRate,
      fundingReserve,
    ];
    if (values.any((value) => !value.isFinite || value < 0) ||
        entryPrice <= 0 ||
        stopPrice <= 0 ||
        quantity <= 0 ||
        contractMultiplier <= 0) {
      throw const FormatException('Position risk input is invalid.');
    }
    final directionalDistance = switch (side) {
      PortfolioSide.long => entryPrice - stopPrice,
      PortfolioSide.short => stopPrice - entryPrice,
    };
    if (directionalDistance <= 0) {
      throw const FormatException('Stop is on the wrong side of entry.');
    }
    final stopDistanceLoss =
        directionalDistance * quantity * contractMultiplier;
    final entryFee = entryPrice * quantity * contractMultiplier * entryFeeRate;
    final exitFee = stopPrice * quantity * contractMultiplier * exitFeeRate;
    final slippage = entryPrice * quantity * contractMultiplier * slippageRate;
    final total =
        stopDistanceLoss + entryFee + exitFee + slippage + fundingReserve;
    if (!total.isFinite || total <= 0) {
      throw const FormatException('Calculated position risk is invalid.');
    }
    return total;
  }

  static double confirmedOpenRisk({
    required PortfolioSide side,
    required double entryPrice,
    required double confirmedStop,
    required double remainingQuantity,
    required double contractMultiplier,
    required double entryFee,
    required double exitFee,
    required double slippageReserve,
    required double fundingReserve,
  }) {
    final values = [
      entryPrice,
      confirmedStop,
      remainingQuantity,
      contractMultiplier,
      entryFee,
      exitFee,
      slippageReserve,
      fundingReserve,
    ];
    if (values.any((value) => !value.isFinite || value < 0) ||
        entryPrice <= 0 ||
        confirmedStop <= 0 ||
        remainingQuantity <= 0 ||
        contractMultiplier <= 0) {
      throw const FormatException('Confirmed open-risk input is invalid.');
    }
    final directionalLossPerUnit = switch (side) {
      PortfolioSide.long => math.max(0, entryPrice - confirmedStop),
      PortfolioSide.short => math.max(0, confirmedStop - entryPrice),
    };
    final priceRisk =
        directionalLossPerUnit * remainingQuantity * contractMultiplier;
    final costRisk = entryFee + exitFee + slippageReserve + fundingReserve;
    final result = math.max(0, priceRisk + costRisk);
    if (!result.isFinite) {
      throw const FormatException('Confirmed open risk is invalid.');
    }
    return result;
  }
}

@immutable
final class PortfolioRiskLedger {
  PortfolioRiskLedger({
    required this.schemaVersion,
    required this.revision,
    required this.tradingDay,
    required this.dailyRiskLimit,
    required this.realizedLoss,
    required this.realizedProfit,
    required List<PositionRiskReservation> reservations,
    required Set<String> processedEventIds,
  }) : reservations = List.unmodifiable(reservations),
       processedEventIds = Set.unmodifiable(processedEventIds);

  factory PortfolioRiskLedger.initial({
    required TradingDayId tradingDay,
    required double dailyRiskLimit,
  }) {
    if (!dailyRiskLimit.isFinite || dailyRiskLimit <= 0) {
      throw const FormatException('Daily risk limit is invalid.');
    }
    return PortfolioRiskLedger(
      schemaVersion: 1,
      revision: 0,
      tradingDay: tradingDay,
      dailyRiskLimit: dailyRiskLimit,
      realizedLoss: 0,
      realizedProfit: 0,
      reservations: const [],
      processedEventIds: const {},
    );
  }

  final int schemaVersion;
  final int revision;
  final TradingDayId tradingDay;
  final double dailyRiskLimit;
  final double realizedLoss;
  final double realizedProfit;
  final List<PositionRiskReservation> reservations;
  final Set<String> processedEventIds;

  List<PositionRiskReservation> get activeReservations =>
      reservations.where((item) => item.active).toList(growable: false);

  DailyRiskBudget get dailyRisk {
    var openRisk = 0.0;
    var pendingRisk = 0.0;
    var ambiguousRisk = 0.0;
    for (final reservation in reservations) {
      if (!reservation.active) continue;
      if (reservation.ambiguous ||
          reservation.verification == PortfolioVerificationState.unverified ||
          reservation.verification == PortfolioVerificationState.stale) {
        ambiguousRisk += math.max(0, reservation.maximumLoss);
      } else if (reservation.open) {
        openRisk += math.max(0, reservation.maximumLoss);
      } else if (reservation.pending) {
        pendingRisk += math.max(0, reservation.maximumLoss);
      }
    }
    return DailyRiskBudget(
      limit: dailyRiskLimit,
      realizedLoss: math.max(0, realizedLoss),
      openRisk: openRisk,
      pendingRisk: pendingRisk,
      ambiguousRisk: ambiguousRisk,
    );
  }

  double get reservedMargin => activeReservations.fold<double>(
    0,
    (sum, item) => sum + math.max(0, item.reservedMargin),
  );

  PortfolioRiskLedger reserve({
    required PortfolioEntryCandidate candidate,
    required PortfolioEntryDecision decision,
    required DateTime createdAt,
  }) {
    if (!decision.allowed) {
      throw StateError('Cannot reserve a blocked portfolio entry.');
    }
    final notional = candidate.notional;
    final entryFee = notional * candidate.entryFeeRate;
    final exitFee =
        candidate.stopPrice *
        candidate.plannedQuantity *
        candidate.contractMultiplier *
        candidate.exitFeeRate;
    final slippage = notional * candidate.slippageRate;
    final next = PositionRiskReservation(
      reservationId: candidate.reservationId,
      journalTradeId: candidate.journalTradeId,
      candidateId: candidate.candidateId,
      symbol: candidate.symbol.toUpperCase(),
      assetGroup: candidate.assetGroup,
      side: candidate.side,
      strategy: candidate.strategy,
      entryOrderId: null,
      positionId: null,
      plannedQuantity: candidate.plannedQuantity,
      filledQuantity: 0,
      entryPrice: candidate.entryPrice,
      currentExchangeConfirmedStop: candidate.stopPrice,
      contractMultiplier: candidate.contractMultiplier,
      estimatedEntryFee: entryFee,
      estimatedExitFee: exitFee,
      slippageReserve: slippage,
      fundingReserve: candidate.fundingReserve,
      maximumLoss: decision.maximumLoss,
      reservedMargin: candidate.requiredMargin,
      createdAt: createdAt.toUtc(),
      tradingDayId: tradingDay.value,
      lifecycle: PortfolioReservationLifecycle.pending,
      verification: PortfolioVerificationState.planned,
      revision: 1,
    );
    return _copy(revision: revision + 1, reservations: [...reservations, next]);
  }

  PortfolioRiskLedger release({
    required String reservationId,
    required String eventId,
  }) {
    if (processedEventIds.contains(eventId)) return this;
    var changed = false;
    final next = reservations
        .map((item) {
          if (item.reservationId != reservationId || !item.active) return item;
          changed = true;
          return item.copyWith(
            maximumLoss: 0,
            reservedMargin: 0,
            lifecycle: PortfolioReservationLifecycle.released,
            verification: PortfolioVerificationState.exchangeConfirmed,
            revision: item.revision + 1,
          );
        })
        .toList(growable: false);
    return _copy(
      revision: changed ? revision + 1 : revision,
      reservations: next,
      processedEventIds: {...processedEventIds, eventId},
    );
  }

  PortfolioRiskLedger markAmbiguous({
    required String reservationId,
    required String eventId,
  }) {
    if (processedEventIds.contains(eventId)) return this;
    var changed = false;
    final next = reservations
        .map((item) {
          if (item.reservationId != reservationId || !item.active) return item;
          changed = true;
          return item.copyWith(
            lifecycle: PortfolioReservationLifecycle.ambiguous,
            verification: PortfolioVerificationState.unverified,
            revision: item.revision + 1,
          );
        })
        .toList(growable: false);
    return _copy(
      revision: changed ? revision + 1 : revision,
      reservations: next,
      processedEventIds: {...processedEventIds, eventId},
    );
  }

  PortfolioRiskLedger applyPartialFill({
    required String reservationId,
    required String eventId,
    required String entryOrderId,
    required String positionId,
    required double fillQuantity,
  }) {
    if (processedEventIds.contains(eventId)) return this;
    if (!fillQuantity.isFinite || fillQuantity <= 0) {
      throw const FormatException('Fill quantity is invalid.');
    }
    final index = reservations.indexWhere(
      (item) => item.reservationId == reservationId && item.pending,
    );
    if (index < 0)
      return _copy(processedEventIds: {...processedEventIds, eventId});
    final source = reservations[index];
    if (fillQuantity > source.plannedQuantity + 1e-9) {
      throw const FormatException('Fill exceeds pending quantity.');
    }
    final filledFraction = fillQuantity / source.plannedQuantity;
    final remainingQuantity = source.plannedQuantity - fillQuantity;
    final openReservation = PositionRiskReservation(
      reservationId: '$reservationId:position:$positionId',
      journalTradeId: source.journalTradeId,
      candidateId: source.candidateId,
      symbol: source.symbol,
      assetGroup: source.assetGroup,
      side: source.side,
      strategy: source.strategy,
      entryOrderId: entryOrderId,
      positionId: positionId,
      plannedQuantity: fillQuantity,
      filledQuantity: fillQuantity,
      entryPrice: source.entryPrice,
      currentExchangeConfirmedStop: source.currentExchangeConfirmedStop,
      contractMultiplier: source.contractMultiplier,
      estimatedEntryFee: source.estimatedEntryFee * filledFraction,
      estimatedExitFee: source.estimatedExitFee * filledFraction,
      slippageReserve: source.slippageReserve * filledFraction,
      fundingReserve: source.fundingReserve * filledFraction,
      maximumLoss: source.maximumLoss * filledFraction,
      reservedMargin: source.reservedMargin * filledFraction,
      createdAt: source.createdAt,
      tradingDayId: source.tradingDayId,
      lifecycle: PortfolioReservationLifecycle.open,
      verification: PortfolioVerificationState.exchangeConfirmed,
      revision: 1,
    );
    final next = [...reservations];
    if (remainingQuantity <= 1e-9) {
      next[index] = source.copyWith(
        entryOrderId: entryOrderId,
        plannedQuantity: 0,
        filledQuantity: fillQuantity,
        maximumLoss: 0,
        reservedMargin: 0,
        lifecycle: PortfolioReservationLifecycle.released,
        verification: PortfolioVerificationState.exchangeConfirmed,
        revision: source.revision + 1,
      );
    } else {
      final remainingFraction = remainingQuantity / source.plannedQuantity;
      next[index] = source.copyWith(
        entryOrderId: entryOrderId,
        plannedQuantity: remainingQuantity,
        filledQuantity: 0,
        estimatedEntryFee: source.estimatedEntryFee * remainingFraction,
        estimatedExitFee: source.estimatedExitFee * remainingFraction,
        slippageReserve: source.slippageReserve * remainingFraction,
        fundingReserve: source.fundingReserve * remainingFraction,
        maximumLoss: source.maximumLoss * remainingFraction,
        reservedMargin: source.reservedMargin * remainingFraction,
        lifecycle: PortfolioReservationLifecycle.partiallyFilled,
        verification: PortfolioVerificationState.exchangeConfirmed,
        revision: source.revision + 1,
      );
    }
    next.add(openReservation);
    return _copy(
      revision: revision + 1,
      reservations: next,
      processedEventIds: {...processedEventIds, eventId},
    );
  }

  PortfolioRiskLedger confirmStop({
    required String positionId,
    required String eventId,
    required double confirmedStop,
  }) {
    if (processedEventIds.contains(eventId)) return this;
    var changed = false;
    final next = reservations
        .map((item) {
          if (!item.open || item.positionId != positionId) return item;
          final risk = PortfolioRiskMath.confirmedOpenRisk(
            side: item.side,
            entryPrice: item.entryPrice,
            confirmedStop: confirmedStop,
            remainingQuantity: item.filledQuantity,
            contractMultiplier: item.contractMultiplier,
            entryFee: item.estimatedEntryFee,
            exitFee: item.estimatedExitFee,
            slippageReserve: item.slippageReserve,
            fundingReserve: item.fundingReserve,
          );
          changed = true;
          return item.copyWith(
            currentExchangeConfirmedStop: confirmedStop,
            maximumLoss: risk,
            verification: PortfolioVerificationState.exchangeConfirmed,
            revision: item.revision + 1,
          );
        })
        .toList(growable: false);
    return _copy(
      revision: changed ? revision + 1 : revision,
      reservations: next,
      processedEventIds: {...processedEventIds, eventId},
    );
  }

  PortfolioRiskLedger closePosition({
    required String positionId,
    required String eventId,
    required double exchangeConfirmedNetPnl,
  }) {
    if (processedEventIds.contains(eventId)) return this;
    if (!exchangeConfirmedNetPnl.isFinite) {
      throw const FormatException('Confirmed PnL is invalid.');
    }
    var changed = false;
    final next = reservations
        .map((item) {
          if (!item.open || item.positionId != positionId) return item;
          changed = true;
          return item.copyWith(
            maximumLoss: 0,
            reservedMargin: 0,
            lifecycle: PortfolioReservationLifecycle.closed,
            verification: PortfolioVerificationState.exchangeConfirmed,
            revision: item.revision + 1,
          );
        })
        .toList(growable: false);
    return _copy(
      revision: changed ? revision + 1 : revision,
      realizedLoss: realizedLoss + math.max(0, -exchangeConfirmedNetPnl),
      realizedProfit: realizedProfit + math.max(0, exchangeConfirmedNetPnl),
      reservations: next,
      processedEventIds: {...processedEventIds, eventId},
    );
  }

  PortfolioRiskLedger rollTradingDay({
    required DateTime now,
    required double nextDailyRiskLimit,
  }) {
    if (!tradingDay.shouldRoll(now)) return this;
    final nextDay = TradingDayId.start(
      now: now,
      timezoneOffsetMinutes: tradingDay.timezoneOffsetMinutes,
    );
    if (nextDay.value == tradingDay.value) return this;
    return PortfolioRiskLedger(
      schemaVersion: schemaVersion,
      revision: revision + 1,
      tradingDay: nextDay,
      dailyRiskLimit: nextDailyRiskLimit,
      realizedLoss: 0,
      realizedProfit: 0,
      reservations: reservations,
      processedEventIds: processedEventIds,
    );
  }

  PortfolioRiskSnapshot snapshot(PortfolioAccountTruth account) {
    final blockReason = !account.fresh
        ? PortfolioEntryBlockReason.staleAccount
        : !account.allOpenPositionsProtected
        ? PortfolioEntryBlockReason.incompleteProtection
        : activeReservations.any((item) => item.ambiguous)
        ? PortfolioEntryBlockReason.ambiguousReservation
        : PortfolioEntryBlockReason.none;
    return PortfolioRiskSnapshot(
      tradingDay: tradingDay,
      dailyRisk: dailyRisk,
      margin: MarginBudget(
        freeMargin: account.freeMargin,
        usedMargin: account.usedMargin,
        reservedMargin: account.pendingMarginReservations + reservedMargin,
        maintenanceMargin: account.maintenanceMargin,
        safetyBuffer: account.safetyBuffer,
        feeReserve: account.feeReserve,
      ),
      positions: activeReservations,
      accountFresh: account.fresh,
      allPositionsProtected: account.allOpenPositionsProtected,
      blockReason: blockReason,
      liveExecutionAllowed: false,
    );
  }

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'revision': revision,
    'tradingDay': tradingDay.toJson(),
    'dailyRiskLimit': dailyRiskLimit,
    'realizedLoss': realizedLoss,
    'realizedProfit': realizedProfit,
    'reservations': reservations.map((item) => item.toJson()).toList(),
    'processedEventIds': processedEventIds.toList()..sort(),
  };

  factory PortfolioRiskLedger.fromJson(Map<String, Object?> json) {
    final dayRaw = json['tradingDay'];
    final reservationsRaw = json['reservations'];
    if (dayRaw is! Map<Object?, Object?> || reservationsRaw is! List<Object?>) {
      throw const FormatException('Invalid portfolio risk ledger.');
    }
    final ledger = PortfolioRiskLedger(
      schemaVersion: _integer(json['schemaVersion']),
      revision: _integer(json['revision']),
      tradingDay: TradingDayId.fromJson(_stringMap(dayRaw)),
      dailyRiskLimit: _number(json['dailyRiskLimit']),
      realizedLoss: _number(json['realizedLoss']),
      realizedProfit: _number(json['realizedProfit']),
      reservations: reservationsRaw
          .whereType<Map<Object?, Object?>>()
          .map((item) => PositionRiskReservation.fromJson(_stringMap(item)))
          .toList(growable: false),
      processedEventIds:
          (json['processedEventIds'] as List<Object?>? ?? const [])
              .map((item) => item.toString())
              .where((item) => item.trim().isNotEmpty)
              .toSet(),
    );
    if (ledger.schemaVersion != 1 ||
        ledger.revision < 0 ||
        !ledger.dailyRiskLimit.isFinite ||
        ledger.dailyRiskLimit <= 0 ||
        !ledger.realizedLoss.isFinite ||
        ledger.realizedLoss < 0 ||
        !ledger.realizedProfit.isFinite ||
        ledger.realizedProfit < 0) {
      throw const FormatException('Portfolio risk ledger failed validation.');
    }
    return ledger;
  }

  PortfolioRiskLedger _copy({
    int? revision,
    double? realizedLoss,
    double? realizedProfit,
    List<PositionRiskReservation>? reservations,
    Set<String>? processedEventIds,
  }) => PortfolioRiskLedger(
    schemaVersion: schemaVersion,
    revision: revision ?? this.revision,
    tradingDay: tradingDay,
    dailyRiskLimit: dailyRiskLimit,
    realizedLoss: realizedLoss ?? this.realizedLoss,
    realizedProfit: realizedProfit ?? this.realizedProfit,
    reservations: reservations ?? this.reservations,
    processedEventIds: processedEventIds ?? this.processedEventIds,
  );
}

bool _candidateValid(PortfolioEntryCandidate candidate) {
  final textFields = [
    candidate.reservationId,
    candidate.journalTradeId,
    candidate.candidateId,
    candidate.symbol,
    candidate.assetGroup,
    candidate.strategy,
  ];
  if (textFields.any((item) => item.trim().isEmpty)) return false;
  final values = [
    candidate.plannedQuantity,
    candidate.entryPrice,
    candidate.stopPrice,
    candidate.contractMultiplier,
    candidate.entryFeeRate,
    candidate.exitFeeRate,
    candidate.slippageRate,
    candidate.fundingReserve,
    candidate.requiredMargin,
    candidate.minimumQuantity,
    candidate.minimumNotional,
  ];
  return values.every((value) => value.isFinite && value >= 0) &&
      candidate.plannedQuantity > 0 &&
      candidate.entryPrice > 0 &&
      candidate.stopPrice > 0 &&
      candidate.contractMultiplier > 0 &&
      candidate.requiredMargin > 0 &&
      candidate.leverage > 0;
}

bool _accountNumbersValid(PortfolioAccountTruth account) => [
  account.freeMargin,
  account.usedMargin,
  account.maintenanceMargin,
  account.pendingMarginReservations,
  account.safetyBuffer,
  account.feeReserve,
].every((value) => value.isFinite && value >= 0);

void _validatePersistedReservation(PositionRiskReservation reservation) {
  if (reservation.reservationId.trim().isEmpty ||
      reservation.journalTradeId.trim().isEmpty ||
      reservation.candidateId.trim().isEmpty ||
      reservation.symbol.trim().isEmpty ||
      reservation.strategy.trim().isEmpty ||
      reservation.tradingDayId.trim().isEmpty ||
      reservation.revision <= 0) {
    throw const FormatException('Invalid reservation identity.');
  }
  final values = [
    reservation.plannedQuantity,
    reservation.filledQuantity,
    reservation.entryPrice,
    reservation.currentExchangeConfirmedStop,
    reservation.contractMultiplier,
    reservation.estimatedEntryFee,
    reservation.estimatedExitFee,
    reservation.slippageReserve,
    reservation.fundingReserve,
    reservation.maximumLoss,
    reservation.reservedMargin,
  ];
  if (values.any((value) => !value.isFinite || value < 0) ||
      reservation.entryPrice <= 0 ||
      reservation.currentExchangeConfirmedStop <= 0 ||
      reservation.contractMultiplier <= 0) {
    throw const FormatException('Invalid persisted reservation values.');
  }
}

String? _nullableString(Object? value) {
  final normalized = value?.toString().trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}

Map<String, Object?> _stringMap(Map<Object?, Object?> source) => {
  for (final entry in source.entries) entry.key.toString(): entry.value,
};

int _integer(Object? value) =>
    value is num ? value.toInt() : int.tryParse(value?.toString() ?? '') ?? 0;

double _number(Object? value) => value is num
    ? value.toDouble()
    : double.tryParse(value?.toString() ?? '') ?? double.nan;

String _canonicalJson(Object? value) {
  Object? normalize(Object? input) {
    if (input is Map) {
      final keys = input.keys.map((key) => key.toString()).toList()..sort();
      return <String, Object?>{
        for (final key in keys) key: normalize(input[key]),
      };
    }
    if (input is Iterable) {
      return input.map(normalize).toList(growable: false);
    }
    return input;
  }

  return jsonEncode(normalize(value));
}
