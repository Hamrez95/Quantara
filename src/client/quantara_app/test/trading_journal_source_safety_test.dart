import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('journal restore, import and UI have no exchange mutation authority', () {
    final root = Directory.current.path;
    String source(String path) => File('$root/$path').readAsStringSync();

    final journalFiles = [
      'lib/features/trading_journal/data/trading_journal_store.dart',
      'lib/features/trading_journal/data/database_trading_journal_store.dart',
      'lib/features/trading_journal/data/trading_journal_export.dart',
      'lib/features/trading_journal/application/trading_journal_controller.dart',
      'lib/features/trading_journal/presentation/trading_journal_view.dart',
    ].map(source).join('\n');
    final observer = source(
      'lib/features/trading_journal/application/local_live_journal_observer.dart',
    );
    final controller = source(
      'lib/features/trading_journal/application/trading_journal_controller.dart',
    );

    for (final forbidden in const [
      'placeMarketEntry(',
      'placePositionStop(',
      'placePartialTakeProfit(',
      'modifyPositionStop(',
      'cancelEntryOrder(',
      'closePositionReduceOnly(',
      'flash_close_position',
      '/trade/place_order',
    ]) {
      expect(journalFiles, isNot(contains(forbidden)));
      expect(observer, isNot(contains(forbidden)));
    }
    expect(observer, contains('observer-only'));
    expect(observer, contains('must never change'));
    expect(controller, contains('Timer.periodic'));
    expect(controller, contains('refresh(silent: true)'));
    expect(controller, contains('next.generation != _ledger.generation'));
    expect(controller, contains('_localRefreshTimer?.cancel()'));
  });

  test('runtime journal composition is database-first with a legacy mirror', () {
    final root = Directory.current.path;
    final ownerPage = File(
      '$root/lib/features/owner_alpha/presentation/owner_alpha_page.dart',
    ).readAsStringSync();
    final databaseStore = File(
      '$root/lib/features/trading_journal/data/database_trading_journal_store.dart',
    ).readAsStringSync();

    expect(ownerPage, contains('DatabaseTradingJournalStore()'));
    expect(
      ownerPage,
      isNot(
        contains(
          'TradingJournalController(store: SharedPreferencesTradingJournalStore())',
        ),
      ),
    );
    expect(databaseStore, contains('QuantaraDurableCategory.journal'));
    expect(databaseStore, contains('_legacyStore.replace(persisted)'));
    expect(databaseStore, contains('return TradingJournalLedger.fromJson'));
  });

  test('privacy export strips secret-like fields and client IDs', () {
    final sourceText = File(
      '${Directory.current.path}/lib/features/trading_journal/data/trading_journal_export.dart',
    ).readAsStringSync();

    expect(sourceText, contains("result.remove('clientId')"));
    expect(sourceText, contains("normalized.contains('apikey')"));
    expect(sourceText, contains("normalized.contains('secret')"));
    expect(sourceText, contains("normalized.contains('credential')"));
    expect(sourceText, isNot(contains('BitunixApiCredentials')));
  });
}
