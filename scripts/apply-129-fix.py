from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    file = Path(path)
    text = file.read_text()
    if old not in text:
        raise SystemExit(f'missing patch anchor in {path}: {old[:80]!r}')
    file.write_text(text.replace(old, new, 1))


backfill = 'src/client/quantara_app/lib/features/owner_alpha/data/bitunix_candle_backfill_source.dart'
replace_once(
    backfill,
    "    this.requestSpacing = const Duration(milliseconds: 120),\n    String apiOrigin = 'https://fapi.bitunix.com',\n",
    "    this.requestSpacing = const Duration(milliseconds: 120),\n    this.maximumMalformedRecentRows = 8,\n    String apiOrigin = 'https://fapi.bitunix.com',\n",
)
replace_once(
    backfill,
    "    if (requestSpacing < const Duration(milliseconds: 100)) {\n      throw ArgumentError.value(\n        requestSpacing,\n        'requestSpacing',\n        'Bitunix public market REST is limited to ten requests per second.',\n      );\n    }\n",
    "    if (requestSpacing < const Duration(milliseconds: 100)) {\n      throw ArgumentError.value(\n        requestSpacing,\n        'requestSpacing',\n        'Bitunix public market REST is limited to ten requests per second.',\n      );\n    }\n    if (maximumMalformedRecentRows < 0 || maximumMalformedRecentRows > 20) {\n      throw ArgumentError.value(\n        maximumMalformedRecentRows,\n        'maximumMalformedRecentRows',\n        'Expected a bounded value from 0 to 20.',\n      );\n    }\n",
)
replace_once(
    backfill,
    "  final Duration requestSpacing;\n  final Uri apiOrigin;\n",
    "  final Duration requestSpacing;\n  final int maximumMalformedRecentRows;\n  final Uri apiOrigin;\n",
)
replace_once(
    backfill,
    "        'type': 'LAST_PRICE',\n      },\n    );\n    final closed = candles\n",
    "        'type': 'LAST_PRICE',\n      },\n      allowedMalformedRows: maximumMalformedRecentRows,\n    );\n    final closed = candles\n",
)
replace_once(
    backfill,
    "  Future<List<ChartCandle>> _request({\n    required RealtimeCandleStreamKey key,\n    required Map<String, String> query,\n  }) async {\n",
    "  Future<List<ChartCandle>> _request({\n    required RealtimeCandleStreamKey key,\n    required Map<String, String> query,\n    int allowedMalformedRows = 0,\n  }) async {\n",
)
old_loop = """    final byTime = <DateTime, ChartCandle>{};
    for (final raw in rawData) {
      final item = _object(raw);
      final openTime = DateTime.fromMillisecondsSinceEpoch(
        _integer(item['time'], 'time'),
        isUtc: true,
      );
      if (openTime.isBefore(DateTime.utc(2020))) {
        throw const FormatException('Bitunix returned an invalid candle time.');
      }
      final open = _positive(item['open'], 'open');
      final high = _positive(item['high'], 'high');
      final low = _positive(item['low'], 'low');
      final close = _positive(item['close'], 'close');
      final candle = ChartCandle(
        openTime: openTime,
        open: open,
        high: high,
        low: low,
        close: close,
        volume: _nonNegative(
          item['baseVol'] ?? item['volume'] ?? item['quoteVol'],
          'baseVol',
        ),
      );
      if (!candle.isValid) {
        throw FormatException('Bitunix returned invalid OHLC for ${key.id}.');
      }
      byTime[openTime] = candle;
    }
"""
new_loop = """    final byTime = <DateTime, ChartCandle>{};
    var malformedRows = 0;
    for (final raw in rawData) {
      try {
        final item = _object(raw);
        final openTime = DateTime.fromMillisecondsSinceEpoch(
          _integer(item['time'], 'time'),
          isUtc: true,
        );
        if (openTime.isBefore(DateTime.utc(2020))) {
          throw const FormatException(
            'Bitunix returned an invalid candle time.',
          );
        }
        final open = _positive(item['open'], 'open');
        final high = _positive(item['high'], 'high');
        final low = _positive(item['low'], 'low');
        final close = _positive(item['close'], 'close');
        final candle = ChartCandle(
          openTime: openTime,
          open: open,
          high: high,
          low: low,
          close: close,
          volume: _nonNegative(
            item['baseVol'] ?? item['volume'] ?? item['quoteVol'],
            'baseVol',
          ),
        );
        if (!candle.isValid) {
          throw FormatException(
            'Bitunix returned invalid OHLC for ${key.id}.',
          );
        }
        byTime[openTime] = candle;
      } on FormatException {
        if (malformedRows >= allowedMalformedRows) rethrow;
        malformedRows++;
      }
    }
"""
replace_once(backfill, old_loop, new_loop)

