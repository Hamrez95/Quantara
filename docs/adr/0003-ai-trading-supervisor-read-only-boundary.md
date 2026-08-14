# ADR 0003: Read-Only AI Trading Supervisor Boundary

## Status
Accepted for issue #180 implementation.

## Context
Quantara needs an AI-assisted Trading Supervisor that can explain runtime behavior, correlate diagnostics with journal evidence, and propose strategy or engineering experiments without becoming a privileged trading actor.

The repository already has diagnostic-export and Support Session work intended for privacy-safe support workflows. The Supervisor should reuse those observation paths instead of creating a second unrestricted telemetry channel.

## Decision
The first AI Supervisor integration is analysis-only and read-only with respect to live trading authority.

### Observation boundary
Supervisor input is built from explicitly allow-listed, strongly typed observation contracts. Unknown fields are not forwarded automatically.

Allowed categories include:
- runtime/build/session identifiers that are not credentials;
- scanner heartbeat and deterministic block/rejection reasons;
- aggregate account/risk/capacity state required for diagnosis;
- managed position metadata required to explain lifecycle state;
- sanitized strategy/version/symbol/timeframe/regime evidence;
- sanitized journal and diagnostic evidence identifiers;
- health/anomaly observations derived from deterministic application state.

Prohibited categories include:
- exchange API keys or secrets;
- authorization/private request headers;
- request signatures, private keys, passwords or session credentials;
- raw credential-bearing request/response payloads;
- any command that can mutate a live order, position, leverage, stop/TP, risk limit, transfer, or live strategy configuration.

Text/event sanitization remains defense in depth after the allow-list rather than the primary trust boundary.

### Reuse existing evidence paths
The Supervisor must prefer existing sanitized diagnostic export evidence and the existing Support Session lifecycle for remote observation. Remote observation remains explicit opt-in, read-only, revocable, time-limited, and off/local by default.

### AI service boundary
OpenAI credentials are server-side only. Mobile/Flutter code must not contain an OpenAI API credential.

The analysis gateway accepts only a sanitized review bundle and returns a structured review. The gateway exposes no exchange or trading mutation methods.

A future ChatGPT/MCP adapter, if added, must sit on the same read-only Supervisor contract and must not create an alternate privileged route to exchange credentials or live execution.

### Review contract
AI review output must separate:
- observed facts with stable evidence references;
- hypotheses with confidence;
- risk/health observations;
- recommendations;
- required validation tests;
- rollback or stop criteria.

Recommendations are experiments, not production mutations. Any strategy/configuration change must pass deterministic tests plus the repository's backtest/walk-forward and paper/shadow validation gates before explicit promotion.

### Fail-closed behavior
If required evidence is missing, stale, malformed, or outside the allow-list, the Supervisor reports insufficient evidence rather than inventing a conclusion or requesting broader authority.

## Consequences
- AI can diagnose and recommend without receiving live execution authority.
- Credential exposure risk is reduced because arbitrary runtime maps do not cross the AI boundary.
- Existing diagnostic and Support Session infrastructure remains the canonical observation path.
- Future OpenAI or MCP adapters can change independently without changing trading authority.
- Some useful diagnostics may be unavailable until they are deliberately added to the allow-listed contract; this is intentional.

## Non-goals for #180
- order placement or cancellation;
- position mutation;
- leverage changes;
- stop-loss/take-profit mutation;
- transfers;
- risk-limit mutation;
- automatic live-strategy/configuration mutation;
- autonomous promotion of AI recommendations.
