import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('journal-derived radar maps are only built on Journal destination', () {
    final source = File(
      'lib/features/owner_alpha/presentation/owner_alpha_page.dart',
    ).readAsStringSync();

    expect(source, contains('final journalLiveAnalyses = destination == 6'));
    expect(source, contains('final journalLiveIdeas = destination == 6'));
    expect(source, contains("const <String, TimeframeChartAnalysis>{}"));
    expect(source, contains("const <String, TradeIdea>{}"));
  });
}