models = 'src/client/quantara_app/lib/features/owner_alpha/domain/realtime_market_runtime_models.dart'
replace_once(
    models,
    "    required this.configuredStreams,\n    required this.activeShards,\n",
    "    required this.configuredStreams,\n    this.activeStreams = 0,\n    this.quarantinedStreams = 0,\n    required this.activeShards,\n",
)
replace_once(
    models,
    "    required this.reconnectTransitions,\n    required this.malformedPayloadFaults,\n",
    "    required this.reconnectTransitions,\n    this.bootstrapFaults = 0,\n    required this.malformedPayloadFaults,\n",
)
replace_once(
    models,
    "  final int configuredStreams;\n  final int activeShards;\n",
    "  final int configuredStreams;\n  final int activeStreams;\n  final int quarantinedStreams;\n  final int activeShards;\n",
)
replace_once(
    models,
    "  final int reconnectTransitions;\n  final int malformedPayloadFaults;\n",
    "  final int reconnectTransitions;\n  final int bootstrapFaults;\n  final int malformedPayloadFaults;\n",
)
replace_once(
    models,
    "      state == RealtimeMarketRuntimeState.live &&\n      activeShards > 0 &&\n      liveShards == activeShards;\n",
    "      state == RealtimeMarketRuntimeState.live &&\n      activeStreams > 0 &&\n      quarantinedStreams == 0 &&\n      activeShards > 0 &&\n      liveShards == activeShards;\n\n  bool get degraded =>\n      state == RealtimeMarketRuntimeState.live && quarantinedStreams > 0;\n",
)

app = 'src/client/quantara_app/lib/features/owner_alpha/data/realtime_market_application.dart'
replace_once(
    app,
    "  final Map<int, BitunixPublicConnectionState> _shardStates = {};\n",
    "  final Map<int, BitunixPublicConnectionState> _shardStates = {};\n  final List<RealtimeCandleStreamKey> _activeStreams = [];\n  final Map<String, String> _quarantinedStreamFaults = {};\n",
)
replace_once(
    app,
    "    configuredStreams: universe.streams.length,\n    activeShards: _fleet?.shardCount ?? 0,\n",
    "    configuredStreams: universe.streams.length,\n    activeStreams: _activeStreams.length,\n    quarantinedStreams: _quarantinedStreamFaults.length,\n    activeShards: _fleet?.shardCount ?? 0,\n",
)
old_bootstrap = """      _setState(RealtimeMarketRuntimeState.bootstrapping);
      for (var index = 0; index < universe.streams.length; index++) {
        await _candleCoordinator.bootstrap(
          key: universe.streams[index],
          closedCandleLimit: closedCandleLimit,
        );
        if (index + 1 < universe.streams.length &&
            bootstrapSpacing > Duration.zero) {
          await _delay(bootstrapSpacing);
        }
      }

      _shardStates.clear();
      final fleet = fleetFactory.build(
        subscriptions: universe.subscriptions,
"""
new_bootstrap = """      _setState(RealtimeMarketRuntimeState.bootstrapping);
      _activeStreams.clear();
      _quarantinedStreamFaults.clear();
      for (var index = 0; index < universe.streams.length; index++) {
        final stream = universe.streams[index];
        try {
          await _candleCoordinator.bootstrap(
            key: stream,
            closedCandleLimit: closedCandleLimit,
          );
          _activeStreams.add(stream);
        } on Object catch (error) {
          final message = error.toString();
          _quarantinedStreamFaults[stream.id] = message;
          _metrics.recordBootstrapFault(
            streamId: stream.id,
            message: message,
            occurredAtUtc: _clock(),
          );
        }
        if (index + 1 < universe.streams.length &&
            bootstrapSpacing > Duration.zero) {
          await _delay(bootstrapSpacing);
        }
      }
      if (_activeStreams.isEmpty) {
        throw StateError(
          'Realtime bootstrap failed for every configured stream.',
        );
      }

      _shardStates.clear();
      final fleet = fleetFactory.build(
        subscriptions: [
          for (final stream in _activeStreams)
            BitunixPublicSubscription.kline(
              symbol: stream.symbol,
              interval: stream.interval,
            ),
        ],
"""
replace_once(app, old_bootstrap, new_bootstrap)
replace_once(
    app,
    "  int reconnectTransitions = 0;\n  int malformedPayloadFaults = 0;\n",
    "  int reconnectTransitions = 0;\n  int bootstrapFaults = 0;\n  int malformedPayloadFaults = 0;\n",
)
replace_once(
    app,
    "  void recordTransportFault(BitunixPublicStreamFault fault) {\n",
    "  void recordBootstrapFault({\n    required String streamId,\n    required String message,\n    required DateTime occurredAtUtc,\n  }) {\n    bootstrapFaults++;\n    recordFault(\n      message: 'Realtime bootstrap quarantined $streamId: $message',\n      occurredAtUtc: occurredAtUtc,\n    );\n  }\n\n  void recordTransportFault(BitunixPublicStreamFault fault) {\n",
)
replace_once(
    app,
    "    required int configuredStreams,\n    required int activeShards,\n",
    "    required int configuredStreams,\n    required int activeStreams,\n    required int quarantinedStreams,\n    required int activeShards,\n",
)
replace_once(
    app,
    "    configuredStreams: configuredStreams,\n    activeShards: activeShards,\n",
    "    configuredStreams: configuredStreams,\n    activeStreams: activeStreams,\n    quarantinedStreams: quarantinedStreams,\n    activeShards: activeShards,\n",
)
replace_once(
    app,
    "    reconnectTransitions: reconnectTransitions,\n    malformedPayloadFaults: malformedPayloadFaults,\n",
    "    reconnectTransitions: reconnectTransitions,\n    bootstrapFaults: bootstrapFaults,\n    malformedPayloadFaults: malformedPayloadFaults,\n",
)

