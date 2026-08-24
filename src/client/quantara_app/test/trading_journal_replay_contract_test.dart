import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('journal replay contract never consults a live analysis fallback', () {
    final source = File(
      'lib/features/trading_journal/domain/trading_journal_replay.dart',
    ).readAsStringSync();

    expect(source, contains('decodeFromIndicatorSnapshot'));
    expect(source, isNot(contains('liveAnalysis')));
    expect(source, isNot(contains('liveAnalyses')));
    expect(source, isNot(contains('currentIdea')));
  });
}
