import 'dart:math' as math;

import '../../market_analysis/domain/market_regime_models.dart';
import '../../owner_alpha/domain/owner_alpha_models.dart';
import '../../owner_alpha/domain/profit_protection_policy.dart';
import '../data/bitunix_local_live_api_client.dart';
import '../domain/local_live_trade_models.dart';
import '../domain/trading_pnl_projection.dart';

final class LocalLiveOrphanRecoveryDecision {
  const LocalLiveOrphanRecoveryDecision._({
    required this.allowed,
    required this.reason,
    this.managed,
  });

  const LocalLiveOrphanRecoveryDecision.allowed(
    LocalLiveManagedPosition managed,
  ) : this._(allowed: true, reason: 'verified', managed: managed);

  const LocalLiveOrphanRecoveryDecision.blocked(String reason)
    : this._(allowed: false, reason: reason);

  final bool allowed;
  final String reason;
  final LocalLiveManagedPosition? managed;
}

/// Reconstructs only a position whose exchange facts prove that it originated
/// from Quantara Local Live. The policy intentionally refuses partially closed,
/// manually opened, cross-margin, ambiguously identified, or incompletely
/// protected positions.
abstract final class LocalLiveOrphanRecoveryPolicy {
  static String? uniqueEntryOrderId({
    required BitunixLivePosition position,
    required PositionPnlProjection? pnl,
  }) {
    if (pnl == null) return null;
    final positionId = position.positionId.trim();
    final orderIds = pnl.fills
        .where(
          (fill) =>
              !fill.reduceOnly &&
              fill.positionId.trim() == positionId &&
              fill.orderId.trim().isNotEmpty,
        )
        .map((fill) => fill.orderId.trim())
        .toSet();
    return orderIds.length == 1 ? orderIds.single : null;
  }

  static LocalLiveOrphanRecoveryDecision evaluate({
    required BitunixLivePosition position,
    required PositionPnlProjection? pnl,
    required List<BitunixPendingProtection> protection,
    required BitunixOrderDetail? entryOrder,
    required BitunixInstrumentRules rules,
  }) {
    LocalLiveOrphanRecoveryDecision blocked(String reason) =>
        LocalLiveOrphanRecoveryDecision.blocked(reason);

    final positionId = position.positionId.trim();
    final symbol = position.symbol.trim().toUpperCase();
    if (positionId.isEmpty ||
        symbol.isEmpty ||
        !position.quantity.isFinite ||
        position.quantity <= 0 ||
        !position.averageOpenPrice.isFinite ||
        position.averageOpenPrice <= 0 ||
        position.leverage <= 0) {
      return blocked('The exchange position identity or size is invalid.');
    }
    if (!position.marginMode.toUpperCase().contains('ISOL')) {
      return blocked('Only isolated exchange positions can be recovered.');
    }
    final direction = _direction(position.side);
    if (direction == null) {
      return blocked('The exchange position side is unsupported.');
    }
    if (pnl == null) {
      return blocked('Position fill history is unavailable.');
    }
    final explicitFills = pnl.fills
        .where((fill) => fill.positionId.trim() == positionId)
        .toList(growable: false);
    if (explicitFills.isEmpty ||
        explicitFills.any((fill) => fill.tradeId.trim().isEmpty)) {
      return blocked('Explicit exchange fill identity is incomplete.');
    }
    if (explicitFills.any((fill) => fill.reduceOnly)) {
      return blocked(
        'A partially closed orphan position cannot be reconstructed safely.',
      );
    }
    if (!pnl.isVerified) {
      return blocked('Position fill history is not exchange-verified.');
    }
    final entryFills = explicitFills
        .where((fill) => !fill.reduceOnly)
        .toList(growable: false);
    final orderIds = entryFills
        .map((fill) => fill.orderId.trim())
        .where((id) => id.isNotEmpty)
        .toSet();
    if (orderIds.length != 1 || entryOrder == null) {
      return blocked('A unique Quantara entry order could not be proven.');
    }
    final orderId = orderIds.single;
    if (entryOrder.orderId.trim() != orderId ||
        entryOrder.symbol.trim().toUpperCase() != symbol ||
        !entryOrder.hasFill ||
        !entryOrder.clientId.trim().startsWith('q-local-')) {
      return blocked(
        'The entry order is not a verified Quantara Local Live order.',
      );
    }

    final quantityTolerance = math.pow(10, -rules.quantityPrecision).toDouble();
    final entryQuantity = entryFills.fold<double>(
      0,
      (sum, fill) => sum + fill.quantity,
    );
    if ((entryQuantity - position.quantity).abs() > quantityTolerance ||
        entryOrder.filledQuantity + quantityTolerance < position.quantity) {
      return blocked('Entry fill quantity does not match the open position.');
    }
    final weightedEntry = entryQuantity <= 0
        ? 0.0
        : entryFills.fold<double>(
                0,
                (sum, fill) => sum + fill.quantity * fill.price,
              ) /
              entryQuantity;
    final priceTolerance = math.max(
      math.pow(10, -rules.pricePrecision).toDouble(),
      position.averageOpenPrice.abs() * 0.0001,
    );
    if (!weightedEntry.isFinite ||
        (weightedEntry - position.averageOpenPrice).abs() > priceTolerance) {
      return blocked('Entry fill price does not match the open position.');
    }

    final matchingProtection = protection
        .where(
          (item) =>
              item.positionId.trim() == positionId &&
              item.symbol.trim().toUpperCase() == symbol,
        )
        .toList(growable: false);
    final stops = matchingProtection
        .where((item) => item.stopLossPrice > 0)
        .toList(growable: false);
    final targets = matchingProtection
        .where((item) => item.takeProfitPrice > 0)
        .toList(growable: true);
    if (stops.length != 1 || targets.isEmpty || targets.length > 3) {
      return blocked(
        'Exactly one stop and between one and three targets are required.',
      );
    }
    final stop = stops.single;
    if (stop.orderId.trim().isEmpty ||
        stop.stopLossQuantity + quantityTolerance < position.quantity) {
      return blocked('The exchange stop does not cover the full position.');
    }
    final stopOnSafeSide = switch (direction) {
      TradeDirection.long => stop.stopLossPrice < position.averageOpenPrice,
      TradeDirection.short => stop.stopLossPrice > position.averageOpenPrice,
      TradeDirection.wait => false,
    };
    if (!stopOnSafeSide) {
      return blocked('The recovered stop is not on the protective side.');
    }

    targets.sort(
      (left, right) => direction == TradeDirection.long
          ? left.takeProfitPrice.compareTo(right.takeProfitPrice)
          : right.takeProfitPrice.compareTo(left.takeProfitPrice),
    );
    if (targets.any(
      (item) =>
          item.orderId.trim().isEmpty ||
          !item.takeProfitQuantity.isFinite ||
          item.takeProfitQuantity <= 0,
    )) {
      return blocked('A target identity or quantity is invalid.');
    }
    if (targets.map((item) => item.orderId.trim()).toSet().length !=
        targets.length) {
      return blocked('Target order identities are not unique.');
    }
    final targetsOnProfitSide = targets.every(
      (item) => switch (direction) {
        TradeDirection.long => item.takeProfitPrice > position.averageOpenPrice,
        TradeDirection.short =>
          item.takeProfitPrice < position.averageOpenPrice,
        TradeDirection.wait => false,
      },
    );
    if (!targetsOnProfitSide) {
      return blocked('A target is on the wrong side of the entry price.');
    }
    final targetQuantity = targets.fold<double>(
      0,
      (sum, item) => sum + item.takeProfitQuantity,
    );
    if ((targetQuantity - position.quantity).abs() > quantityTolerance) {
      return blocked('The active target quantities do not cover the position.');
    }

    final paddedQuantities = <double>[
      ...targets.map((item) => item.takeProfitQuantity),
      ...List<double>.filled(3 - targets.length, 0),
    ];
    final paddedOrderIds = <String>[
      ...targets.map((item) => item.orderId.trim()),
      ...List<String>.filled(3 - targets.length, ''),
    ];
    final paddedTargetPrices = <double>[
      ...targets.map((item) => item.takeProfitPrice),
      ...List<double>.filled(3 - targets.length, 0),
    ];
    final allocation = ProfitProtectionTargetAllocation.checked(
      tp1Fraction: paddedQuantities[0] / position.quantity,
      tp2Fraction: paddedQuantities[1] / position.quantity,
      tp3Fraction: paddedQuantities[2] / position.quantity,
    );
    final openedAt = entryFills
        .map((fill) => fill.occurredAt.toUtc())
        .reduce((left, right) => left.isBefore(right) ? left : right);
    final managed = LocalLiveManagedPosition(
      setupId: 'recovered:$positionId',
      symbol: symbol,
      timeframe: 'recovered',
      direction: direction,
      positionId: positionId,
      entryOrderId: orderId,
      clientId: entryOrder.clientId.trim(),
      initialQuantity: position.quantity,
      entryPrice: position.averageOpenPrice,
      originalStopLoss: stop.stopLossPrice,
      targets: List.unmodifiable(paddedTargetPrices),
      leverage: position.leverage,
      openedAt: openedAt,
      stopOrderId: stop.orderId.trim(),
      targetAllocation: allocation,
      targetQuantities: List.unmodifiable(paddedQuantities),
      targetOrderIds: List.unmodifiable(paddedOrderIds),
      marketRegime: MarketRegime.transition,
    );
    return LocalLiveOrphanRecoveryDecision.allowed(managed);
  }