production = 'src/client/quantara_app/lib/features/owner_alpha/data/realtime_production_runtime.dart'
replace_once(
    production,
    "      backfillSource: BitunixCandleBackfillSource(client: client),\n",
    "      backfillSource: BitunixCandleBackfillSource(\n        client: client,\n        maximumMalformedRecentRows: 8,\n      ),\n",
)
replace_once(
    production,
    "      closedCandleLimit: 200,\n",
    "      closedCandleLimit: 120,\n",
)

page = 'src/client/quantara_app/lib/features/owner_alpha/presentation/owner_alpha_page.dart'
replace_once(
    page,
    "            RealtimeMarketRuntimeState.live => strings.t(\n              'پایش زنده',\n              'Live monitoring',\n            ),\n",
    "            RealtimeMarketRuntimeState.live => health.degraded\n                ? strings.t('پایش زنده محدود', 'Degraded live monitoring')\n                : strings.t('پایش زنده', 'Live monitoring'),\n",
)
replace_once(
    page,
    "            '${health.configuredStreams} جریان · ${health.liveShards}/${health.activeShards} اتصال · تأخیر p95 شبکه ${health.p95TransportLag.inMilliseconds}ms · پردازش ${health.p95PipelineLatency.inMilliseconds}ms',\n            '${health.configuredStreams} streams · ${health.liveShards}/${health.activeShards} shards · p95 transport ${health.p95TransportLag.inMilliseconds}ms · processing ${health.p95PipelineLatency.inMilliseconds}ms',\n",
    "            '${health.activeStreams}/${health.configuredStreams} جریان سالم · ${health.liveShards}/${health.activeShards} اتصال · تأخیر p95 شبکه ${health.p95TransportLag.inMilliseconds}ms · پردازش ${health.p95PipelineLatency.inMilliseconds}ms',\n            '${health.activeStreams}/${health.configuredStreams} healthy streams · ${health.liveShards}/${health.activeShards} shards · p95 transport ${health.p95TransportLag.inMilliseconds}ms · processing ${health.p95PipelineLatency.inMilliseconds}ms',\n",
)
replace_once(
    page,
    "    final error = monitor.error;\n",
    "    final error = monitor.error;\n    final degradedDetail = health != null && health.quarantinedStreams > 0\n        ? strings.t(\n            '${health.quarantinedStreams} جریان به‌دلیل داده ناسالم قرنطینه شد؛ سایر نمادها فعال مانده‌اند.',\n            '${health.quarantinedStreams} stream was quarantined for malformed data; healthy symbols remain active.',\n          )\n        : null;\n    final detail = error ?? degradedDetail ?? limitation;\n",
)
replace_once(
    page,
    "      label: '$status. $metrics. $limitation',\n",
    "      label: '$status. $metrics. $detail',\n",
)
replace_once(
    page,
    "                      error == null ? limitation : '$limitation $error',\n",
    "                      detail,\n",
)
replace_once(
    page,
    "                        color: error == null\n                            ? scheme.onSurfaceVariant\n                            : scheme.error,\n",
    "                        color: error != null || degradedDetail != null\n                            ? scheme.error\n                            : scheme.onSurfaceVariant,\n",
)

