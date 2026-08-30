# Strategy validation and promotion gate

Quantara does not promote a strategy from one backtest, one profitable week, or a high historical win rate. Promotion evidence must remain chronological, reproducible and conservative.

## Required evidence path

1. **Deterministic Replay** uses only information available at each event time. Closed candles are the default decision truth.
2. **Purged walk-forward validation** uses expanding training windows, explicit purge gaps before each validation fold and embargo gaps after each fold.
3. **Locked holdout** is excluded from tuning and walk-forward selection. It is evaluated only as final out-of-sample evidence.
4. **Realtime Shadow** observes the real pipeline without order authority. Default promotion evidence requires at least 14 days and the configured terminal sample floor.
5. **Paper** uses the same canonical pre-execution decision as Replay/Shadow/Live, then realizes conservative simulated fees, spread, slippage, funding, latency penalty and deterministic partial fills.
6. **Tiny-risk Canary eligibility** is a gate only. Validation code never starts the system, never changes leverage/risk and never places an order. Start must already be enabled and Capital Guardian must independently allow new risk.

## Leakage and data provenance

Every promotion packet identifies the dataset, dataset version, point-in-time universe timestamp, strategy configuration hash and source build. A strategy cannot be promotion-ready when survivorship-bias control is not proven. Purge, embargo and locked holdout boundaries are part of the evidence packet so a later reviewer can reproduce the split.

## Calibration

The UI should present **Setup Quality Score** until the minimum calibration sample size has been reached for the matching playbook + playbook version + regime + timeframe identity. Only then may the same score be presented as a calibrated probability when Brier/calibration evidence is healthy.

Calibration drift, coverage collapse, execution-cost drift or trigger-latency SLO breach automatically downgrades presentation to score-only. This is a deterministic safety downgrade; it does not auto-tune strategy parameters.

## Uncertainty and robustness

Promotion evidence includes:

- Brier score and calibration error;
- bootstrap expectancy distribution and probability of positive expectancy;
- trade-order Monte Carlo maximum-drawdown distribution;
- fee/spread/slippage/funding/latency/partial-fill stress assumptions;
- missed-fill/cost stress scenarios;
- parameter-neighborhood stability so a sharp isolated optimum is rejected;
- current-engine, same-risk no-skill timing, buy-and-hold context and simple-trend baselines;
- opportunity funnel counts and signals per week;
- locked-holdout expectancy and realtime Shadow sample duration/count.

## Champion / challenger and rollback

Promotion packets keep explicit champion/challenger identities for the strategy family and management policy. Validation never overwrites the champion or silently changes live parameters. Each regime playbook retains its independent feature flag, so a problematic playbook can be rolled back without disabling the others.

## Hard authority boundary

`strategy_validation_*` and promotion code must not depend on Bitunix private clients, order placement, transfer/withdrawal operations, margin-mode changes, leverage changes or portfolio reservation. Live execution remains behind the existing deterministic system-start, Capital Guardian, atomic reservation, protected executor and reconciliation gates.
