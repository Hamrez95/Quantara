import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/auto_trade/application/private_truth_telemetry.dart';
import 'package:quantara_app/features/auto_trade/domain/private_truth_models.dart';

void main() {
  final now = DateTime.utc(2026, 8, 16, 1);

  PrivateTruthEvent eventWithLatency(int milliseconds, String identity) =>
      PrivateTruthEvent(
        eventIdentity: identity,
        channel: PrivateTruthChannel.balance,
        exchangeTimestampUtc: now,
        receivedAtUtc: now.add(Duration(milliseconds: milliseconds - 1)),
        processedAtUtc: now.add(Duration(milliseconds: milliseconds)),
        payload: const PrivateBalanceUpdate(
          coin: 'USDT',
          available: 100,
          frozen: 0,
          margin: 0,
          isolationFrozen: 0,
          crossFrozen: 0,
          isolationMargin: 0,
          crossMargin: 0,
        ),
      );

  PrivateTruthProjection projection({
    PrivateTruthMetrics metrics = const PrivateTruthMetrics(),
  }) => PrivateTruthProjection(
    cycleId: 1,
    health: PrivateTruthHealth.fresh,
    lagReason: PrivateTruthLagReason.none,
    updatedAtUtc: now,
    restVerifiedAtUtc: now,
    balances: const {},
    orders: const {},
    positions: const {},
    protections: const {},
    resourceExchangeTimes: const {},
    recentEventIdentities: const [],
    metrics: metrics,
  );

  test('computes deterministic p50 p95 p99 from bounded event samples', () {
    final collector = PrivateTruthTelemetryCollector();
    for (var i = 1; i <= 100; i++) {
      collector.recordEvent(eventWithLatency(i, 'e-$i'));
    }

    final snapshot = collector.snapshot(
      projection: projection(),
      droppedOrMalformedEvents: 0,
      nowUtc: now.add(const Duration(seconds: 1)),
    );

    expect(snapshot.eventToLocalP50Ms, 51);
    expect(snapshot.eventToLocalP95Ms, 96);
    expect(snapshot.eventToLocalP99Ms, 100);
  });

  test('reports exact rolling REST count and Hot Path history pages as zero', () {
    final collector = PrivateTruthTelemetryCollector();
    collector.recordRestRequests(4, now);
    collector.recordRestRequests(2, now.add(const Duration(seconds: 10)));

    final active = collector.snapshot(
      projection: projection(),
      droppedOrMalformedEvents: 3,
      nowUtc: now.add(const Duration(seconds: 30)),
    );
    expect(active.restRequestsLastMinute, 6);
    expect(active.hotHistoryPagesPerRequest, 0);
    expect(active.droppedOrMalformedEvents, 3);

    final expired = collector.snapshot(
      projection: projection(),
      droppedOrMalformedEvents: 3,
      nowUtc: now.add(const Duration(minutes: 2)),
    );
    expect(expired.restRequestsLastMinute, 0);
  });

  test('tracks reconnect recovery and current entry-block duration', () {
    final collector = PrivateTruthTelemetryCollector();
    collector.recordReconnect(now);
    collector.recordEntryGate(canAdmit: false, atUtc: now);
    collector.recordReconciled(now.add(const Duration(milliseconds: 750)));

    final blocked = collector.snapshot(
      projection: projection(
        metrics: const PrivateTruthMetrics(entryBlocks: 1),
      ),
      droppedOrMalformedEvents: 0,
      nowUtc: now.add(const Duration(seconds: 2)),
    );
    expect(blocked.lastReconnectRecoveryMs, 750);
    expect(blocked.currentEntryBlockDurationMs, 2000);
    expect(blocked.entryBlocks, 1);

    collector.recordEntryGate(
      canAdmit: true,
      atUtc: now.add(const Duration(seconds: 3)),
    );
    final recovered = collector.snapshot(
      projection: projection(),
      droppedOrMalformedEvents: 0,
      nowUtc: now.add(const Duration(seconds: 4)),
    );
    expect(recovered.currentEntryBlockDurationMs, 0);
  });
}
