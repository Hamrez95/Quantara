# Architecture

## Monorepo Layout
- `src/backend`: ASP.NET Core-oriented backend libraries and future services.
- `apps/analytics`: Python/FastAPI analytics, research, and statistical modules.
- `apps/web`: Next.js TypeScript dashboard.
- `infra`: local development infrastructure and database bootstrap files.
- `docs`: product, architecture, risk, threat-model, order-state-machine, and ADR documentation.
- `tests`: automated tests grouped by stack.

## Modular Backend Boundaries
The first backend version is a modular monolith with separable modules: identity, exchange abstraction, market data, technical analysis, research, decision engine, risk, execution, audit, and observability. Modules communicate through explicit interfaces and domain records, not shared mutable infrastructure state.

## Safety Defaults
Every environment defaults to paper trading through `TRADING_MODE=PAPER`. Live trading additionally requires a server-side feature flag, user live setting, maximum allocation, verified credentials, configured risk limits, active stop-loss policy, healthy WebSocket state, fresh market data, no circuit breaker, and explicit acknowledgement.

## Exchange Integration
`IExchangeConnector` defines the exchange boundary. Milestone 1 includes `DeterministicMockExchangeConnector` for repeatable tests. Paper and Bitunix implementations are later milestones. The Bitunix adapter must use only official documented APIs and must not call reverse-engineered TradingView endpoints.

## Observability and Data Types
Production services will use OpenTelemetry-compatible structured logs and traces. Money, price, quantity, fees, margin, and risk use `decimal` in .NET domain models.
