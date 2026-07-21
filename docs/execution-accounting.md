# Execution Accounting Kernel

Quantara uses one deterministic accounting kernel for future backtesting, paper trading, shadow trading, and exchange reconciliation. The kernel uses `decimal` only and has no network, database, clock, or AI dependency.

## Separation of responsibilities

### Order fill accounting

`OrderFillAggregate` owns execution progress for one order:

- requested quantity;
- filled and remaining quantity;
- weighted average fill price;
- accumulated execution fees;
- unfilled, partially filled, and filled status;
- identical versus conflicting fill replay detection.

A fill is rejected without mutation when it belongs to another order, symbol, or side, or when it would overfill the requested quantity.

### Position accounting

`PositionAccountingAggregate` owns one symbol position:

- signed and absolute quantity;
- long, short, or flat direction;
- weighted average entry price;
- contract multiplier;
- gross realized PnL;
- fees paid;
- net funding credits or debits;
- net realized and marked unrealized PnL;
- identical versus conflicting fill and funding replay detection.

Order lifecycle state and position accounting are intentionally separate. A later application transaction will atomically apply a confirmed fill to both aggregates and persist their resulting events.

## PnL formulas

For an open long position:

`unrealized = (mark - average entry) × quantity × contract multiplier`

For an open short position, signed quantity makes the same formula valid:

`unrealized = (mark - average entry) × signed quantity × contract multiplier`

Gross realized PnL is calculated only for the quantity closed by an opposing fill. A reversal first realizes the closed quantity and opens the remaining quantity in the new direction at the reversal fill price.

`net realized = gross realized - fees paid + funding net`

`net PnL = net realized + unrealized`

Fees, funding, gross PnL, and net PnL remain separate so reconciliation can identify the source of a difference instead of hiding it inside one combined number.

## Reduce-only invariant

A reduce-only fill is accepted only when it:

- acts against an existing non-zero position;
- does not increase the current position;
- does not cross through zero and reverse direction.

It can close the position exactly or reduce it partially. It cannot open a flat position.

## Idempotency

Fill and funding identifiers are unique within their event type.

- Replaying an identical normalized payload returns `DuplicateIgnored`.
- Reusing an identifier with different content returns `ConflictingDuplicate`.
- Rejected events do not enter processed-event history.

Occurrence timestamps are normalized to UTC before comparison, so the same instant represented with a different offset remains an identical replay.

## Rehydration integrity

Both aggregates can be rehydrated from an expected snapshot plus the ordered history of applied events. Rehydration replays the history through the normal domain rules and fails when the resulting snapshot does not exactly reconcile with the persisted snapshot.

This provides a corruption detector for the later PostgreSQL implementation rather than blindly trusting denormalized state.

## Current limitations

This slice does not yet:

- reserve or release account margin;
- mutate wallet balances;
- calculate liquidation prices;
- match market, limit, stop, or take-profit orders;
- model spread, slippage, liquidity, or latency;
- persist fills, positions, or account snapshots;
- submit any real or paper exchange order.

Those capabilities will be layered on this shared accounting kernel. Live trading remains unavailable.

