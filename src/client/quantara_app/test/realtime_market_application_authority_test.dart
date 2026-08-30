import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('realtime public market runtime has no order authority path', () {
    final runtime = File(
      'lib/features/owner_alpha/data/realtime_market_application.dart',
    ).readAsStringSync();

    expect(runtime, contains('BitunixPublicStreamFleetFactory'));
    expect(runtime, contains('RealtimeCandlePipelineCoordinator'));
    expect(runtime, contains('RealtimeCandidateCoordinator'));
    expect(runtime, isNot(contains('bitunix_private_api_client')));
    expect(runtime, isNot(contains('bitunix_local_live_api_client')));
    expect(runtime, isNot(contains('local_live_trade_controller')));
    expect(runtime, isNot(contains('/trade/place_order')));
    expect(runtime, isNot(contains('withdraw')));
    expect(runtime, isNot(contains('transfer')));
    expect(runtime, isNot(contains('apiKey')));
    expect(runtime, isNot(contains('secretKey')));
  });
}
