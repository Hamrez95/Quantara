import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/owner_alpha/data/realtime_production_runtime.dart';
import 'package:quantara_app/features/owner_alpha/domain/owner_alpha_models.dart';
import 'package:quantara_app/features/owner_alpha/domain/realtime_candidate_models.dart';
import 'package:quantara_app/features/owner_alpha/domain/realtime_market_runtime_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('settings produce a bounded five-timeframe public universe', () {
    final universe = RealtimeSettingsUniverse.build(
      const OwnerAlphaSettings(
        symbols: ['BTCUSDT', 'ETHUSDT', 'BTCUSDT'],
        capital: 10000,
        riskPercent: 0.5,
      ),
    );

    expect(universe.streams, hasLength(10));
    expect(universe.maximumStreams, 48);
    expect(
      universe.streams.map((stream) => stream.interval.timeframe).toSet(),
      {'5m', '15m', '30m', '1h', '4h'},
    );
  });

  test(
    'transient inactive and hidden states do not pause monitoring',
    () async {
      final runtime = _FakeRuntime();
      final host = RealtimeMarketHost(
        runtime: runtime,
        pollInterval: const Duration(milliseconds: 250),
        backgroundPauseGrace: const Duration(milliseconds: 40),
      );

      await host.initialize();
      host.didChangeAppLifecycleState(AppLifecycleState.inactive);
      host.didChangeAppLifecycleState(AppLifecycleState.hidden);
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(runtime.starts, 1);
      expect(runtime.pauses, 0);
      expect(runtime.state, RealtimeMarketRuntimeState.live);

      host.dispose();
      await Future<void>.delayed(Duration.zero);
      expect(runtime.stops, 1);
    },
  );

  test(
    'brief background transition is cancelled when the app resumes',
    () async {
      final runtime = _FakeRuntime();
      final host = RealtimeMarketHost(
        runtime: runtime,
        pollInterval: const Duration(milliseconds: 250),
        backgroundPauseGrace: const Duration(milliseconds: 60),
      );

      await host.initialize();
      host.didChangeAppLifecycleState(AppLifecycleState.paused);
      await Future<void>.delayed(const Duration(milliseconds: 15));
      host.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(runtime.pauses, 0);
      expect(runtime.resumes, 0);
      expect(runtime.state, RealtimeMarketRuntimeState.live);

      host.dispose();
    },
  );

  test(
    'sustained backgrounding pauses after grace and resumes safely',
    () async {
      final runtime = _FakeRuntime();
      final host = RealtimeMarketHost(
        runtime: runtime,
        pollInterval: const Duration(milliseconds: 250),
        backgroundPauseGrace: const Duration(milliseconds: 20),
      );

      await host.initialize();
      host.didChangeAppLifecycleState(AppLifecycleState.paused);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(runtime.pauses, 1);
      expect(runtime.state, RealtimeMarketRuntimeState.paused);

      host.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(runtime.resumes, 1);
      expect(runtime.state, RealtimeMarketRuntimeState.live);

      host.dispose();
    },
  );

  test('degraded monitoring receives one bounded recovery restart', () async {
    final runtime = _FakeRuntime(degraded: true);
    final host = RealtimeMarketHost(
      runtime: runtime,
      pollInterval: const Duration(milliseconds: 250),
      degradedRetryInterval: const Duration(milliseconds: 150),
    );

    await host.initialize();
    await Future<void>.delayed(const Duration(milliseconds: 340));

    expect(runtime.pauses, 1);
    expect(runtime.resumes, 1);
    expect(host.value.operational, isTrue);
    expect(host.value.healthy, isFalse);

    host.dispose();
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
  _FakeRuntime({this.degraded = false});

  final bool degraded;
  var starts = 0;
  var pauses = 0;
  var resumes = 0;
  var stops = 0;
  RealtimeMarketRuntimeState _state = RealtimeMarketRuntimeState.idle;

  @override
  RealtimeMarketRuntimeState get state => _state;

  @override
  int get candidateSnapshotRevision => 0;

  @override
  List<RealtimeOpportunityCandidate> get radarCandidates => const [];

  @override
  RealtimeMarketHealthSnapshot get health => RealtimeMarketHealthSnapshot(
    state: _state,
    configuredStreams: 8,
    activeStreams: degraded ? 7 : 8,
    quarantinedStreams: degraded ? 1 : 0,
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
