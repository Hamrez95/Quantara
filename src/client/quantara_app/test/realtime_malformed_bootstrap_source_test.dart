import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('production realtime keeps malformed bootstrap isolation guards', () {
    final backfill = File(
      'lib/features/owner_alpha/data/bitunix_candle_backfill_source.dart',
    ).readAsStringSync();
    final application = File(
      'lib/features/owner_alpha/data/realtime_market_application.dart',
    ).readAsStringSync();
    final production = File(
      'lib/features/owner_alpha/data/realtime_production_runtime.dart',
    ).readAsStringSync();
    final page = File(
      'lib/features/owner_alpha/presentation/owner_alpha_page.dart',
    ).readAsStringSync();

    expect(backfill, contains('allowedMalformedRows'));
    expect(backfill, contains('maximumMalformedRecentRows'));
    expect(application, contains('_quarantinedStreamFaults'));
    expect(
      application,
      contains("'Realtime bootstrap failed for every configured stream.'"),
    );
    expect(application, contains('for (final stream in _activeStreams)'));
    expect(production, contains('maximumMalformedRecentRows: 8'));
    expect(production, contains('closedCandleLimit: 120'));
    expect(page, contains('health.quarantinedStreams'));
    expect(page, contains('Degraded live monitoring'));
    expect(page, contains('canResumeEntries'));
    expect(page, contains('Resume entries'));
  });
}
