# Persistence and Audit

Quantara persists safety-critical state in PostgreSQL through Entity Framework Core and the Npgsql provider. Persistence is designed around restart recovery, idempotency, optimistic concurrency, and append-only audit evidence.

## Stored records

### Orders

The `orders` table stores:

- stable order identifier;
- current domain state;
- monotonic version used as an optimistic concurrency token;
- creation and update timestamps.

### Order lifecycle events

The `order_events` table stores every new lifecycle event identifier, including invalid transition attempts. Each record contains:

- target state;
- application result;
- previous and resulting states;
- exchange or application occurrence time;
- persisted reason and timestamp.

Event identifiers are globally unique. Replaying an existing identifier returns an idempotent duplicate result rather than mutating order state again.

Only successfully applied event identifiers are used when rehydrating the in-memory aggregate. Persisted invalid attempts remain auditable and duplicate-safe without becoming valid domain history.

### Risk evaluations

The `risk_evaluations` table stores an immutable JSON envelope containing the proposal identifier and complete structured `RiskEvaluationResult`.

The SHA-256 hash covers both the proposal identifier and the complete result. Reusing an evaluation identifier with the same hash is an idempotent duplicate; reusing it with different content is a conflicting duplicate.

### Audit events

Every order creation, lifecycle event attempt, and risk-evaluation append creates an audit event in the same `SaveChanges` transaction as the domain change.

Audit records include:

- monotonic database sequence;
- globally unique event identifier;
- aggregate type and identifier;
- event type;
- JSON payload;
- occurrence timestamp.

## Append-only enforcement

Audit immutability is enforced twice:

1. `QuantaraDbContext` rejects tracked audit entities in `Modified` or `Deleted` state.
2. PostgreSQL installs a `BEFORE UPDATE OR DELETE` trigger on `audit_events` that raises an exception even for direct SQL.

Application-layer protection is not treated as a substitute for database enforcement.

## Atomicity

EF Core `SaveChanges` wraps order state changes, lifecycle-event insertion, and audit insertion in one transaction. A unique-key, concurrency, or database failure rolls back the entire operation.

The same rule applies when appending a risk evaluation and its audit evidence.

## Optimistic concurrency

`orders.version` is an EF Core concurrency token. Callers supply the version they previously observed.

- Matching version: the event may be evaluated and persisted.
- Stale version before persistence: return `ConcurrencyConflict` without writing an event.
- Race detected during `SaveChanges`: roll back, reload authoritative state/version, and return `ConcurrencyConflict`.

Clients must reload and reconsider the next action; the store never guesses or silently overwrites newer state.

## Restart recovery

A fresh process loads the persisted order state, version, and successfully applied event identifiers. These values rehydrate `OrderAggregate`, preserving transition validation and duplicate-event behavior after restart.

## Migration

The initial migration creates:

- `orders`;
- `order_events`;
- `risk_evaluations`;
- `audit_events`;
- required keys and indexes;
- PostgreSQL audit immutability trigger.

The migration is applied in integration tests against a real `postgres:16-alpine` Testcontainer.

## Current limitations

This slice does not yet persist fills, positions, balances, funding, PnL, paper-account snapshots, or exchange reconciliation state. It also does not expose persistence directly to a public API. Those capabilities build on these durability guarantees in later slices.
