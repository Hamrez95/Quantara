import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/auto_trade/domain/local_live_management_only_after_flat.dart';

void main() {
  group('Issue #165 management-only after final exchange close', () {
    test('final managed close latches entries off while user intent was armed', () {
      expect(
        LocalLiveManagementOnlyAfterFlatPolicy.shouldLatchAfterFinalExchangeClose(
          hadManagedPositions: true,
          hasManagedPositions: false,
          exchangeOpenPositionCount: 0,
          userRequestedEntries: true,
        ),
        isTrue,
      );
      expect(
        LocalLiveManagementOnlyAfterFlatPolicy.effectiveEntriesEnabled(
          userRequestedEntries: true,
          managementOnlyAfterFlat: true,
        ),
        isFalse,
      );
    });

    test('ordinary flat account without a managed close does not latch', () {
      expect(
        LocalLiveManagementOnlyAfterFlatPolicy.shouldLatchAfterFinalExchangeClose(
          hadManagedPositions: false,
          hasManagedPositions: false,
          exchangeOpenPositionCount: 0,
          userRequestedEntries: true,
        ),
        isFalse,
      );
    });

    test('restart keeps entries disabled until explicit resume clears latch', () {
      const persistedLatch = true;
      expect(
        LocalLiveManagementOnlyAfterFlatPolicy.effectiveEntriesEnabled(
          userRequestedEntries: true,
          managementOnlyAfterFlat: persistedLatch,
        ),
        isFalse,
      );
      expect(
        LocalLiveManagementOnlyAfterFlatPolicy.effectiveEntriesEnabled(
          userRequestedEntries: true,
          managementOnlyAfterFlat: false,
        ),
        isTrue,
      );
    });

    test('service source persists latch and preserves journal-close evidence', () {
      final source = File(
        'lib/features/auto_trade/application/local_live_trade_service.dart',
      ).readAsStringSync();

      expect(source, contains('localLiveManagementOnlyAfterFlatKey'));
      expect(source, contains('managementOnlyAfterFlat'));
      expect(source, contains('shouldLatchAfterFinalExchangeClose'));
      expect(source, contains('management_only_after_flat'));
      expect(source, contains('_pendingJournalClosures.add(managed)'));
      expect(source, contains('recordExchangeClosureObserved'));
      expect(source, contains('journal_close_reconciled'));
    });
  });
}
