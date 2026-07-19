# Quantara

Quantara is a safety-first crypto trading analysis and automation platform. The project is being built as a modular monorepo with a .NET backend, PostgreSQL/Redis infrastructure, a future Flutter mobile and web/PWA client, and research services for technical and fundamental analysis.

## Current status

Milestone 1 provides the architecture baseline, deterministic domain models, a mock exchange, local PostgreSQL/Redis infrastructure, and initial tests. Active development is integrated into `dev`; `main` is reserved for reviewed release candidates.

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

Every implementation should begin with a GitHub issue, use a short-lived branch from `dev`, include tests and limitations, and enter `dev` through a reviewed pull request.
