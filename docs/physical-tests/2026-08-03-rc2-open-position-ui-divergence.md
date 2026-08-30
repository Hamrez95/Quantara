# RC2 physical finding: Local Live position/account UI divergence

Observed on Samsung physical test, 2026-08-03 around 14:56–14:57 +03:30.

## Exchange truth

- Bitunix showed one open `XRPUSDT` short position.
- Isolated margin, 10x leverage.
- Entry approximately `1.0665`, size approximately `22.8038 USDT`, margin approximately `2.2974 USDT`.
- One stop and three staged take-profit protections were visible; Bitunix showed four open orders.

## Quantara state divergence

- Foreground-service notification correctly showed `1 open`.
- Account summary and the Open Positions/Open Orders cards still showed zero positions and zero orders.
- The displayed private-account snapshot was last synchronized at `2026-08-03 14:25:11`, over thirty minutes before the screenshots.

## Root cause confirmed in RC2 source

`LocalLiveTradeController` receives foreground task status independently. `AutoTradeController` owns a separate `AutoTradeAccountSnapshot` and refreshes only during initialize/connect/manual refresh. A confirmed Local Live fill does not trigger `AutoTradeController.refresh()`, and there is no bounded account polling while Local Live is active.

## Safety impact

- UI can claim no position/order while exchange and Local Live have an active protected position.
- A stale account summary can mislead the operator during emergency review.
- Restart/rearm decisions must not rely on the stale view.
- Realized-PnL values shown by notification and exchange also require reconciliation and unit/fee attribution.

## Required fix

- Single authoritative private-account snapshot stream shared by Local Live status and account cards.
- Immediate post-entry/post-protection refresh.
- Bounded polling while the local service is active and refresh on app resume.
- Explicit stale timestamp/banner and fail-closed entry behavior when private state is stale or divergent.
- Display positions and pending protections from the same reconciliation cycle.
- Regression for one filled position with one SL and three TP orders.
- Never auto-arm or expand order authority as part of synchronization.
