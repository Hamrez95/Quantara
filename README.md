# Quantara

Quantara is a safety-first crypto trading analysis and automation platform. The modular monorepo contains a .NET backend, PostgreSQL/Redis infrastructure, a Flutter Android and web/PWA cockpit, and research services for technical and fundamental analysis.

## Current status

Android preview 0.4.0 uses real public Bitunix Futures prices and closed candles for periodic multi-timeframe analysis, support/resistance zones and explainable risk scenarios. It defaults to Persian and supports instant Persian/English RTL/LTR switching with device-local preferences. The active Android route does not fall back to simulated market data.

Market data currently refreshes every 60 seconds only while the app is open. It is not a WebSocket stream or a 24-hour background monitor. TradingView Lightweight Charts renders Quantara/Bitunix candles; TradingView is not the market-data feed. Android is the current product priority and PWA work is deferred.

Default trading mode is paper-only. Live Bitunix order placement, autonomous LLM order execution, and withdrawal functionality are intentionally unavailable.

## Quality policy

A successful build or a strong backtest does not prove profitability. Strategy candidates must pass chronological out-of-sample, walk-forward, realistic-cost, regime, stability, paper-trading, and shadow-trading gates before restricted live execution can even be considered. Win rate is reported beside expectancy, drawdown, profit factor, uncertainty, and sample size; it is never guaranteed or used alone.

See:

- [`docs/product-scope.md`](docs/product-scope.md)
- [`docs/architecture.md`](docs/architecture.md)
- [`docs/quality-gates.md`](docs/quality-gates.md)
- [`docs/branching-and-release.md`](docs/branching-and-release.md)
- [`docs/risk-engine.md`](docs/risk-engine.md)
- [`docs/order-state-machine.md`](docs/order-state-machine.md)
- [`docs/threat-model.md`](docs/threat-model.md)

## Local validation

With the pinned .NET 8 SDK, Python 3, and Docker Compose installed:

```bash
dotnet restore Quantara.sln
dotnet format whitespace Quantara.sln --verify-no-changes --no-restore
dotnet build Quantara.sln --configuration Release --no-restore
dotnet test Quantara.sln --configuration Release --no-build
python3 scripts/validate-milestone1.py
docker compose config --quiet
```

Flutter validation runs from `src/client/quantara_app`:

```bash
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze --fatal-infos
flutter test
flutter build apk --release
```

The Android preview reads only documented HTTPS public endpoints and requires no API key. A malformed, stale or unavailable market response fails closed and the interface identifies old snapshots instead of presenting them as fresh. Exchange credentials, real orders and withdrawals are absent.

Every implementation should begin with a GitHub issue, use a short-lived branch from `dev`, include tests and limitations, and enter `dev` through a reviewed pull request.
