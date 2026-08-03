# Issue 135 — Bitunix position TP/SL reconciliation

## Read-only exchange boundary

The private account projection reads regular pending orders from `/api/v1/futures/trade/get_pending_orders` and Position TP/SL rows independently from `/api/v1/futures/tpsl/get_pending_orders`. The TP/SL request is scoped by the open position's exchange `positionId` and symbol. Optional integer `side` and `positionMode` filters are intentionally omitted because the local position model carries their string forms. No placement, cancellation, replacement, or modification endpoint is part of this projection.

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

## Focused automated gate

On formatted implementation head `6deac3a4d97fc77b27c48980e54a606f79b6ce5d`, strict analyzer and the focused API, reconciliation, widget, stale-state, and source-safety test set passed. The source-safety test confirms the private client contains only the read-only TP/SL pending-order path and no TP/SL placement, cancellation, or modification path.

The Bitunix query-shape review fix passed strict analyzer and focused protection tests on `dfd8e78c423552a393d9aec0eada21b9438c84f8`. The final request uses only the documented string filters `positionId` and `symbol`, plus pagination, and omits optional integer `side` and `positionMode` filters.

## External gate

Only after all automated gates pass, execute the read-only Samsung checklist on Issue #135 and Epic #140. The checklist must not create an entry or cancel, move, resize, weaken, or replace any existing position, stop, or take-profit order.
