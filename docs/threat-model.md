# Threat Model

## Assets
- Exchange API keys and secret material.
- Trading decisions, orders, balances, and positions.
- User identity, roles, permissions, and audit events.
- Market-data integrity and research provenance.

## Primary Threats
- Secret leakage to logs, frontend, or unauthorized services.
- Unauthorized live trading through privilege escalation or misconfiguration.
- Replay attacks against exchange or internal order APIs.
- Stale, incomplete, manipulated, or inconsistent market data causing unsafe trades.
- LLM-generated content bypassing deterministic validation.
- Dependency, supply-chain, CSRF, XSS, and rate-limit abuse.

## Controls
- Never send exchange secrets to the frontend.
- Encrypt credentials at rest and support secret rotation.
- Enforce least-privilege roles separating read-only, paper, and live trading.
- Store immutable audit events for security-sensitive actions.
- Validate inputs, timestamps, nonces, and structured LLM output.
- Redact secrets from logs and traces.
- Block opening orders when kill switch, stale data, disconnects, circuit breakers, or risk violations are active.
- No withdrawal functionality.
