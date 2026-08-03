# Issue 143 — Configurable TP allocation and exchange-confirmed profit lock

## User behavior

- New Local Live configurations default to TP1/TP2/TP3 = 65% / 20% / 15%.
- The user can adjust each target in 5% steps while the editor keeps the total at exactly 100%.
- The selected allocation persists across app reconstruction.
- A managed position stores the exact allocation, rounded quantities and exchange target order IDs that were active when its protection ladder was created. Later preference changes do not rewrite the open position plan.

## Exchange-confirmed target progression

Remaining quantity is never sufficient evidence that TP1 or TP2 filled. Manual closes, liquidation, stale reads and exchange corrections can all reduce quantity.

A target is confirmed only when Bitunix trade history contains reduce-only fills whose:

- `positionId` resolves to the managed position;
- `orderId` equals that position's stored TP order ID;
- unique `tradeId` quantities reach the stored exchange-rounded target quantity.

Duplicate and out-of-order fills are idempotent by `tradeId`. Partial target fills remain partial and do not promote the stop.

## Stop promotion

After exchange-confirmed TP1:

- LONG stop is proposed above entry by the configured cost buffer and rounded toward profit;
- SHORT stop is proposed below entry by the configured cost buffer and rounded toward profit;
- an already safer stop is retained unchanged.

After exchange-confirmed TP2, the runner stop is proposed at TP1, again only if that improves protection.

The pending promotion intent is persisted before mutation. Exactly one modify request is sent. Quantara then performs bounded read-after-write checks against position TP/SL truth. A timeout or ambiguous response never causes a blind retry. New entries remain blocked while confirmation is pending, but the last exchange-confirmed stop remains authoritative.

## Automated regressions

Focused tests cover:

- 65/20/15 default and 70/20/10 JSON round-trip;
- positive tranches totaling exactly 100%;
- deterministic precision rounding without over-allocation;
- preference persistence and editor RTL/LTR behavior;
- immutable per-position order IDs and quantities;
- TP1/TP2 confirmation by matching exchange order/trade identity;
- duplicate, out-of-order and partial fills;
- quantity-only false positives;
- LONG/SHORT cost-aware stop calculation;
- never weakening an already better stop;
- one mutation with bounded read-back confirmation;
- ambiguous mutation response and restart-safe pending state;
- source-level protection against duplicate mutation loops.

Focused format, strict analyzer and safety tests passed on implementation head `8749e05ddc4d8e8e80a37213fa8a36f7de4f8d43`. The legacy source guard was upgraded to reject the removed quantity-ratio heuristic and require exchange fill identity; its formatted clean head is `fe0bc0f6e3954847954d033a0cd6b8338cc2ad2b`.

## Physical Samsung checklist — external gate

Do not open a new position for this checklist. Do not modify the user's current/previous exchange SL/TP manually.

1. With Local Live stopped and no managed position, open the settings panel and confirm 65/20/15 is displayed.
2. Change to 70/20/10, leave/reopen the page and restart the app; confirm the same values remain.
3. Confirm invalid totals cannot be created by the controls.
4. Confirm the UI explains that changes apply to future positions and do not rewrite an existing position plan.
5. Using fixture/demo data only, confirm a partial TP1 fill does not show Risk Free.
6. Confirm quantity reduction without a matching TP order ID does not show Risk Free.
7. Confirm a complete matching TP1 fill produces one pending/confirmed risk-free timeline event.
8. Confirm offline/timeout state shows pending confirmation and does not issue another mutation.
9. Confirm all screenshots/logs omit API secrets.

Real entries remain disabled by the Phase 1 gate. `main` and Draft Release PR #131 remain untouched.