backfill_test = 'src/client/quantara_app/test/bitunix_candle_backfill_source_test.dart'
anchor = """    test('paginates an exact range beyond the 200-candle API limit', () async {
"""
addition = """    test('skips a bounded malformed row in recent history', () async {
      final start = DateTime.utc(2026, 8, 2, 10);
      final now = start.add(const Duration(minutes: 150));
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'code': 0,
            'data': [
              for (var index = 0; index < 30; index++)
                index == 3
                    ? {
                        ..._jsonCandle(
                          start.add(Duration(minutes: index * 5)),
                          index,
                        ),
                        'high': '99',
                        'close': '101',
                      }
                    : _jsonCandle(
                        start.add(Duration(minutes: index * 5)),
                        index,
                      ),
            ],
          }),
          200,
        );
      });
      final source = BitunixCandleBackfillSource(client: client);

      final candles = await source.loadRecentClosed(
        key: key,
        limit: 20,
        nowUtc: now,
      );

      expect(candles, hasLength(20));
      expect(candles.every((candle) => candle.isValid), isTrue);
      expect(candles.any((candle) => candle.openTime == start), isFalse);
    });

    test('fails recent history after the malformed-row budget is exceeded', () async {
      final start = DateTime.utc(2026, 8, 2, 10);
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'code': 0,
            'data': [
              for (var index = 0; index < 24; index++)
                index < 2
                    ? {
                        ..._jsonCandle(
                          start.add(Duration(minutes: index * 5)),
                          index,
                        ),
                        'high': '99',
                        'close': '101',
                      }
                    : _jsonCandle(
                        start.add(Duration(minutes: index * 5)),
                        index,
                      ),
            ],
          }),
          200,
        );
      });
      final source = BitunixCandleBackfillSource(
        client: client,
        maximumMalformedRecentRows: 1,
      );

      await expectLater(
        source.loadRecentClosed(
          key: key,
          limit: 20,
          nowUtc: start.add(const Duration(minutes: 120)),
        ),
        throwsFormatException,
      );
    });

"""
replace_once(backfill_test, anchor, addition + anchor)
replace_once(
    backfill_test,
    "            requestSpacing: const Duration(milliseconds: 99),\n          ),\n          throwsArgumentError,\n        );\n",
    "            requestSpacing: const Duration(milliseconds: 99),\n          ),\n          throwsArgumentError,\n        );\n        expect(\n          () => BitunixCandleBackfillSource(\n            client: MockClient((request) async => http.Response('{}', 200)),\n            maximumMalformedRecentRows: 21,\n          ),\n          throwsArgumentError,\n        );\n",
)

