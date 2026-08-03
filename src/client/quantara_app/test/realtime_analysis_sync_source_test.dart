import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('runtime synchronizes every pipeline update before analysis gate', () {
    final source = File(
      'lib/features/owner_alpha/data/realtime_market_application.dart',
    ).readAsStringSync();
    final capabilityCheck = source.indexOf(
      'analysisGateway is RealtimeMarketAnalysisSynchronizer',
    );
    final synchronize = source.indexOf(
      'await synchronizer.synchronize(update);',
    );
    final candidateGate = source.indexOf(
      'if (!update.allowsCandidatePreparation) return;',
    );

    expect(capabilityCheck, greaterThanOrEqualTo(0));
    expect(synchronize, greaterThan(capabilityCheck));
    expect(candidateGate, greaterThan(synchronize));
    expect(source, contains('Realtime analysis synchronization failed'));
  });
}
