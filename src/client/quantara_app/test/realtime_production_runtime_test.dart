import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/owner_alpha/data/realtime_production_runtime.dart';
import 'package:quantara_app/features/owner_alpha/domain/owner_alpha_models.dart';
import 'package:quantara_app/features/owner_alpha/domain/realtime_market_runtime_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('settings produce a bounded four-timeframe public universe', () {
    final universe = RealtimeSettingsUniverse.build(
      const OwnerAlphaSettings(
        symbols: ['BTCUSDT', 'ETHUSDT', 'BTCUSDT'],
        capital: 10000,
        riskPercent: 0.5,
      ),
    );

    expect(universe.streams, hasLength(8));
    expect(universe.maximumStreams, 48);
    expect(
      universe.streams.map((stream) => stream.interval.timeframe).toSet(),
      {'5m', '15m', '1h', '4h'},
    );
  });

  test('foreground host starts, pauses, resumes and stops safely', () async {
    final runtime = _FakeRuntime();
    final host = RealtimeMarketHost(
      runtime: runtime,
      pollInterval: const Duration(milliseconds: 250),
    );

    await host.initialize();
    expect(runtime.starts, 1);
    expect(host.value.health?.state, RealtimeMarketRuntimeState.live);

    host.didChangeAppLifecycleState(AppLifecycleState.paused);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(runtime.pauses, 1);

    host.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(runtime.resumes, 1);

    host.dispose();
    await Future<void>.delayed(Duration.zero);
    expect(runtime.stops, 1);
  });

  test('invalid or oversized settings fail closed', () {
    expect(
      () => RealtimeSettingsUniverse.build(
        const OwnerAlphaSettings(symbols: [], capital: 10000, riskPercent: 0.5),
      ),
      throwsStateError,
    );
  });
}

final class _FakeRuntime implements RealtimeMarketRuntimeLifecycle {
  var starts = 0;
  var pauses = 0;
  var resumes = 0;
  var stops = 0;
  RealtimeMarketRuntimeState _state = RealtimeMarketRuntimeState.idle;

  @override
  RealtimeMarketRuntimeState get state => _state;

  @override
  RealtimeMarketHealthSnapshot get health => RealtimeMarketHealthSnapshot(
    state: _state,
    configuredStreams: 8,
    activeShards: 1,
    liveShards: _state == RealtimeMarketRuntimeState.live ? 1 : 0,
    eventsReceived: 0,
    klineEventsReceived: 0,
    closedCandleEvents: 0,
    gapEvents: 0,
    reconciliationEvents: 0,
    candidateEvaluations: 0,
    candidateCommits: 0,
    reconnectTransitions: 0,
    malformedPayloadFaults: 0,
    backpressureFaults: 0,
    p95TransportLag: Duration.zero,
    p95PipelineLatency: Duration.zero,
    lastEventAtUtc: null,
    lastFaultAtUtc: null,
    lastFaultMessage: null,
  );

  @override
  Future<void> start() async {
    starts++;
    _state = RealtimeMarketRuntimeState.live;
  }

  @override
  Future<void> pause() async {
    pauses++;
    _state = RealtimeMarketRuntimeState.paused;
  }

  @override
  Future<void> resume() async {
    resumes++;
    _state = RealtimeMarketRuntimeState.live;
  }

  @override
  Future<void> stop() async {
    stops++;
    _state = RealtimeMarketRuntimeState.stopped;
  }
}
