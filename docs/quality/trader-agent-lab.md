# Quantara Trader Agent Lab

The Trader Agent Lab is a deterministic, persona-driven release gate. It does not
pretend that a synthetic test is a profitable trader. Its purpose is to exercise
product workflows repeatedly, surface regressions and produce reproducible bug
reports before a build is promoted.

## Built-in agents

| Persona | Primary focus |
| --- | --- |
| Arman | conservative 1h/4h setup quality and capital/risk sizing |
| Nima | rapid 15m navigation, symbol switching and notification pressure |
| Sara | risk settings, leverage boundaries and persistence |
| Kian | Bitunix read-only onboarding, refresh, revoke and failure states |
| Mina | Persian RTL, light mode, large text and narrow-screen layout |
| Reza | background/foreground, slow/intermittent network and restart chaos |
| Leila | Strategy Lab replay, forward sessions and outcome history |
| Omid | execution safety, authority boundaries, reconciliation and auditability |

## Reproducibility

Every run has a seed. A report includes the persona ID, step ID, feature,
severity, seed, elapsed time and exact failure details. A failed run must be
repeatable with the same seed before it is accepted as a product bug; flaky
infrastructure failures are tracked separately and do not get silently ignored.

## Release-blocking findings

The following are P0/P1 blockers:

- uncaught Flutter errors or app termination;
- layout overflow, grey overlay, endless scroll or permanent loading state;
- saved capital/risk not propagating to pending setup sizing;
- stale setup remaining eligible for execution;
- live-trading authority before staged approval gates;
- any withdrawal or transfer authority;
- settings/history loss after restart;
- missing kill switch, idempotency or reconciliation in an executable mode.

## Rollout

1. Pure deterministic runner and fake probe.
2. Widget probe against the complete in-memory app.
3. Android integration probe on API 34, 35 and 36.
4. Thirty-minute soak and 100-navigation stress runs.
5. Shadow-account and read-only Bitunix failure injection.
6. Manual/canary execution probes using a fake exchange connector before any
   physical-account canary.

The first version is intentionally fail-closed and has no real-money authority.
