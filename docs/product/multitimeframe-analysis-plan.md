# Multi-timeframe chart analysis

## Product goal

Quantara presents deterministic candlestick charts and explains important price structure for 15m, 1h, 4h and 1D intervals. The first release uses repeatable fixture candles so rendering and analysis can be validated before an external feed is trusted.

This feature is analytical and read-only. A detected zone is evidence, not an instruction or a promise of outcome.

## Roundtable decision

### Quant research

- Important prices are represented as zones rather than exact horizontal lines.
- Only confirmed pivots are considered. A final candle cannot confirm itself.
- Nearby pivots are clustered with a tolerance based on both price basis points and average true range.
- Zone strength combines confirmed reaction count, recency, rejection wick and relative volume.
- Reaction-count evidence saturates gradually at twelve touches so repeated old observations cannot create unlimited confidence.

### Risk review

- A single zone never authorizes an action.
- Missing, duplicate, unordered or mixed-interval candles are rejected before analysis.
- A level that breaks may change role, but its score receives a penalty until new evidence accumulates.
- The interface shows the data mode and does not animate stale input as live.

### Data engineering

The stable chart contract contains:

- UTC candle open time;
- open, high, low, close and volume;
- normalized symbol and interval;
- generated-at time and deterministic fingerprint;
- zones with lower/upper bounds, role, lifecycle state, touches, strength and distance.

The chart screen does not depend on Bitunix, TradingView or any provider-specific response shape.

### Mobile and UX

- Native Flutter painting is the first renderer because it is deterministic on Android and PWA and can be covered by widget tests.
- The screen shows the candle chart, one concise interval summary and at most three strongest zones.
- Detailed evidence remains available without filling the primary chart with labels.
- The renderer is isolated in a `RepaintBoundary` and does not use nested scrollable grids.
- 360×800 with text scale 1.3, repeated theme changes and interval changes are permanent regression gates.

### Critical review

A visually attractive line fitted through arbitrary highs and lows is easy to overfit. Quantara therefore avoids diagonal trend-line claims in this slice. The output is limited to deterministic horizontal zones whose source observations can be counted and reproduced.

The heuristic is not a statistical guarantee. Research on support and resistance suggests that prior bounce count may contain information and that effects decay with time, but production promotion still requires out-of-sample evaluation and calibration.

## Deterministic algorithm

1. Validate one symbol, one interval, ascending UTC opens and no missing candle.
2. Calculate true range and rolling average true range.
3. Detect pivot highs and lows with a symmetric confirmation radius.
4. Calculate rejection-wick and relative-volume evidence for every pivot.
5. Sort pivots by price and cluster nearby values using volatility-aware tolerance.
6. Reject clusters below the minimum confirmed-touch count.
7. Build a price zone around the cluster center.
8. Resolve current role as support, resistance or pivot.
9. Mark a confirmed break as a role flip and apply a confidence penalty.
10. Score, sort and cap the returned zones.
11. Calculate short/slow close structure and current volatility.
12. Hash normalized candles, specification and output into a canonical fingerprint.

## Multi-timeframe confluence

Each timeframe is analyzed independently first. A second deterministic pass clusters overlapping zones across timeframes. Longer intervals receive greater weight, while confluence adds a capped bonus. Input ordering cannot change the fingerprint.

Confluence is displayed as supporting context; disagreement between intervals is preserved rather than hidden behind one artificial score.

## Renderer boundary

The native renderer consumes only `TimeframeChartAnalysis`. It paints:

- candle bodies and wicks;
- volume bars;
- price grid and labels;
- current-price dashed line;
- support, resistance and pivot bands;
- dark and light themes.

A future TradingView adapter must implement the same boundary. The planned path is:

- PWA: locally hosted TradingView Lightweight Charts with an `HtmlElementView` adapter;
- Android/iOS: the same local chart surface in the official Flutter web view;
- backend: Quantara-owned normalized datafeed and freshness state;
- updates: full history replacement plus incremental last-candle updates;
- overlays: price lines or primitives generated from Quantara zones;
- no remote arbitrary HTML and no provider key inside the client.

TradingView Lightweight Charts provides the rendering library but not market data. Quantara remains responsible for the datafeed, gap handling, UTC normalization and stale-state display.

Official references:

- https://tradingview.github.io/lightweight-charts/
- https://tradingview.github.io/lightweight-charts/docs/api/interfaces/CandlestickData
- https://tradingview.github.io/lightweight-charts/tutorials/how_to/price-line
- https://www.tradingview.com/charting-library-docs/latest/connecting_data/Datafeed-API/
- https://api.flutter.dev/flutter/widgets/HtmlElementView-class.html
- https://pub.dev/packages/webview_flutter

## Current limitations

- Fixture candles are deterministic and not external market observations.
- Horizontal zones do not cover order-book liquidity, derivatives positioning or news events.
- Zone strength is a bounded heuristic and still requires calibration on multiple assets and regimes.
- The Flutter and C# implementations intentionally share the same concepts, but the backend will become the authoritative analyzer once the read-only API is connected.
- No action automation is introduced by this milestone.

## Promotion gates

Before external-feed release:

- backend and Flutter fingerprints must match on shared fixtures;
- historical gaps and partial candles must be explicit;
- multiple providers or a verified raw archive must reproduce the same normalized candles;
- out-of-sample evidence must measure bounce calibration, false breaks and regime sensitivity;
- the chart must pass Android device tests in dark/light mode and degraded connectivity states.
