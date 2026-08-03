# Realtime analysis context

The realtime runtime synchronizes every candle-pipeline event into a bounded, read-only per-stream snapshot before candidate preparation.

## Contract

- REST bootstrap establishes at least 20 contiguous closed candles.
- Working updates mutate only the working snapshot.
- Rollover and reconciliation append closed candles with a bounded retention limit.
- Gap or blocked-by-gap state is fail-closed for discovery.
- Strategy analysis receives immutable full history plus the original event delta and separate exchange, receive and process timestamps.
- The decorator implements the existing analysis gateway, so the public runtime remains isolated from private exchange and order authority.

## Remaining issue #101 work

Production strategy/projection adapters, settings-derived foreground lifecycle wiring and the health/latency dashboard remain separate reviewable slices.
