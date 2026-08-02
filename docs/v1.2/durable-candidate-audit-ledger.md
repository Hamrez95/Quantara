# Quantara v1.2 — Durable Candidate Audit Ledger

Related issues: #108, #112 and Epic #113.

## Purpose

Candidate lifecycle and registry events must survive normal app restarts, process death and an interrupted local write. This slice provides a bounded, versioned and integrity-checked local ledger for `CandidateRegistryAuditEvent` records.

The ledger contains market-analysis audit facts only. It never stores API credentials, signing material, withdrawal authority or raw private account payloads.

## Record identity

Each audit event is converted into a SHA-256 record identifier derived from:

- event, setup, symbol and timeframe identity;
- disposition;
- UTC observation timestamp;
- previous/current lifecycle stage;
- transition reason;
- optional gap sequences.

The local audit sequence is intentionally excluded from the identifier. A restarted process may restart its local counter, but replaying the same factual audit event remains idempotent.

## Integrity envelope

The encoded ledger has:

- schema version;
- monotonically increasing generation;
- ordered bounded records;
- SHA-256 checksum over the canonical JSON body.

Malformed, oversized, unsupported or checksum-mismatched data is rejected rather than partially trusted.

## Double-slot recovery

The durable store keeps two independent values:

- primary: newest committed generation;
- backup: the previously valid generation.

Append order is:

1. load the highest valid generation;
2. append and compact in memory;
3. write the current generation to backup;
4. write the next generation to primary.

If the primary write fails, the previous generation remains recoverable. On load, the highest valid generation is selected. This is crash-resilient local persistence, not a transactional database.

## Concurrency

Writes are serialized within one store instance. A failed append does not poison the queue; later writes may continue. The product composition must use one store instance per local ledger key pair.

## Capacity

The default limit is 2,000 records. When the bound is exceeded, the oldest records are compacted. The limit is configurable for tests and future product profiles.

Compaction is explicit and deterministic; the ledger never grows without bound.

## Integration contract

The registry remains synchronous and transport-independent. A coordinator must:

1. apply the reconciled observation to `RealtimeCandidateRegistry`;
2. append the returned audit event to `CandidateAuditStore`;
3. publish the resulting projection to the journal, diagnostics, Radar and notifications;
4. surface and retry persistence failure rather than silently claiming durable audit success.

This PR provides the durable store and codec. Wiring the store into the realtime coordinator and adding user-visible journal projections are the next slices.

## Platform adapter

`SharedPreferencesCandidateAuditKeyValueStore` is intentionally a tiny adapter. All recovery, checksum, idempotency, capacity and concurrency behavior is implemented above the plugin boundary and tested without platform mocks.
