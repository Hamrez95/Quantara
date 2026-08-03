# Quantara v1.2 — Realtime Candle Event Pipeline

Related issues: #101, #102, #108, #112 and Epic #113.

## Purpose

Public Kline updates are mutable working snapshots. Quantara must not treat an in-progress Kline as a closed candle or run full closed-candle analysis on every WebSocket message.

This slice establishes the data path between validated public market events and future candidate analysis:

`REST bootstrap → working Kline updates → deterministic rollover → gap block → exact REST reconciliation → bounded incremental event bus`

It contains no private exchange access or order authority.

## Bootstrap

Every symbol/timeframe stream must load at least 20 strictly contiguous closed candles before accepting WebSocket Kline updates. The default product bootstrap may retain up to 500 closed candles per stream.

The REST source:

- uses the public `/api/v1/futures/market/kline` endpoint;
- requires HTTPS without embedded credentials, query tokens or fragments;
- observes the official ten-request-per-second IP limit with at least 100 ms pacing;
- paginates at the official 200-candle page limit;
- rejects oversized, malformed, unsuccessful or invalid-OHLC responses;
- excludes the currently open candle from recent-history bootstrap;
- validates exact `[from, to)` boundaries for reconciliation.

## Working and closed candles

A WebSocket Kline with the expected next open time becomes the working candle. Further updates for the same open time replace only that working snapshot.

A candle becomes closed only when a valid Kline for the immediately following interval arrives. That rollover closes the previous working candle exactly once. A working update may prepare or update a candidate; rollover is the event that requests full closed-candle analysis.

Exact repeated snapshots are classified as duplicates. Older Klines are classified as out-of-order and never become candidate inputs.

## Gap handling

When an observed Kline skips one or more expected intervals:

1. the stream records an explicit UTC gap;
2. the observed Kline is held as pending working state;
3. the stream becomes untrusted for new candidate preparation;
4. a critical gap event is published before reconciliation;
5. REST must return the exact contiguous missing closed range;
6. only after exact validation is the pending Kline installed as working state.

A failed or partial backfill leaves the stream blocked. The next event retries reconciliation before applying fresh market data. Open-position management remains a separate path and must not be disabled merely because new-entry discovery is blocked.

The reconciled event preserves the original exchange and receive timestamps of the Kline that exposed the gap; REST processing time is stored separately.

## Incremental event bus

The event bus serializes events per symbol/timeframe while allowing independent streams to progress concurrently.

It uses bounded queues:

- working updates may be coalesced to the latest queued snapshot;
- bootstrap, closed-candle, reconciliation, gap and ordering events are critical and never silently dropped;
- critical capacity exhaustion fails closed with an explicit backpressure error;
- handler failure is isolated and does not poison later events;
- active-stream capacity is bounded.

This prevents a slow symbol from blocking the market universe and prevents high-frequency working updates from creating unbounded memory growth.

## Analysis contract

Downstream analysis must follow these rules:

- working update: incremental indicators and candidate preparation only;
- duplicate: optional metrics, no full rescan;
- closed candle: full strategy and candidate scan;
- gap/blocked/out-of-order: no new candidate preparation;
- reconciled: full analysis against corrected closed history;
- all decisions preserve exchange, receive and process UTC timestamps.

## Boundaries

This slice does not yet:

- subscribe the transport fleet in application composition;
- map candle updates into strategy-engine feature vectors;
- publish user-visible Radar, journal or notification projections;
- execute or modify an exchange order.

Those are subsequent slices consuming this tested candle truth layer.
