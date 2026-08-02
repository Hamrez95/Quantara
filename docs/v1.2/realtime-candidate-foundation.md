# Quantara v1.2 — Realtime Candidate Foundation

Related issues: #101, #102, #103 and Epic #113.

## Purpose

This first vertical slice separates opportunity discovery from final signal execution. A setup may be detected early and observed continuously instead of being discarded until every confirmation is complete.

The lifecycle is:

```text
detected → forming → armed → triggered
                    ↘ missed
          ↘ expired / invalidated
```

`missed`, `expired` and `invalidated` are terminal. A terminal candidate cannot be resurrected by a delayed or duplicate event.

## Safety and coverage contract

- Broad discovery is allowed before all confirmation is present.
- A forming candidate is not an executable order.
- A trigger requires a closed-candle confirmation supplied by the owning playbook.
- Stale events may update diagnostics but cannot trigger a setup.
- Price beyond a playbook-specific chase limit becomes `missed`; the engine does not chase it.
- Structural invalidation or a breached protective boundary terminates the candidate.
- Score, entry distance, chase distance and event age are supplied through a playbook-specific policy rather than one global hard funnel.

## Time contract

All timestamps are UTC and monotonic:

- exchange event timestamp;
- local receive timestamp;
- candidate evaluation timestamp;
- trigger/resolution timestamp.

The evaluation result exposes event age and processing latency so #101 can enforce the product SLOs and #112 can audit late or dropped opportunities.

## Integration sequence

1. WebSocket/REST reconciliation converts exchange updates into `RealtimeMarketObservation`.
2. A playbook calculates quality, structure validity and closed-candle trigger confirmation.
3. `RealtimeCandidateEngine` performs the deterministic state transition.
4. The candidate repository publishes the transition to Radar, notifications and the journal.
5. Only a `triggered` candidate may enter the risk reservation and execution pipeline.

## Deliberate exclusions from this slice

- WebSocket transport and reconnect logic;
- persistent candidate repository;
- UI rendering and notifications;
- order placement or live execution;
- strategy probability calibration.

Those are implemented in dependent slices after this domain contract passes CI and review.
