# Strategy Engine v2 validation gates

No playbook is promoted to default notifications only because a synthetic test
passes or a historical win rate looks high.

Required gates:

- chronological train, walk-forward and locked holdout windows;
- fees, spread and slippage applied before expectancy is calculated;
- results split by trend, range, breakout and disorder regimes;
- minimum trade-count and signals-per-week evidence;
- expectancy in R, profit factor, maximum drawdown and average win/loss;
- parameter stability around the chosen values;
- comparison against Structure & Zones and a no-skill baseline;
- paper/shadow observation before default notification rollout.

The first implementation loop remains an experimental paper-trading feature.
