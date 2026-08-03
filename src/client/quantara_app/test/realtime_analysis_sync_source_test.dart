import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('runtime synchronizes every pipeline update before analysis gate', () {
    final source = File(
      'lib/features/owner_alpha/data/realtime_market_application.dart',
    ).readAsStringSync();
    final synchronize = source.indexOf(
      'gateway is RealtimeMarketAnalysisSynchronizer',
    );
    final candidateGate = source.indexOf(
      'if (!update.allowsCandidatePreparation) return;',
    );

    expect(synchronize, greaterThanOrEqualTo(0));
    expect(candidateGate, greaterThan(synchronize));
    expect(source, contains('Realtime analysis synchronization failed'));
  });
}
