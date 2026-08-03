# Realtime analysis context

The realtime runtime synchronizes every candle-pipeline event into a bounded, read-only per-stream snapshot before candidate preparation.

## Contract

- REST bootstrap establishes at least 20 contiguous closed candles.
- Working updates mutate only the working snapshot.
- Rollover and reconciliation append closed candles with a bounded retention limit.
- Gap or blocked-by-gap state is fail-closed for discovery.
- Strategy analysis receives immutable full history plus the original event delta and separate exchange, receive and process timestamps.
- The decorator implements the existing analysis gateway, so the public runtime remains isolated from private exchange and order authority.
- Runtime synchronization uses an explicit interface cast so Dart 3.12 resolves the optional capability without weakening the base gateway contract.
- Canonical Flutter 3.44.8 and Dart 3.12.2 formatting, analyzer, tests and platform builds are the merge gate for this slice.

## Remaining issue #101 work

Production strategy/projection adapters, settings-derived foreground lifecycle wiring and the health/latency dashboard remain separate reviewable slices.