  static TradeDirection? _direction(String raw) {
    final value = raw.trim().toUpperCase();
    if (value.contains('BUY') || value.contains('LONG')) {
      return TradeDirection.long;
    }
    if (value.contains('SELL') || value.contains('SHORT')) {
      return TradeDirection.short;
    }
    return null;
  }
}

/// The entry REST fallback has already proved the symbol was flat before submit.
/// Empty exchange position truth therefore means no current exposure candidate.
/// Multiple or structurally invalid candidates are different: they are ambiguous
/// post-submit truth and must throw into the existing entry-lifecycle catch so the
/// portfolio reservation remains ambiguous instead of being released as flat.
extension UniqueBitunixLivePositionListSelection on List<BitunixLivePosition> {
  BitunixLivePosition? get firstOrNull {
    if (isEmpty) return null;
    if (length != 1) {
      throw StateError('Ambiguous exchange position truth after entry submit.');
    }
    final candidate = single;
    if (candidate.positionId.trim().isEmpty ||
        !candidate.quantity.isFinite ||
        candidate.quantity <= 0) {
      throw StateError('Invalid exchange position truth after entry submit.');
    }
    return candidate;
  }

  BitunixLivePosition? uniqueMatchingSide(String expectedSide) {
    final candidate = firstOrNull;
    if (candidate == null) return null;

    String? normalized(String raw) {
      final value = raw.trim().toUpperCase();
      if (value.contains('BUY') || value.contains('LONG')) return 'LONG';
      if (value.contains('SELL') || value.contains('SHORT')) return 'SHORT';
      return null;
    }

    final expected = normalized(expectedSide);
    final actual = normalized(candidate.side);
    if (expected == null || actual == null || actual != expected) {
      throw StateError('Exchange position side is ambiguous after entry submit.');
    }
    return candidate;
  }
}
