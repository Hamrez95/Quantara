# Trusted realtime analysis context

Realtime strategy analysis must not reconstruct market state from a single transport event. The production runtime now owns one candle assembler and passes a read-only `RealtimeCandleAnalysisContext` to every analysis gateway call.

## Context contents

- original pipeline update and disposition;
- full immutable closed-candle history for the stream;
- current mutable working-candle snapshot;
- event-only closed-candle delta for rollover or reconciliation diagnostics;
- exchange, receive and process timestamps;
- trusted-state and closed-analysis flags.

## Invariants

The context is constructed only after the candle pipeline has applied the event. Construction fails closed when:

- the event and snapshot use different symbol/timeframe keys;
- the snapshot working candle does not match the event working candle;
- the event or snapshot is in gap-blocked/untrusted state.

The closed history comes from `RealtimeCandleStreamSnapshot`, which exposes an unmodifiable list. Strategy and UI code can observe market truth but cannot mutate the pipeline.

## Runtime sequence

`Public event -> Candle assembler -> Pipeline update -> Bounded event bus -> Trusted full snapshot -> Analysis gateway`

Gap detection and out-of-order events remain visible to metrics but do not enter candidate analysis. Reconciliation must complete first; the subsequent trusted context contains the repaired full history.

## Regression coverage

- full history is available when an event contains no closed-candle delta;
- event delta remains separately observable;
- closed history is immutable;
- a different stream key is rejected;
- gap/untrusted state is rejected before analysis;
- existing runtime and fake-WebSocket E2E tests use the upgraded gateway contract.

## Remaining issue #101 work

- implement the production multi-timeframe analysis adapter;
- derive the active universe from saved symbols and timeframe settings;
- wire runtime start/pause/resume/stop to the foreground application lifecycle;
- consume durable audit into Radar and Journal projections;
- expose bounded health and latency diagnostics in the UI.