app_test = 'src/client/quantara_app/test/realtime_market_application_test.dart'
anchor = """    test(
      'stops a constructed fleet after synchronous startup failure',
"""
addition = """    test('quarantines one failed stream and connects the healthy stream', () async {
      final avax = RealtimeCandleStreamKey(
        symbol: 'AVAXUSDT',
        interval: BitunixKlineInterval.fifteenMinutes,
      );
      final clock = _MutableClock(DateTime.utc(2026, 8, 2, 10, 59));
      final source = _SelectiveBackfillSource(
        recent: _candles(historyStart, 20, interval: key.interval.duration),
        failures: {avax.id: const FormatException('invalid AVAX OHLC')},
      );
      final fleetFactory = _FakeFleetFactory();
      final application = RealtimeMarketApplication(
        universe: RealtimeMarketUniverse([key, avax]),
        backfillSource: source,
        fleetFactory: fleetFactory,
        analysisGateway: const _EmptyAnalysisGateway(),
        candidateCoordinator: RealtimeCandidateCoordinator(
          registry: RealtimeCandidateRegistry(),
          auditStore: _FakeAuditStore(),
        ),
        projection: _FakeProjection(),
        closedCandleLimit: 20,
        bootstrapSpacing: Duration.zero,
        clock: clock.call,
        delay: (_) async {},
      );

      await application.start();
      await _flushMicrotasks();

      expect(application.state, RealtimeMarketRuntimeState.live);
      expect(application.health.configuredStreams, 2);
      expect(application.health.activeStreams, 1);
      expect(application.health.quarantinedStreams, 1);
      expect(application.health.bootstrapFaults, 1);
      expect(application.health.degraded, isTrue);
      expect(application.health.discoveryHealthy, isFalse);
      expect(fleetFactory.subscriptions, hasLength(1));
      expect(fleetFactory.subscriptions.single.symbol, 'BTCUSDT');
      expect(application.health.lastFaultMessage, contains(avax.id));

      await application.stop();
    });

    test('fails startup when every configured stream is quarantined', () async {
      final avax = RealtimeCandleStreamKey(
        symbol: 'AVAXUSDT',
        interval: BitunixKlineInterval.fifteenMinutes,
      );
      final clock = _MutableClock(DateTime.utc(2026, 8, 2, 10, 59));
      final source = _SelectiveBackfillSource(
        recent: _candles(historyStart, 20, interval: key.interval.duration),
        failures: {
          key.id: const FormatException('invalid BTC OHLC'),
          avax.id: const FormatException('invalid AVAX OHLC'),
        },
      );
      final fleetFactory = _FakeFleetFactory();
      final application = RealtimeMarketApplication(
        universe: RealtimeMarketUniverse([key, avax]),
        backfillSource: source,
        fleetFactory: fleetFactory,
        analysisGateway: const _EmptyAnalysisGateway(),
        candidateCoordinator: RealtimeCandidateCoordinator(
          registry: RealtimeCandidateRegistry(),
          auditStore: _FakeAuditStore(),
        ),
        projection: _FakeProjection(),
        closedCandleLimit: 20,
        bootstrapSpacing: Duration.zero,
        clock: clock.call,
        delay: (_) async {},
      );

      await expectLater(application.start(), throwsStateError);

      expect(application.state, RealtimeMarketRuntimeState.failed);
      expect(application.health.activeStreams, 0);
      expect(application.health.quarantinedStreams, 2);
      expect(application.health.bootstrapFaults, 2);
      expect(fleetFactory.fleets, isEmpty);
      await application.stop();
    });

"""
replace_once(app_test, anchor, addition + anchor)
insert_before = """final class _FakeBackfillSource implements RealtimeCandleBackfillSource {
"""
selective = """final class _SelectiveBackfillSource
    implements RealtimeCandleBackfillSource {
  _SelectiveBackfillSource({required this.recent, required this.failures});

  final List<ChartCandle> recent;
  final Map<String, Object> failures;

  @override
  Future<List<ChartCandle>> loadRecentClosed({
    required RealtimeCandleStreamKey key,
    required int limit,
    required DateTime nowUtc,
  }) async {
    final failure = failures[key.id];
    if (failure != null) throw failure;
    return recent.sublist(recent.length - limit);
  }

  @override
  Future<List<ChartCandle>> loadClosedRange({
    required RealtimeCandleStreamKey key,
    required DateTime fromInclusiveUtc,
    required DateTime toExclusiveUtc,
  }) async => const [];
}

"""
replace_once(app_test, insert_before, selective + insert_before)

production_test = 'src/client/quantara_app/test/realtime_production_runtime_test.dart'
text = Path(production_test).read_text()
if "closedCandleLimit: 120" not in Path(production).read_text():
    raise SystemExit('production history reserve was not applied')

print('Issue 129 patch applied successfully.')
