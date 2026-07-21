# Order State Machine

Quantara models order execution as an explicit state machine. A successful REST submission is never treated as a confirmed fill. Exchange events and reconciliation must move the aggregate through valid states.

## States

- `Created`: local order aggregate exists but has not passed risk evaluation.
- `RiskRejected`: deterministic risk evaluation rejected the proposal.
- `RiskApproved`: deterministic risk evaluation approved the proposal.
- `SubmissionPending`: durable submission intent was created.
- `Submitted`: the request was sent to the exchange boundary.
- `Acknowledged`: the exchange accepted creation, but no fill is assumed.
- `PartiallyFilled`: one or more executions were confirmed.
- `Filled`: the complete order quantity was confirmed filled.
- `CancellationPending`: a cancellation request was sent.
- `Cancelled`: cancellation was confirmed.
- `Rejected`: the exchange or reconciliation process confirmed rejection.
- `Expired`: the proposal or order expired.
- `ReconciliationRequired`: local and remote state cannot yet be resolved safely.
- `Failed`: an operational failure occurred and may require reconciliation.

## Transition rules

Valid transitions are encoded in `OrderStateMachine`; callers cannot assign state directly. Invalid transitions return a structured failure and leave state unchanged.

Terminal states are:

- `RiskRejected`
- `Filled`
- `Cancelled`
- `Rejected`
- `Expired`

A `Failed` order is not terminal because reconciliation may recover authoritative exchange state.

## Idempotency

Every lifecycle event has a required event identifier. Once an event identifier is successfully applied, replaying it returns `DuplicateIgnored` and does not mutate the aggregate. This protects the domain model from duplicated WebSocket messages, retries, and restart replay.

Invalid events are not silently accepted. They return `InvalidTransition` and must be written to the append-only audit stream by the persistence/application layer.

## Execution invariants

- REST success does not mean filled.
- Partial fills remain explicit.
- Cancellation can race with additional fills, so `CancellationPending` may transition to `PartiallyFilled` or `Filled`.
- Ambiguous failures move to `ReconciliationRequired` instead of guessing.
- Client order IDs and exchange event IDs must be idempotent.
- Protection-order failure for a live position must invoke a separately tested emergency policy.

Persistence, audit storage, exchange reconciliation, and restart recovery are follow-up slices built on this domain state machine.
