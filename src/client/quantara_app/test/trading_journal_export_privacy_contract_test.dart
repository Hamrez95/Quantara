import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('privacy exporter pseudonymizes identifiers before JSON and CSV output', () {
    final source = File(
      'lib/features/trading_journal/data/trading_journal_export.dart',
    ).readAsStringSync();

    expect(source, contains('_TradingJournalExportPseudonyms'));
    expect(source, contains('pseudonymizeEmbedded'));
    expect(source, contains('journalTradeId'));
    expect(source, contains('positionId'));
    expect(source, contains('orderId'));
    expect(source, contains('tradeId'));
  });
}
