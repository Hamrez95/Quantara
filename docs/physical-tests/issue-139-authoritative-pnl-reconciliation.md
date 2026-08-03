# Issue 139 — Authoritative PnL reconciliation

## Projection contract

Quantara now carries one structured exchange accounting projection instead of treating Local Live `realizedPnl` as an ambiguous scalar.

Every metric carries:

- value or explicit unavailable state;
- source;
- account, position or session scope;
- currency;
- `asOf` timestamp;
- confirmed, stale, unavailable or unverified state.

The projection separates:

- open-position unrealized PnL;
- exchange-confirmed realized gross PnL;
- fees;
- signed funding;
- net realized PnL;
- Local Live session PnL filtered to the session's owned position IDs.

Account, position UI and Local Live notification consume this same projection. The future append-only Journal will persist the same exchange event IDs.

## Exchange reconciliation

- Trade-history rows are idempotent by Bitunix `tradeId`.
- Conflicting duplicate exchange IDs make the projection unverified.
- Closed-position history supplies position scope, funding and time bounds.
- Trade rows without a position ID are attached only when symbol and position time bounds resolve to one unambiguous position.
- A failed funding-history read leaves confirmed realized gross and fees visible, but funding and net remain unavailable and the projection is not ready for risk gates.
- Missing or stale values are never converted to zero.

## Physical XRP regression fixture

The fixture models the observed sequence:

1. `XRPUSDT` short entry fills for quantity `21.4`.
2. TP1 fills quantity `13.91` and realizes `+0.100 USDT` gross.
3. The remaining `7.49` later closes at stop and realizes `-0.050 USDT` gross.
4. Total fee is `0.017 USDT`.
5. Funding is `-0.002 USDT`.
6. Final net realized PnL is `+0.031 USDT`.

The duplicate TP1 row in the fixture is reconciled once. The stop affects only the remaining quantity; it does not erase the already-realized TP1 result.

## Automated focused gate

On implementation commit `03eafe741e2e5af162e871308b0f01c7a46db3a4`:

- `flutter analyze --fatal-infos` passed;
- projection, Bitunix history mapping, TP/SL reconciliation, account-cycle, Local Live model, stale-state and source-safety tests passed;
- all temporary source-transfer workflows and payloads were removed from the final diff.

## Phase 1 quarantine

`ExchangeTruthPhaseOneGate.realEntriesAllowed` remains false. PnL history that is unavailable, stale or unverified blocks new entries but does not stop management of an already-confirmed position.

## Samsung read-only checklist — External Gate

Do not create a new position for this checklist and do not cancel, move, resize, replace or weaken any current SL/TP.

1. Open Account and confirm one shared `asOf` timestamp for Unrealized, Realized Gross, Fee, Funding and Net.
2. Confirm unavailable components display `Unavailable` rather than `0.00`.
3. Confirm a stale account displays its stale timestamp and blocks new entries.
4. Open an existing/recent position and confirm its exchange fill IDs are not duplicated after manual refresh, app resume or process restart.
5. For a TP1-then-stop trade, confirm TP1 and the remaining stop appear as separate realized components and final net includes all fees and funding.
6. Confirm Local Live notification and Account UI show the same session/account projection and timestamp.
7. Confirm no action in this checklist changes exchange protection orders.

`main` and Draft Release PR #131 remain untouched.
