import 'dart:math' as math;

import 'package:flutter/foundation.dart';

@immutable
final class RestoredPositionOwnership {
  const RestoredPositionOwnership({
    required this.journalTradeId,
    required this.positionId,
    required this.entryOrderId,
    required this.clientId,
    required this.stopOrderId,
    required this.targetOrderIds,
  });

  final String journalTradeId;
  final String positionId;
  final String entryOrderId;
  final String clientId;
  final String? stopOrderId;
  final List<String> targetOrderIds;
}

@immutable
final class RecoveryExchangePosition {
  const RecoveryExchangePosition({
    required this.positionId,
    required this.symbol,
    required this.quantity,
    required this.clientId,
  });

  final String positionId;
  final String symbol;
  final double quantity;
  final String clientId;
}

enum RecoveryProtectionKind { stop, takeProfit }

@immutable
final class RecoveryProtectionOrder {
  const RecoveryProtectionOrder({
    required this.orderId,
    required this.positionId,
    required this.kind,
    required this.quantity,
  });

  final String orderId;
  final String positionId;
  final RecoveryProtectionKind kind;
  final double quantity;
}

enum RecoveryClassification {
  ownedProtected,
  ownedIncomplete,
  externalUnmanaged,
  closedWhileOffline,
}

enum RecoveryManagementMode { observeOnly }

@immutable
final class RecoveredExchangePosition {
  const RecoveredExchangePosition({
    required this.positionId,
    required this.symbol,
    required this.classification,
    required this.managementMode,
    required this.ownershipProven,
    required this.recoveryEventId,
    required this.warnings,
  });

  final String positionId;
  final String symbol;
  final RecoveryClassification classification;
  final RecoveryManagementMode managementMode;
  final bool ownershipProven;
  final String recoveryEventId;
  final List<String> warnings;
}

@immutable
final class ExchangeReinstallRecoveryResult {
  const ExchangeReinstallRecoveryResult({
    required this.positions,
    required this.newEntriesAllowed,
    required this.requiresCredentialReconnect,
  });

  final List<RecoveredExchangePosition> positions;
  final bool newEntriesAllowed;
  final bool requiresCredentialReconnect;
}

abstract final class ExchangeReinstallRecovery {
  static ExchangeReinstallRecoveryResult classify({
    required List<RestoredPositionOwnership> restoredOwnership,
    required List<RecoveryExchangePosition> exchangePositions,
    required Set<String> regularOrderIds,
    required List<RecoveryProtectionOrder> protectionOrders,
    required Set<String> recentClosedPositionIds,
  }) {
    final claimsByPosition = {
      for (final claim in restoredOwnership)
        if (claim.positionId.trim().isNotEmpty) claim.positionId: claim,
    };
    final results = <RecoveredExchangePosition>[];
    final seen = <String>{};

    for (final position in exchangePositions) {
      if (!seen.add(position.positionId)) continue;
      final claim = claimsByPosition[position.positionId];
      final ownershipProven =
          claim != null &&
          _ownershipEvidence(
            claim: claim,
            position: position,
            regularOrderIds: regularOrderIds,
            protectionOrders: protectionOrders,
          );
      if (!ownershipProven) {
        results.add(
          RecoveredExchangePosition(
            positionId: position.positionId,
            symbol: position.symbol,
            classification: RecoveryClassification.externalUnmanaged,
            managementMode: RecoveryManagementMode.observeOnly,
            ownershipProven: false,
            recoveryEventId: _eventId(
              RecoveryClassification.externalUnmanaged,
              position.positionId,
            ),
            warnings: const [
              'Ownership could not be proven; position remains external and unmanaged.',
              'New entries stay blocked while an external position is open.',
            ],
          ),
        );
        continue;
      }

      final complete = _protectionComplete(
        claim: claim!,
        position: position,
        protectionOrders: protectionOrders,
      );
      results.add(
        RecoveredExchangePosition(
          positionId: position.positionId,
          symbol: position.symbol,
          classification: complete
              ? RecoveryClassification.ownedProtected
              : RecoveryClassification.ownedIncomplete,
          managementMode: RecoveryManagementMode.observeOnly,
          ownershipProven: true,
          recoveryEventId: _eventId(
            complete
                ? RecoveryClassification.ownedProtected
                : RecoveryClassification.ownedIncomplete,
            position.positionId,
          ),
          warnings: complete
              ? const [
                  'Quantara ownership and exchange-native protection were verified.',
                  'Credential reconnection and explicit recovery are still required.',
                ]
              : const [
                  'Quantara ownership was verified but protection is incomplete or unverified.',
                  'The position remains observe-only and new entries are blocked.',
                ],
        ),
      );
    }

    for (final claim in restoredOwnership) {
      if (seen.contains(claim.positionId) ||
          !recentClosedPositionIds.contains(claim.positionId)) {
        continue;
      }
      seen.add(claim.positionId);
      results.add(
        RecoveredExchangePosition(
          positionId: claim.positionId,
          symbol: '',
          classification: RecoveryClassification.closedWhileOffline,
          managementMode: RecoveryManagementMode.observeOnly,
          ownershipProven: true,
          recoveryEventId: _eventId(
            RecoveryClassification.closedWhileOffline,
            claim.positionId,
          ),
          warnings: const [
            'The restored Quantara position closed while the app was offline.',
            'Journal completion must be rebuilt from verified exchange history.',
          ],
        ),
      );
    }

    results.sort((left, right) => left.positionId.compareTo(right.positionId));
    return ExchangeReinstallRecoveryResult(
      positions: List.unmodifiable(results),
      newEntriesAllowed: false,
      requiresCredentialReconnect: true,
    );
  }

