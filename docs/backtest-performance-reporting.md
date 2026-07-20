# Canonical backtest performance reporting

## Purpose

This slice converts a completed deterministic backtest into an immutable, auditable performance report. It does not promote a strategy and does not authorize paper, shadow, or live execution.

## Trust boundary

A report is created only when all of the following are valid:

- the run is completed and its configuration fingerprint matches the supplied experiment, cost model, and execution rules;
- the equity curve is positive, ordered, contained inside the experiment evaluation window, and reconciles to final equity;
- the benchmark is positive, ordered, and timestamp-aligned with the strategy equity curve;
- decision, fill, and funding sequences are contiguous;
- fill and funding identifiers are unique;
- final position direction, signed quantity, contract multiplier, and average entry are internally consistent.

Invalid inputs fail closed with structured rejection codes.

## Canonical identities

Three separate hashes are preserved:

1. `LedgerSha256` binds the complete run evidence: decisions, fills, funding, equity, warnings, final position, final equity, and effective target.
2. `BenchmarkSha256` binds the benchmark name, starting value, timestamps, and every raw benchmark value.
3. `ReportSha256` binds the report specification, ledger identity, benchmark identity, experiment/run identities, metrics, and bootstrap interval.

Equal terminal returns are not considered equal evidence when the underlying paths differ.

## Metrics

The report includes:

- total and annualized return;
- annualized volatility;
- Sharpe, Sortino, and Calmar ratios;
- maximum drawdown and maximum drawdown duration;
- winning and losing period rates;
- fees, funding, spread cost, slippage cost, traded notional, turnover, time in market, and leverage;
- benchmark total/excess return, beta, correlation, tracking error, and information ratio;
- deterministic moving-block bootstrap interval for total return.

Metrics that are mathematically undefined remain explicit structured values with a reason. A valid zero is not confused with an undefined value: zero volatility and zero tracking error are reported as defined zero, while Sharpe or information ratio with zero denominator are undefined.

## Drawdown duration

Drawdown duration starts at the actual experiment evaluation-window boundary. If the first reported equity point is already below starting equity, the unobserved interval between the window start and that point is not discarded.

## Limitations

This slice does not yet provide:

- trade-level expectancy or profit factor because durable round-trip trade attribution is not yet part of the runner result;
- walk-forward aggregation, parameter-stability surfaces, regime segmentation, or Monte Carlo execution stress;
- immutable PostgreSQL report persistence;
- strategy promotion governance or final holdout publication;
- any paper or real order endpoint.

Those remain separate acceptance gates under the research and paper-trading milestones.
