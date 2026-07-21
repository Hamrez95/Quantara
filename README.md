# Quantara

Quantara is a safety-first crypto trading analysis and automation platform. The modular monorepo contains a .NET backend, PostgreSQL/Redis infrastructure, a Flutter Android and web/PWA cockpit, and research services for technical and fundamental analysis.

## Current status

Version 0.2.0 provides a stable Persian RTL Flutter cockpit, deterministic multi-timeframe candlestick analysis, support/resistance zones, a read-only ASP.NET cockpit API, and an explicit offline demo fallback. Active development is integrated into `dev`; `main` contains reviewed stable releases.

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
flutter build web --release
flutter build apk --release
```

Set `QUANTARA_API_BASE_URL` with `--dart-define` to use the read-only API. Release builds require HTTPS. When no API origin is configured, or a configured API is temporarily unreachable, the app remains usable with clearly labelled deterministic demo data. Unsafe or malformed API responses fail closed and are never hidden by the demo fallback.

Every implementation should begin with a GitHub issue, use a short-lived branch from `dev`, include tests and limitations, and enter `dev` through a reviewed pull request.
