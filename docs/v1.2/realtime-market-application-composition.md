# Realtime market application composition

This slice composes the public Bitunix transport, deterministic candle truth, bounded event delivery, strategy analysis, audited candidate coordination and derived projection without introducing private exchange or order authority.

## Runtime sequence

1. Restore the durable candidate projection.
2. Normalize and bound the active symbol/timeframe universe.
3. REST-bootstrap every stream with closed candles.
4. Build deterministic public Kline subscriptions only after bootstrap succeeds.
5. Start the sharded public WebSocket fleet.
6. Decode Kline events and feed the per-stream candle coordinator.
7. Reconcile exact gaps before candidate discovery resumes.
8. Deliver trusted updates through the bounded event bus.
9. Run analysis, register newly discovered candidates and coordinate observations.
10. Persist required audit events before candidate commit.
11. Update the projection only from successfully persisted audit events.

## Safety properties

- Public subscriptions are deduplicated, sorted and bounded.
- The default fleet retains the 300-subscription shard limit.
- No WebSocket subscription starts before REST bootstrap completes.
- Working updates may be analyzed, but trigger finality remains an analysis contract and must require a closed trigger candle.
- Gap, blocked-gap, out-of-order and duplicate updates cannot prepare new candidates.
- Critical event overflow remains explicit fail-closed backpressure.
- Candidate mutation still follows `prepare -> durable audit -> commit`.
- Audit failure prevents candidate commit and projection.
- Projection failure cannot mutate candidate truth and can be repaired from the durable audit ledger.
- Intentional pause/stop is distinct from unexpected fleet termination.
- The runtime accepts no credential, private endpoint, account payload or order-authority dependency.

## Lifecycle

`idle -> restoring -> bootstrapping -> connecting -> live`

Application pause stops the public fleet and moves to `paused`. Resume performs a fresh REST bootstrap before opening subscriptions again. Final stop drains the event bus and closes the runtime.

## Observability

The bounded health snapshot exposes:

- configured streams and active/live shards;
- public and Kline event counts;
- closed candle, gap and reconciliation counts;
- candidate evaluation and commit counts;
- reconnect, malformed payload and backpressure counts;
- bounded p95 transport and pipeline latency samples;
- last event and last fault diagnostics.

Historical faults remain visible, while a fully live shard fleet can recover to a healthy discovery state.

## Validation

Runtime and regression sources are formatted with Flutter `3.44.8` and Dart `3.12.2`; temporary formatter diagnostics are removed before CI and review.

## Remaining issue #101 work

- wire the runtime into the foreground app lifecycle and settings-derived universe;
- provide the production analysis gateway and durable Radar/Journal projection;
- add a fake WebSocket plus fake REST end-to-end transport test;
- add the 100-symbol benchmark and UI health/latency dashboard;
- preserve the existing periodic background scanner as a fallback rather than a source of realtime truth.
