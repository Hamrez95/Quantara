# Realtime production wiring

Quantara now composes the public Bitunix WebSocket, REST candle bootstrap/reconciliation, bounded analysis snapshots, audited candidate coordination and durable Journal projection at the application boundary.

## Runtime boundary

- The settings-derived foreground universe is capped at 12 symbols across 5m, 15m, 1h and 4h: at most 48 public streams.
- Strategy analysis uses only trusted closed history; a working candle can prepare or update a candidate but cannot confirm a trigger.
- Candidate mutation still follows prepare, durable audit, commit and projection.
- Candidate audit uses primary and backup SharedPreferences ledgers.
- Journal projection survives restart through the existing OpportunityStateStore.
- Pause/resume is owned by QuantaraApp, outside the page that owns private Auto Trade controllers.
- The health strip exposes stream/shard state, p95 transport and processing latency, reconnect/fault state and the foreground-only RC limitation.
- Canonical Flutter 3.44.8 / Dart 3.12.2 formatting, strict analysis, full tests and all platform gates are required before merge.
- The final validation run starts from a clean six-file product diff with no temporary workflow.

## Safety boundary

No private exchange client, credential store, account state or order authority is imported by the production realtime runtime. This RC does not promise background monitoring after the app or browser tab is closed.
