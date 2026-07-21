# Engineering and Trading Quality Gates

Quantara separates software correctness, simulation validity, research evidence, and production readiness. Passing one gate never implies the next gate has passed.

## Gate 1: Repository integrity

Required on every pull request:

- The pinned .NET SDK is available.
- Restore, formatting verification, Release build, and automated tests pass.
- Repository validation scripts pass.
- Docker Compose configuration is valid.
- Failures are visible and are not ignored or converted to successful results.

This gate proves that the checked-in code can be built and tested in the CI environment. It does not prove trading profitability, exchange correctness, or production safety.

## Gate 2: Domain and execution correctness

Before paper trading can be promoted:

- Financial values use decimal arithmetic.
- Risk decisions are deterministic and versioned.
- Quantity and price normalization cannot raise approved risk.
- Order transitions are explicit, tested, and auditable.
- Duplicate requests and duplicate events are idempotent.
- Restart and reconciliation tests pass.
- Stale data, disconnection, circuit breakers, and kill switches block opening risk.
- Reduce-only exits remain possible during protective shutdown states.

## Gate 3: Backtest validity

Every strategy experiment must include:

- Dataset provenance and immutable configuration.
- Strict chronological train, validation, and untouched test partitions.
- Walk-forward or rolling out-of-sample evaluation.
- Fees, spread, slippage, funding, latency, and realistic fill constraints.
- Market-regime breakdowns and parameter-sensitivity analysis.
- Baseline comparisons and a complete trade ledger.
- Explicit checks for look-ahead bias and future-data leakage.

A high in-sample result is not evidence of a deployable strategy.

## Gate 4: Strategy promotion

Win rate is descriptive, not a sufficient objective. Quantara must also report:

- Expectancy.
- Profit factor.
- Maximum drawdown.
- Return-to-drawdown ratio.
- Sharpe and Sortino ratios where statistically meaningful.
- Tail losses.
- Exposure time and turnover.
- Trade count, confidence intervals, and stability across folds and regimes.

A research target such as a win rate above 60 percent may be recorded, but it is never guaranteed and cannot override poor expectancy, excessive drawdown, a small sample, instability, or failure on unseen data.

## Gate 5: Paper and shadow evidence

Before live trading is considered:

- Paper accounting reconciles balances, margin, fees, funding, fills, and PnL.
- Restart recovery and reconciliation pass repeatedly.
- Shadow decisions are evaluated on live market data without order submission.
- Performance is observed across multiple market regimes and operational failures.
- User workflows and emergency controls pass acceptance testing.

## Gate 6: Restricted live release

Live trading remains unavailable until a separate release decision verifies all safety dependencies. It must require independent server-side and user-level gates, strict allocation and loss limits, trade-only credentials, tested protection orders, healthy data streams, full auditability, and rollback/incident runbooks.

No quality gate can guarantee profit. The goal is to reduce avoidable technical, statistical, and operational risk while making uncertainty visible.

