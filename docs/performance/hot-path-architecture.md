# Realtime hot-path performance evidence

Issue #198 software scope uses a bounded, fail-closed path:

`ingest validation -> rolling features -> playbook fan-out -> candidate evaluation -> ranking -> risk/allocation -> durable audit -> trade intent`

## Runtime guarantees

- Per-stream queues are bounded. Working-candle updates may be coalesced and may be dropped after a configured queue-age limit.
- Bootstrap, closed-candle, gap, reconciliation, duplicate, and out-of-order evidence is critical. Critical events are never silently dropped; capacity exhaustion returns a typed fail-closed error.
- Streams drain independently, so a slow symbol/timeframe cannot stall unrelated streams.
- Rolling EMA/ATR and 20-period features retain at most 21 candles. Corrections rebuild only the already-bounded retained snapshot; the common append path is incremental.
- Latency evidence is an in-memory bounded ring per stage. Correlation IDs connect measurements without adding I/O to the realtime path.
- UI, LLM/supervisor, HTTP, export, and durable-history I/O are forbidden from the critical primitives and covered by a source-isolation test.

## Reproducible software gate

Run from `src/client/quantara_app`:

```sh
dart run tool/hot_path_benchmark.dart --output hot-path-performance.json
```

The deterministic target load is 100 symbols x 5 timeframes x 3 strategies. A second 150 x 5 x 4 stress envelope exposes nonlinear behavior. The JSON artifact includes configuration, seed, deterministic checksum, total elapsed time, process RSS before/after, and p50/p95/p99 for every named stage. CI fails if the combined synthetic software gate exceeds 60 seconds. The generous ceiling detects catastrophic regressions without pretending shared CI hardware is a physical-device benchmark.

## Evidence boundary

The benchmark artifact explicitly sets `physicalAndroidEvidence` to `false`. Emulator launch checks, software benchmarks, and successful APK/Windows builds do not satisfy physical Android sustained-load, frame-timing, thermal, battery, or network-fault acceptance. Issue closure still requires recorded evidence from a real target Android device and representative desktop hardware; that blocker must not be inferred or waived from this software artifact.

This work does not alter safety, freshness, risk, allocator, protection, autonomy authorization, or execution authority. The risk/allocation and durable-audit stages in the synthetic harness are workload labels only, not alternate trading implementations.
