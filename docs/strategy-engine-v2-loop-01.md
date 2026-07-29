# Strategy Engine v2 — loop 01

## Build

- Added reusable EMA 20/50/200, ATR 14, RSI 14, ADX/DI, relative-volume,
  volume z-score, Donchian 20, Bollinger bandwidth, trend-efficiency and swing
  calculations.
- Added regime classification for trend, range, breakout expansion, transition
  and high-volatility disorder.
- Replaced the previous strategy-name-only behaviour for `trendPullback` and
  `momentumContinuation` with independent playbooks:
  - EMA/ADX/RSI/closed-candle trend pullback.
  - Donchian breakout with ATR and volume expansion.
- Kept Structure & Zones unchanged as the control strategy.
- Preserved risk-percent caps, estimated round-trip costs, volatility-aware
  leverage caps and three targets.

## Tests

- Indicator behaviour on a persistent bullish series.
- Breakout and range regime classification.
- End-to-end Donchian setup generation with risk sizing.

## Self-critique

- This loop does not yet add Ichimoku, range mean reversion or price-action
  reversal execution paths.
- Regime and score details are not yet shown in the UI.
- Thresholds are research candidates, not validated production parameters.
- A synthetic unit test is necessary but insufficient evidence of profitability.

## Next correction loop

1. Fix all analyzer, formatter and test findings from CI.
2. Add candidate/rejection telemetry to the UI and journal.
3. Implement Range Mean Reversion and Price Action at Structure behind shadow
   flags.
4. Add walk-forward backtest fixtures with fees and slippage before enabling
   Strategy Engine v2 notifications by default.
