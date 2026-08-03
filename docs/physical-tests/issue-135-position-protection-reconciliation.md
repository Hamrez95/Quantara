# Issue 135 — Bitunix position TP/SL reconciliation

## Read-only exchange boundary

The private account projection reads regular pending orders from `/api/v1/futures/trade/get_pending_orders` and Position TP/SL rows independently from `/api/v1/futures/tpsl/get_pending_orders`. The TP/SL request is scoped by the open position's exchange `positionId`, symbol, and position mode. No placement, cancellation, replacement, or modification endpoint is part of this projection.

## Reconciliation model

- Regular and protection feeds remain visible separately.
- Exchange IDs are used to calculate one deduplicated pending-order total.
- Each open position receives one protection projection with an `as of` timestamp.
- A verified full-quantity stop and three quantity-complete partial take-profits produce `Fully protected`.
- Missing or insufficient stop coverage produces `Missing stop`.
- Missing targets, fewer than three targets, quantity gaps, or over-allocation produce `Incomplete ladder`.
- A failed, malformed, mismatched, or ambiguous Position TP/SL response produces `Unverified` without replacing the rest of the account snapshot with zeroes.
- When the authoritative account snapshot is stale, the UI displays `Stale` while preserving the last verified SL/TP details.
- TP quantity total, residual quantity, and residual dust are displayed per position.

## Physical reference fixture

The automated fixture represents `XRPUSDT` short, isolated, 10x, quantity `21.4`, entry `1.0665`, stop `1.0691`, and take-profits `1.0603`, `1.0567`, and `1.0531`. The four protection rows total exactly `21.4` TP quantity and produce zero residual.

## External gate

Only after all automated gates pass, execute the read-only Samsung checklist on Issue #135 and Epic #140. The checklist must not create an entry or cancel, move, resize, weaken, or replace any existing position, stop, or take-profit order.
