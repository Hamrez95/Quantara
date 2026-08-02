# Quantara v1.2 — Realtime Candidate Event Registry

Related issues: #101, #102, #108, #112 and Epic #113.

## Responsibility

The registry sits between reconciled market/playbook observations and the deterministic candidate lifecycle engine.

It owns:

- candidate identity and capacity;
- candidate-scoped event deduplication;
- optional sequence continuity and gap detection;
- timestamp ordering when the upstream adapter has no sequence;
- deterministic lifecycle updates;
- a monotonic audit event for every accepted or rejected delivery.

It does not own WebSocket sockets, REST backfill, playbook calculations, persistence, notifications, orders or risk reservations.

## Delivery contract

An adapter produces a `RealtimeObservationEnvelope` with:

- non-empty event and setup identifiers;
- exact symbol and timeframe identity;
- optional non-negative candidate-delivery sequence;
- validated UTC exchange, receive and evaluation timestamps;
- the playbook observation consumed by `RealtimeCandidateEngine`.

The registry returns one disposition:

- `accepted`;
- `duplicate`;
- `outOfOrder`;
- `gapDetected`;
- `unknownCandidate`;
- `identityMismatch`.

A gap never advances the cursor or mutates the candidate. The upstream coordinator must backfill/replay the missing observations and call `markReconciled` before normal delivery resumes.

## Audit contract

Every delivery receives a monotonic local audit sequence and records:

- event/setup/stream identity;
- disposition;
- observation evaluation time;
- previous and current candidate stage;
- lifecycle transition reason when accepted;
- expected and observed sequence when a gap is detected.

This audit result is returned to the caller. Durable storage and journal projection are implemented in the next persistence slice rather than hidden inside the in-memory registry.

## Capacity and memory

The default registry accepts up to 2,000 candidate identities and remembers the most recent 4,096 accepted event IDs. Capacity is explicit and fail-closed: active candidate truth is not silently evicted.

The recent-event window is bounded so a long-running scanner cannot grow memory indefinitely. Raw WebSocket deduplication and exchange sequence reconciliation remain an upstream responsibility; the registry protects candidate deliveries after fan-out.

## Next integration

1. Official exchange adapters reconcile raw WebSocket and REST data.
2. Playbooks produce candidate-scoped observations.
3. The registry rejects duplicates, ordering faults and gaps.
4. Accepted updates are persisted as journal/audit events.
5. Radar and notifications consume projections rather than owning trading logic.
