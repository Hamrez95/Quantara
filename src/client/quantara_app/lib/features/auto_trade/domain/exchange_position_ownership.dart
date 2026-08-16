import 'dart:collection';

import 'auto_trade_models.dart';
import 'local_live_trade_models.dart';

enum ExchangePositionOwnershipKind {
  managed,
  recoverableOrphan,
  externalUnmanaged,
}

enum ExchangePositionRecoveryBlock {
  none,
  missingPositionIdentity,
  duplicatePositionIdentity,
  symbolCollision,
  nonIsolatedMargin,
  unsupportedPositionMode,
  unsupportedSide,
  protectionUnverified,
  protectionIncomplete,
  conflictingRegularOrders,
  quantaraOwnershipNotVerified,
}

final class ExchangePositionOwnershipAssessment {
  ExchangePositionOwnershipAssessment({
    required this.position,
    required this.kind,
    required this.protection,
    required Iterable<ExchangePositionRecoveryBlock> recoveryBlocks,
    this.managedPosition,
  }) : recoveryBlocks = UnmodifiableListView(
         recoveryBlocks.toList(growable: false),
       );

  final AutoTradePosition position;
  final ExchangePositionOwnershipKind kind;
  final AutoTradePositionProtection protection;
  final UnmodifiableListView<ExchangePositionRecoveryBlock> recoveryBlocks;
  final LocalLiveManagedPosition? managedPosition;

  bool get recoverable =>
      kind == ExchangePositionOwnershipKind.recoverableOrphan &&
      recoveryBlocks.isEmpty;

  bool get blocksNewEntries => kind != ExchangePositionOwnershipKind.managed;
}

final class ExchangePositionOwnershipSnapshot {
  ExchangePositionOwnershipSnapshot({
    required DateTime asOfUtc,
    required Iterable<ExchangePositionOwnershipAssessment> positions,
  }) : asOfUtc = asOfUtc.toUtc(),
       positions = UnmodifiableListView(positions.toList(growable: false));

  final DateTime asOfUtc;
  final UnmodifiableListView<ExchangePositionOwnershipAssessment> positions;

  int get exchangeOpenPositionCount => positions.length;
  int get managedCount => positions
      .where((item) => item.kind == ExchangePositionOwnershipKind.managed)
      .length;
  int get recoverableOrphanCount => positions
      .where(
        (item) => item.kind == ExchangePositionOwnershipKind.recoverableOrphan,
      )
      .length;
  int get externalUnmanagedCount => positions
      .where(
        (item) => item.kind == ExchangePositionOwnershipKind.externalUnmanaged,
      )
      .length;

  int consumedSlots(int configuredMaximum) =>
      exchangeOpenPositionCount.clamp(0, configuredMaximum);

  int freeSlots(int configuredMaximum) =>
      (configuredMaximum - consumedSlots(configuredMaximum)).clamp(
        0,
        configuredMaximum,
      );

  bool get blocksNewEntries => positions.any((item) => item.blocksNewEntries);

  bool get hasContradictoryLocalCount =>
      exchangeOpenPositionCount != managedCount;
}

abstract final class ExchangePositionOwnershipClassifier {
  static ExchangePositionOwnershipSnapshot classify({
    required AutoTradeAccountSnapshot account,
    required Iterable<LocalLiveManagedPosition> managedPositions,
    Iterable<String> verifiedQuantaraRecoveryPositionIds = const [],
  }) {
    final managedById = <String, LocalLiveManagedPosition>{};
    for (final managed in managedPositions) {
      final id = managed.positionId.trim();
      if (id.isNotEmpty) managedById[id] = managed;
    }
    final verifiedRecovery = verifiedQuantaraRecoveryPositionIds
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toSet();
    final positionIdCounts = <String, int>{};
    final symbolCounts = <String, int>{};
    for (final position in account.positions.where(
      (item) => item.quantity > 0,
    )) {
      final id = position.positionId.trim();
      final symbol = position.symbol.trim().toUpperCase();
      positionIdCounts[id] = (positionIdCounts[id] ?? 0) + 1;
      symbolCounts[symbol] = (symbolCounts[symbol] ?? 0) + 1;
    }

    final assessments = <ExchangePositionOwnershipAssessment>[];
    for (final position in account.positions.where(
      (item) => item.quantity > 0,
    )) {
      final id = position.positionId.trim();
      final symbol = position.symbol.trim().toUpperCase();
      final managed = managedById[id];
      final protection = AutoTradePositionProtection.reconcile(
        position: position,
        orders: account.protectionOrders,
        asOf: account.syncedAt,
        expectedTakeProfitCount: verifiedRecovery.contains(id) ? 1 : 3,
      );
      if (managed != null &&
          managed.symbol.trim().toUpperCase() == symbol &&
          managed.initialQuantity > 0) {
        assessments.add(
          ExchangePositionOwnershipAssessment(
            position: position,
            kind: ExchangePositionOwnershipKind.managed,
            protection: protection,
            recoveryBlocks: const [],
            managedPosition: managed,
          ),
        );
        continue;
      }

      final blocks = <ExchangePositionRecoveryBlock>[];
      if (id.isEmpty) {
        blocks.add(ExchangePositionRecoveryBlock.missingPositionIdentity);
      }
      if ((positionIdCounts[id] ?? 0) != 1) {
        blocks.add(ExchangePositionRecoveryBlock.duplicatePositionIdentity);
      }
      if ((symbolCounts[symbol] ?? 0) != 1) {
        blocks.add(ExchangePositionRecoveryBlock.symbolCollision);
      }
      if (!position.marginMode.toUpperCase().contains('ISOLAT')) {
        blocks.add(ExchangePositionRecoveryBlock.nonIsolatedMargin);
      }
      final positionMode = position.positionMode.toUpperCase();
      if (positionMode.isEmpty ||
          (!positionMode.contains('ONE') && !positionMode.contains('HEDGE'))) {
        blocks.add(ExchangePositionRecoveryBlock.unsupportedPositionMode);
      }
      final side = position.side.toUpperCase();
      if (!side.contains('LONG') &&
          !side.contains('SHORT') &&
          side != 'BUY' &&
          side != 'SELL') {
        blocks.add(ExchangePositionRecoveryBlock.unsupportedSide);
      }
      final verification = account.protectionVerifications[id];
      if (verification == null || !verification.verified) {
        blocks.add(ExchangePositionRecoveryBlock.protectionUnverified);
      }
      if (protection.status != AutoTradeProtectionStatus.fullyProtected) {
        blocks.add(ExchangePositionRecoveryBlock.protectionIncomplete);
      }
      if (account.orders.any(
        (order) => order.symbol.trim().toUpperCase() == symbol,
      )) {
        blocks.add(ExchangePositionRecoveryBlock.conflictingRegularOrders);
      }
      if (!verifiedRecovery.contains(id)) {
        blocks.add(ExchangePositionRecoveryBlock.quantaraOwnershipNotVerified);
      }

      assessments.add(
        ExchangePositionOwnershipAssessment(
          position: position,
          kind: blocks.isEmpty
              ? ExchangePositionOwnershipKind.recoverableOrphan
              : ExchangePositionOwnershipKind.externalUnmanaged,
          protection: protection,
          recoveryBlocks: blocks,
        ),
      );
    }

    return ExchangePositionOwnershipSnapshot(
      asOfUtc: account.syncedAt,
      positions: assessments,
    );
  }
}
