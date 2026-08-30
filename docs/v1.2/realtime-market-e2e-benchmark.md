# Realtime public transport end-to-end benchmark

This validation slice exercises the public market path through the production transport and composition contracts without credentials, account state or order authority.

## End-to-end path

`Fake REST bootstrap -> Fake public WebSocket -> Bitunix decoder -> candle pipeline -> bounded event bus -> analysis gateway -> candidate registry -> durable audit -> projection`

The transport and runtime remain production implementations. Only the network endpoints, REST history source, analysis fixture, audit sink and projection sink are test doubles.

## Reconnect regression

The reconnect scenario verifies that:

- REST bootstrap finishes before the first public subscription;
- a working Kline is accepted through the real public decoder and transport;
- an unexpected socket close causes a deterministic reconnect;
- replaying the same working Kline after reconnect is deduplicated;
- the next Kline performs one closed-candle rollover;
- exactly one candidate observation is audited, committed and projected;
- reconnect metrics increment without creating a duplicate candidate;
- stop closes the active fake socket cleanly.

Each asynchronous wait has a stage label, so a CI timeout identifies whether subscription, working-Kline delivery, reconnect, replay or projection failed.

The first reconnect run exposed a domain defect: the public pipeline supported 5m Klines while `TradeIdea.validityWindow` treated 5m as unsupported and expired the setup immediately. The fix gives 5m setups the same three-closed-candle validity policy used by the other realtime timeframes: 15 minutes. A separate domain regression verifies all five supported windows and candidate creation after a 5m candle closes.

## 100-symbol benchmark

The benchmark creates 100 deterministic symbols across all five supported Kline timeframes:

- 5m
- 15m
- 1h
- 4h
- 1D

This produces 500 bounded public subscriptions. The production planner must create exactly two shards under the 300-subscription limit. The test then sends one valid Kline for every stream through the production decoder and runtime.

Release-blocking assertions:

- all 500 subscriptions are present across the two subscribe payloads;
- exactly two shards become live;
- all 500 Klines are received and processed;
- no malformed-payload or critical-backpressure fault occurs;
- bounded p95 transport lag remains below one second;
- bounded p95 pipeline latency remains below one second;
- the complete fake-network dispatch finishes within ten seconds in CI;
- discovery health remains live after the batch.

The wall-clock limit is intentionally wider than the product latency target so shared CI runner variance does not create false failures. Product latency is asserted through the runtime timestamps and p95 metrics.

## Safety boundary

- The test uses the public Bitunix WebSocket endpoint contract only.
- No API key, secret, account payload, private client or order endpoint is available.
- The existing source-level authority regression remains active.
- Candidate mutation still requires durable audit before commit and projection.
- This slice does not enable foreground wiring, private exchange access or real-money execution.

## Validation tooling

The E2E and domain regression sources are formatted with Flutter `3.44.8` and Dart `3.12.2`. One-shot formatting or diagnostic workflows self-delete before CI and review, so no temporary workflow is part of the product diff.

## Remaining issue #101 work

After this slice, issue #101 still requires foreground application lifecycle wiring, a settings-derived production universe, production strategy/projection adapters and a user-facing health/latency dashboard.
