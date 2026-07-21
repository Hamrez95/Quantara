# Deterministic Cost-Aware Backtest Runner

The Quantara runner executes train, validation, and test experiments against the immutable manifests introduced in Milestone 3 slice 1. It deliberately refuses final holdout execution; holdout requires a separate authorization and immutable-publication path.

## No-look-ahead timeline

For each evaluation candle:

1. A target scheduled by an earlier close may fill at the current candle open.
2. Funding points inside the candle interval are applied using the candle open as a deterministic non-future reference price.
3. The position is marked at candle close and an equity point is recorded.
4. Only then does the strategy receive the current closed candle and the read-only prefix of all candles up to that close.
5. The new target cannot execute before a later candle open.

`LatencyBars = 1` means a decision made at one candle close is first eligible at the next candle open. The context uses a fixed-count prefix view over the source candles. It does not copy the full history on every bar and cannot expose candles added after the context was created.

## Target-position interface

A strategy returns a signed target quantity:

- positive: long target;
- negative: short target;
- zero: flat target.

The runner computes the difference between the target and the actual position. A later decision replaces the unfilled target remainder. This supports partial fills, position increases, reductions, closes, and reversals without maintaining a separate PnL implementation.

Targets are normalized toward zero using the configured quantity step and minimum order quantity. Decisions exceeding the absolute target limit or gross-leverage limit are rejected without a fill.

## Execution costs

The immutable cost model contains:

- half spread in basis points;
- base slippage in basis points;
- additional impact at maximum allowed participation;
- taker fee in basis points;
- maximum fraction of candle volume available to the strategy;
- candle-boundary latency.

For each eligible bar:

`maximum fill = candle volume × maximum participation`

The fill is rounded down to the quantity step. Impact scales linearly with utilization of that maximum fill. Buy prices move upward and sell prices move downward by spread plus slippage. Fees use executed notional and the execution-accounting contract multiplier.

A target too large for one candle remains pending and can fill across later candles. Zero or sub-minimum liquidity creates no synthetic fill.

## Funding

A funding point in `[candle open, next candle open)` applies to the position held after any fill at that candle open. The reference price is the candle open, so funding never reads a future close. For signed quantity `q`:

`funding net = -q × open price × contract multiplier × funding rate`

Positive funding rates debit longs and credit shorts. Funding, fees, gross realized PnL, net realized PnL, and unrealized PnL remain separated by the shared execution-accounting kernel.

## Determinism

A completed run is bound to:

- runner version;
- experiment fingerprint;
- exact cost-model fingerprint;
- starting equity;
- contract multiplier;
- quantity rules;
- leverage and target limits.

The strategy receives a stable versioned pseudo-random generator seeded from the experiment manifest. Identical code, manifest, costs, rules, and seed produce identical decisions, event identifiers, fills, funding records, and equity curves.

## Dataset verification

Before evaluating the strategy, the runner rebuilds the candle/funding content and provenance hashes and compares them with the immutable dataset manifest. Altered data is rejected before strategy code executes.

## Holdout safety

The generic runner rejects `ExperimentStage.Holdout`. A backtest caller cannot bypass the holdout ledger by directly changing the stage at runtime. A later publication orchestrator will require a valid holdout receipt, persist the exact output, and consume the scope atomically.

## Current limitations

This slice does not yet:

- calculate performance metrics or uncertainty intervals;
- force liquidation at the final candle;
- model maker orders, queue priority, order-book depth, or nonlinear impact;
- simulate liquidation and maintenance margin;
- hash the canonical result ledger;
- persist runs, fills, equity curves, or reports;
- authorize final holdout execution;
- promote a strategy to paper trading.

An open position is marked to the final close, and a late target remains explicitly pending with a warning. These states are not silently converted into a favorable terminal fill.
