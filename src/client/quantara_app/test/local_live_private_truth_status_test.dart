import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/auto_trade/domain/local_live_trade_models.dart';

void main() {
  test('private WS health lag and metrics survive Local Live status JSON', () {
    final now = DateTime.utc(2026, 8, 16, 1);
    final status = LocalLiveTradeStatus(
      state: LocalLiveTradeState.managingOnly,
      updatedAt: now,
      message: 'Private account truth is stale.',
      entryBlockReason: 'privateAccountState:heartbeatStale',
      privateTruthHealth: 'stale',
      privateTruthLagReason: 'heartbeatStale',
      privateTruthAgeMs: 13000,
      privateTruthRestVerificationAgeMs: 72000,
      privateTruthTelemetry: const {
        'eventToLocalP95Ms': 42,
        'restRequestsLastMinute': 4,
        'hotHistoryPagesPerRequest': 0,
        'entryBlocks': 2,
      },
      entriesEnabled: false,
    );

    final decoded = LocalLiveTradeStatus.fromJson(status.toJson());
    expect(decoded.privateTruthHealth, 'stale');
    expect(decoded.privateTruthLagReason, 'heartbeatStale');
    expect(decoded.privateTruthAgeMs, 13000);
    expect(decoded.privateTruthRestVerificationAgeMs, 72000);
    expect(decoded.privateTruthTelemetry?['eventToLocalP95Ms'], 42);
    expect(decoded.privateTruthTelemetry?['hotHistoryPagesPerRequest'], 0);
    expect(decoded.entriesEnabled, isFalse);
  });
}
