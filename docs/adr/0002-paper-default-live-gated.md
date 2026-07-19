# ADR 0002: Paper Trading by Default

## Status
Accepted

## Decision
Default all environments to paper trading. Live trading requires every documented safeguard and is not implemented in Milestone 1.

## Consequences
Development and tests cannot accidentally place real orders. Live execution work is blocked until mock, paper, risk, state-machine, and reconciliation tests exist.
