import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/recovery/domain/exchange_reinstall_recovery.dart';

void main() {
  const owned = RestoredPositionOwnership(
    journalTradeId: 'local-live:owned-1',
    positionId: 'owned-1',
    entryOrderId: 'entry-1',
    clientId: 'quantara-entry-1',
    stopOrderId: 'stop-1',
    targetOrderIds: ['tp-1', 'tp-2', 'tp-3'],
  );

  test('owned protected position is rebuilt without order mutation', () {
    final result = ExchangeReinstallRecovery.classify(
      restoredOwnership: const [owned],
      exchangePositions: const [
        RecoveryExchangePosition(
          positionId: 'owned-1',
          symbol: 'XRPUSDT',
          quantity: 7.49,
          clientId: 'quantara-entry-1',
        ),
      ],
      regularOrderIds: const {'entry-1'},
      protectionOrders: const [
        RecoveryProtectionOrder(
          orderId: 'stop-1',
          positionId: 'owned-1',
          kind: RecoveryProtectionKind.stop,
          quantity: 7.49,
        ),
        RecoveryProtectionOrder(
          orderId: 'tp-2',
          positionId: 'owned-1',
          kind: RecoveryProtectionKind.takeProfit,
          quantity: 4.28,
        ),
        RecoveryProtectionOrder(
          orderId: 'tp-3',
          positionId: 'owned-1',
          kind: RecoveryProtectionKind.takeProfit,
          quantity: 3.21,
        ),
      ],
      recentClosedPositionIds: const {},
    );

    expect(result.positions.single.classification, RecoveryClassification.ownedProtected);
    expect(result.positions.single.managementMode, RecoveryManagementMode.observeOnly);
    expect(result.newEntriesAllowed, isFalse);
    expect(result.requiresCredentialReconnect, isTrue);
  });

  test('owned incomplete protection remains observe-only and blocks entries', () {
    final result = ExchangeReinstallRecovery.classify(
      restoredOwnership: const [owned],
      exchangePositions: const [
        RecoveryExchangePosition(
          positionId: 'owned-1',
          symbol: 'XRPUSDT',
          quantity: 7.49,
          clientId: 'quantara-entry-1',
        ),
      ],
      regularOrderIds: const {'entry-1'},
      protectionOrders: const [
        RecoveryProtectionOrder(
          orderId: 'tp-2',
          positionId: 'owned-1',
          kind: RecoveryProtectionKind.takeProfit,
          quantity: 4.28,
        ),
      ],
      recentClosedPositionIds: const {},
    );

    expect(result.positions.single.classification, RecoveryClassification.ownedIncomplete);
    expect(result.positions.single.managementMode, RecoveryManagementMode.observeOnly);
    expect(result.newEntriesAllowed, isFalse);
  });

  test('unknown manual position is external unmanaged and never adopted', () {
    final result = ExchangeReinstallRecovery.classify(
      restoredOwnership: const [owned],
      exchangePositions: const [
        RecoveryExchangePosition(
          positionId: 'manual-9',
          symbol: 'BTCUSDT',
          quantity: 0.01,
          clientId: 'manual-mobile-order',
        ),
      ],
      regularOrderIds: const {},
      protectionOrders: const [
        RecoveryProtectionOrder(
          orderId: 'manual-stop',
          positionId: 'manual-9',
          kind: RecoveryProtectionKind.stop,
          quantity: 0.01,
        ),
      ],
      recentClosedPositionIds: const {},
    );

    expect(result.positions.single.classification, RecoveryClassification.externalUnmanaged);
    expect(result.positions.single.ownershipProven, isFalse);
    expect(result.positions.single.managementMode, RecoveryManagementMode.observeOnly);
    expect(result.newEntriesAllowed, isFalse);
  });

  test('position closed while offline is completed idempotently from history', () {
    final first = ExchangeReinstallRecovery.classify(
      restoredOwnership: const [owned],
      exchangePositions: const [],
      regularOrderIds: const {},
      protectionOrders: const [],
      recentClosedPositionIds: const {'owned-1'},
    );
    final second = ExchangeReinstallRecovery.classify(
      restoredOwnership: const [owned],
      exchangePositions: const [],
      regularOrderIds: const {},
      protectionOrders: const [],
      recentClosedPositionIds: const {'owned-1'},
    );

    expect(first.positions.single.classification, RecoveryClassification.closedWhileOffline);
    expect(first.positions.single.recoveryEventId, second.positions.single.recoveryEventId);
    expect(first.newEntriesAllowed, isFalse);
  });
}
