import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('private account reconciliation paginates both history endpoints', () {
    final source = File(
      'lib/features/auto_trade/data/bitunix_private_api_client.dart',
    ).readAsStringSync();

    expect(source, contains("'skip': '\$skip'"));
    expect(source, contains("'limit': '\$_historyPageSize'"));
    expect(source, contains("data['total']"));
    expect(source, contains("listKey: 'positionList'"));
    expect(source, contains("identityKey: 'positionId'"));
    expect(source, contains("listKey: 'tradeList'"));
    expect(source, contains("identityKey: 'tradeId'"));
    expect(source, contains('seenIdentities'));
    expect(source, contains('full history was not claimed'));
  });

  test('history pagination cannot silently truncate at the first 100 rows', () {
    final source = File(
      'lib/features/auto_trade/data/bitunix_private_api_client.dart',
    ).readAsStringSync();

    expect(source, contains('static const _historyPageSize = 100'));
    expect(source, contains('static const _historyMaxPages = 50'));
    expect(source, contains('skip += pageRows.length'));
    expect(source, contains('reachedReportedTotal'));
    expect(source, contains('Duration(milliseconds: 120)'));
  });
}
