# Issue 134 — Authoritative private-account reconciliation

## Automated implementation boundary

- `AutoTradeController` is the only owner of the current Bitunix private-account projection.
- Local Live status observations are compared with that projection and trigger an immediate read-only reconciliation when they diverge.
- A bounded 20-second poll runs only while Local Live is active.
- Account-page open and application resume request an immediate reconciliation.
- A failed refresh preserves the last confirmed snapshot and marks it stale instead of replacing positions or balances with zeroes.
- Stale, unavailable, or divergent state blocks new entries while management of an already confirmed position remains available.
- The projection carries one reconciliation cycle ID and completion timestamp for all account-card consumers.

## Phase 1 trading quarantine

`ExchangeTruthPhaseOneGate.realEntriesAllowed` remains `false`. Starting Local Live with no existing exchange position is rejected. An existing position can only resume in management-only mode; synchronization does not place, modify, cancel, move, weaken, or remove any order.

## Automated fixtures

The regression fixture represents one `XRPUSDT` isolated short position, 10x leverage, quantity `21.4`, entry `1.0665`, margin `2.30 USDT`, and unrealized PnL `0.0021 USDT`. Tests cover stale-state fail-closed behavior, Local Live/account divergence, failed-refresh last-known-state preservation, page warning UI, and source-level observer-only safety.

## External physical gate

After all CI gates pass, execute the Samsung reconciliation checklist recorded on Issue #134 and Epic #140. No physical test may create a new entry or alter the user's current SL/TP protections.
