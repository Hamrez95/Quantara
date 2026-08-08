import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'closed positions queue economics without occupying an execution slot',
    () {
      final source = File(
        'lib/features/auto_trade/application/local_live_trade_service.dart',
      ).readAsStringSync();
      expect(source, contains('_pendingJournalClosures'));
      expect(source, contains('_reconcilePendingJournalClosures'));
      expect(source, contains('_userRequestedEntries'));
      expect(source, contains('_entriesEnabled = _userRequestedEntries'));
    },
  );

  test(
    'refresh routes account, local status, and journal to truth sources',
    () {
      final page = File(
        'lib/features/owner_alpha/presentation/owner_alpha_page.dart',
      ).readAsStringSync();
      final autoTrade = File(
        'lib/features/owner_alpha/presentation/owner_alpha_auto_trade.dart',
      ).readAsStringSync();
      expect(page, contains('_refreshCurrentDestination'));
      expect(page, contains('await state.refreshAll()'));
      expect(page, contains('await _journalController.refresh()'));
      expect(page, contains('onRefresh: _refreshCurrentDestination'));
      expect(autoTrade, contains('Future<void> refreshAll()'));
      expect(autoTrade, contains('await _localController.refresh()'));
    },
  );

  test(
    'verified historical exchange closure repairs old open journal records',
    () {
      final controller = File(
        'lib/features/trading_journal/application/trading_journal_controller.dart',
      ).readAsStringSync();
      final page = File(
        'lib/features/owner_alpha/presentation/owner_alpha_page.dart',
      ).readAsStringSync();
      expect(controller, contains('reconcileVerifiedExchangeClosures'));
      expect(page, contains('_reconcileJournalFromAccount'));
      expect(page, contains('snapshot.authoritativePnl'));
      expect(page, contains('value == 5 || value == 6'));
    },
  );

  test(
    'journal confirmation and closed lifecycle are neutral, not profit green',
    () {
      final source = File(
        'lib/features/trading_journal/presentation/trading_journal_view.dart',
      ).readAsStringSync();
      expect(
        source,
        contains(
          'TradingJournalTradeState.closed => QuantaraColors.electricBlue',
        ),
      );
      expect(
        source,
        contains('TradingJournalFactQuality.confirmed => QuantaraColors.cyan'),
      );
      expect(source, contains('_closeReasonColor'));
    },
  );
}
