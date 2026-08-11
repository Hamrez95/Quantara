import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/owner_alpha/data/realtime_production_runtime.dart';
import 'package:quantara_app/features/owner_alpha/domain/owner_alpha_models.dart';
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

  test('brief background transition is cancelled when the app resumes', () async {
    final runtime = _FakeRuntime();
    final host = RealtimeMarketHost(
      runtime: runtime,
      pollInterval: const Duration(milliseconds: 250),
      backgroundPauseGrace: const Duration(milliseconds: 50),
    );

    await host.initialize();
    host.didChangeAppLifecycleState(AppLifecycleState.paused);
    await Future<void>.delayed(const Duration(milliseconds: 15));
    host.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await Future<void>.delayed(const Duration(milliseconds: 60));

    expect(runtime.pauses, 0);
    expect(runtime.resumes, 0);
    expect(runtime.state, RealtimeMarketRuntimeState.live);

    host.dispose();
    await Future<void>.delayed(Duration.zero);
  });

  test('sustained backgrounding pauses after grace and resumes safely', () async {
    final runtime = _FakeRuntime();
    final host = RealtimeMarketHost(
      runtime: runtime,
      pollInterval: const Duration(milliseconds: 250),
      backgroundPauseGrace: const Duration(milliseconds: 20),
    );

    await host.initialize();
    host.didChangeAppLifecycleState(AppLifecycleState.paused);
    await Future<void>.delayed(const Duration(milliseconds: 35));

    expect(runtime.pauses, 1);
    expect(runtime.state, RealtimeMarketRuntimeState.paused);

    host.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await Future<void>.delayed(Duration.zero);

    expect(runtime.resumes, 1);
    expect(runtime.state, RealtimeMarketRuntimeState.live);

    host.dispose();
    await Future<void>.delayed(Duration.zero);
  });

  test('degraded monitoring receives one bounded recovery restart', () async {
    final runtime = _FakeRuntime();
    final host = RealtimeMarketHost(
      runtime: runtime,
      pollInterval: const Duration(milliseconds: 10),
      backgroundPauseGrace: const Duration(milliseconds: 20),
    );

    await host.initialize();
    runtime.state = RealtimeMarketRuntimeState.degraded;
    await Future<void>.delayed(const Duration(milliseconds: 40));

    expect(runtime.restarts, 1);

    host.dispose();
    await Future<void>.delayed(Duration.zero);
  });

  test('invalid or oversized settings fail closed', () {
    expect(
      () => RealtimeSettingsUniverse.build(
        const OwnerAlphaSettings(
          symbols: [],
          capital: 1000,
          riskPercent: 1,
        ),
      ),
      throwsArgumentError,
    );
    expect(
      () => RealtimeSettingsUniverse.build(
        OwnerAlphaSettings(
          symbols: List<String>.generate(13, (index) => 'COIN${index}USDT'),
          capital: 1000,
          riskPercent: 1,
        ),
      ),
      throwsArgumentError,
    );
  });
}

final class _FakeRuntime implements RealtimeMarketRuntime {
  RealtimeMarketRuntimeState state = RealtimeMarketRuntimeState.stopped;
  int starts = 0;
  int pauses = 0;
  int resumes = 0;
  int restarts = 0;
  int stops = 0;

  @override
  RealtimeMarketRuntimeSnapshot get snapshot => RealtimeMarketRuntimeSnapshot(
    state: state,
    updatedAt: DateTime.now().toUtc(),
    activeStreams: const [],
    faults: const [],
  );

  @override
  Future<void> start() async {
    starts++;
    state = RealtimeMarketRuntimeState.live;
  }

  @override
  Future<void> pause() async {
    pauses++;
    state = RealtimeMarketRuntimeState.paused;
  }

  @override
  Future<void> resume() async {
    resumes++;
    state = RealtimeMarketRuntimeState.live;
  }

  @override
  Future<void> restart() async {
    restarts++;
    state = RealtimeMarketRuntimeState.live;
  }

  @override
  Future<void> stop() async {
    stops++;
    state = RealtimeMarketRuntimeState.stopped;
  }
}