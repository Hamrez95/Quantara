# Order State Machine

## States
- `Draft`: local proposal not submitted.
- `Submitted`: request accepted for exchange submission.
- `Acknowledged`: exchange accepted order creation, but fill is not confirmed.
- `PartiallyFilled`: one or more fills received.
- `Filled`: total order quantity filled.
- `CancelRequested`: cancellation submitted.
- `Cancelled`: cancellation confirmed.
- `Rejected`: exchange or risk rejection.
- `Expired`: time-in-force or decision expiration reached.
- `EmergencyClosing`: emergency close/reduce-only flow active.

## Rules
REST success never means filled. Fill state must be confirmed through exchange events and reconciliation. Client order IDs are idempotent. Stop loss and take profits are protective children of a position plan. If stop-loss placement fails for a live position, the configured emergency policy must run and emit an audit event.
