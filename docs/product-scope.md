# Product Scope

## Objective
Quantara receives real-time and historical crypto market data, performs multi-timeframe technical analysis, normalizes approved-source research, combines market, funding, portfolio, and deterministic risk information, and produces trade decisions that may be analysis-only, proposed, approved, or executed.

## Milestone Plan
1. **Milestone 1: Foundations and safety baseline.** Documentation, ADRs, monorepo structure, Docker Compose, deterministic mock exchange, core domain models, and unit-test specifications.
2. **Milestone 2: Risk engine and order state machine.** Deterministic sizing, circuit breakers, durable order lifecycle, and reconciliation tests.
3. **Milestone 3: Market data and strategy framework.** Historical ingestion, WebSocket ingestion, candle aggregation, stale-data gates, and versioned strategy outputs.
4. **Milestone 4: Paper and shadow trading.** Paper exchange, portfolio simulation, latency/spread/slippage modeling, and dashboard views.
5. **Milestone 5: Research pipeline.** Approved-source ingestion, structured LLM validation, freshness checks, and decision-engine integration.
6. **Milestone 6: Bitunix read-only integration.** Official REST/WebSocket market data, balances, positions, and reconciliation.
7. **Milestone 7: Restricted live trading.** Only after mock, paper, risk, state-machine, and reconciliation tests pass; disabled unless all live safeguards are true.

## Milestone 1 Assumptions
- The repository starts empty except for Git metadata.
- Local development uses PostgreSQL and Redis via Docker Compose.
- .NET SDK and Docker may not be installed in every execution environment; project files are still created for the intended stack.
- Live Bitunix order placement is out of scope and must remain absent.

## Out of Scope for Milestone 1
- Real-money trading.
- Bitunix live order placement.
- LLM execution of orders.
- Withdrawal functionality.

