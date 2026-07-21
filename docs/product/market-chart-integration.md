# Market chart integration

## Product decision

Quantara separates the chart engine from the market-data provider.

- The backend owns normalized OHLCV candles, UTC timestamps, symbol mapping, freshness and gap detection.
- Flutter consumes a typed chart stream and does not depend on Bitunix response shapes.
- The chart component can switch from deterministic demo candles to read-only exchange candles without changing the screen contract.

## TradingView choice

The first in-app professional chart will use **TradingView Lightweight Charts** with Quantara/Bitunix candle data. It is open source, supports streaming updates and is designed for high-volume financial series.

TradingView Advanced Charts is a separate option. It requires access to TradingView's private package and must not be copied into a public repository. It will only be considered after access and redistribution terms are confirmed.

Official references:

- https://www.tradingview.com/lightweight-charts/
- https://www.tradingview.com/charting-library-docs/latest/getting_started/
- https://www.tradingview.com/charting-library-docs/latest/mobile_specifics/

## Client boundary

The client chart adapter receives:

- market and normalized symbol;
- timeframe;
- ordered UTC candles;
- data-source mode (`demo`, `read_only_market`, `paper`);
- last complete candle and optional live partial candle;
- freshness and reconnect status.

The adapter supports:

- full history replacement;
- incremental candle update;
- symbol and timeframe change;
- dark/light theme change without reconstructing the whole page;
- connection-lost and stale-data overlays;
- visible TradingView attribution where required.

## Mobile and web implementation

- PWA: host the Lightweight Charts JavaScript bundle inside the app and communicate through a narrow Dart/JavaScript bridge.
- Android/iOS: render the same local chart surface in a controlled web view and send typed messages through the platform bridge.
- No remote HTML or arbitrary script is loaded into the chart surface.
- A separate action may open the corresponding public TradingView symbol page for broader community indicators.

## Safety

A chart is visualization only. It cannot grant execution authority, place orders or hide stale data. Live-looking animations stop when the feed is disconnected or stale.
