import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'journal detail renders only immutable decision-time chart evidence',
    () {
      final source = File(
        'lib/features/trading_journal/presentation/trading_journal_view.dart',
      ).readAsStringSync();

      expect(source, contains('TradingJournalReplay.decisionChart('));
      expect(source, contains('projection.plan,'));
      expect(source, contains('analysis: historicalAnalysis,'));
      expect(source, contains('currentIdea: null,'));

      expect(source, isNot(contains('widget.liveAnalyses[requestedKey]')));
      expect(source, isNot(contains('currentIdea: liveIdea')));
      expect(source, isNot(contains("const ['1h', '15m', '5m', '4h']")));

      expect(source, contains('Decision-time chart replay'));
      expect(
        source,
        contains('newer live data is never substituted for history'),
      );
    },
  );
}
