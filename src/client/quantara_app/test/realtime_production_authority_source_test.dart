import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('foreground realtime wiring remains public-data-only', () {
    final runtime = File(
      'lib/features/owner_alpha/data/realtime_production_runtime.dart',
    ).readAsStringSync();
    final app = File('lib/app/quantara_app.dart').readAsStringSync();

    for (final forbidden in [
      'bitunix_private_api_client',
      'local_live_trade_service',
      'auto_trade_controller',
      'withdraw',
      'transfer',
      'placeOrder',
    ]) {
      expect(runtime, isNot(contains(forbidden)));
    }
    expect(runtime, contains('BitunixCandleBackfillSource'));
    expect(runtime, contains('BitunixRealtimePublicStreamFleetFactory'));
    expect(runtime, contains('DurableCandidateAuditStore'));
    expect(app, contains('PlatformRealtimeMarketHostFactory.create'));
    expect(app, contains('realtimeMonitor: _realtimeMarketHost'));
  });
}