  static bool _ownershipEvidence({
    required RestoredPositionOwnership claim,
    required RecoveryExchangePosition position,
    required Set<String> regularOrderIds,
    required List<RecoveryProtectionOrder> protectionOrders,
  }) {
    if (claim.positionId != position.positionId) return false;
    final clientMatch =
        claim.clientId.trim().isNotEmpty &&
        position.clientId.trim().isNotEmpty &&
        claim.clientId == position.clientId;
    final entryMatch =
        claim.entryOrderId.trim().isNotEmpty &&
        regularOrderIds.contains(claim.entryOrderId);
    final knownProtectionIds = {
      if (claim.stopOrderId != null) claim.stopOrderId!,
      ...claim.targetOrderIds,
    };
    final protectionMatch = protectionOrders.any(
      (order) =>
          order.positionId == position.positionId &&
          knownProtectionIds.contains(order.orderId),
    );
    return clientMatch || entryMatch || protectionMatch;
  }

  static bool _protectionComplete({
    required RestoredPositionOwnership claim,
    required RecoveryExchangePosition position,
    required List<RecoveryProtectionOrder> protectionOrders,
  }) {
    final scoped = protectionOrders
        .where((order) => order.positionId == position.positionId)
        .toList(growable: false);
    final stopId = claim.stopOrderId;
    final stopQuantity = scoped
        .where(
          (order) =>
              order.kind == RecoveryProtectionKind.stop &&
              stopId != null &&
              order.orderId == stopId,
        )
        .fold<double>(0, (total, order) => total + order.quantity);
    final targetIds = claim.targetOrderIds.toSet();
    final targets = scoped.where(
      (order) =>
          order.kind == RecoveryProtectionKind.takeProfit &&
          targetIds.contains(order.orderId),
    );
    final targetQuantity = targets.fold<double>(
      0,
      (total, order) => total + order.quantity,
    );
    final tolerance = math.max(0.00000001, position.quantity.abs() * 0.000001);
    return stopQuantity + tolerance >= position.quantity &&
        targetQuantity + tolerance >= position.quantity;
  }

  static String _eventId(
    RecoveryClassification classification,
    String positionId,
  ) => 'reinstall-recovery:${classification.name}:${positionId.trim()}';
}
