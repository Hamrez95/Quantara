# Quantara v1.2 — Audited Candidate Coordinator

Related issues: #101, #108, #112 and Epic #113.

## Problem

A realtime registry that mutates candidate state before durable audit storage creates a failure window:

1. event advances candidate/cursor/dedup state;
2. audit write fails;
3. replay is rejected as duplicate or out-of-order;
4. durable journal truth is permanently incomplete.

The coordinator and two-phase registry contract close that window.

## Processing order

For every candidate-scoped observation:

1. `RealtimeCandidateRegistry.prepare` validates identity, deduplication, ordering, gap and lifecycle rules without changing registry state;
2. retention policy classifies the audit event as `persist`, `aggregate` or `skip`;
3. durable events are appended to `CandidateAuditStore`;
4. only after successful persistence does `registry.commit` advance candidate, cursor and dedup state;
5. the committed update becomes publishable to journal projections, Radar and notifications.

If durable storage fails, the prepared update is not committed. Replaying the same upstream envelope is safe because candidate state, cursor and dedup memory did not advance, while the audit store itself is idempotent.

## Registry transaction contract

A prepared accepted update captures the registry revision. Commit succeeds only when:

- the prepared update belongs to the same registry;
- no candidate registration, reconciliation or accepted commit changed the registry revision;
- the prepared update contains complete candidate/cursor/dedup state.

Rejected observations require no commit because they do not mutate registry truth. The existing `apply` method remains as a prepare-plus-commit convenience for tests and non-durable callers.

The production composition must treat the registry as coordinator-owned. A commit conflict is a programming or ownership fault, is never publishable and must stop that processing path for reconciliation.

## Persistence decisions

- lifecycle transitions and important stale/order/gap/identity faults are persisted before publication;
- accepted ticks without durable state change are committed without snapshot I/O;
- duplicate noise is aggregated through a metric sink;
- metric failure is surfaced diagnostically but does not turn a duplicate delivery into a trading-state mutation.

## Concurrency

Coordinator operations are serialized. Concurrent envelopes are processed in submission order so candidate sequence continuity remains deterministic. A failed operation does not poison later coordinator work.

## Publication contract

`CandidateCoordinationResult.publishable` is true only for an accepted update that was successfully committed. Callers must not notify, project or hand a candidate to future risk/execution code when the result is rejected, durability-failed or commit-conflicted.

## Boundaries

This slice does not add:

- exchange WebSocket transport or REST backfill;
- user-visible journal/Radar projections;
- position sizing, risk reservation or order execution;
- persistent restoration of full candidate state.

It provides the consistency boundary those later slices consume.
