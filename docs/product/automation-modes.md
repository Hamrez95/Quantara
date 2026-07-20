# Quantara automation modes

## Goal

Quantara must turn a broad instruction such as “use a limited budget and continue looking for opportunities” into an explicit, reviewable and time-bounded operating mode.

## Modes

### 1. Observe

- Read-only market monitoring.
- Explanations, freshness and risk context.
- No account action.

### 2. Assist

- Quantara prepares a complete proposed plan.
- The user reviews every proposed action before it can proceed.
- Best first mode for learning the product and calibrating trust.

### 3. Paper Auto

- Quantara operates independently against the durable simulated account.
- The same capital, exposure, loss and timing limits intended for a later real session are enforced.
- Results are reconciled and reviewed before any higher mode is considered.

### 4. Bounded Live Session

A real session is never unlimited. Before it starts, the user confirms:

- allocated capital;
- maximum risk per position;
- maximum session loss;
- maximum concurrent positions;
- allowed markets;
- hard expiry time;
- stale-data and disconnect behaviour;
- emergency stop behaviour.

Extending time or capital creates a new confirmation. A disconnected, expired or inconsistent session fails closed.

## Product flow

The app asks plain-language questions, converts the answers to an explicit session contract, and displays the worst-case loss before confirmation. While running, the user always sees allocated capital, current exposure, remaining loss budget, expiry and the stop control.

## Rollout order

1. Observe
2. Assist
3. Paper Auto
4. Bounded Live Session

The unlimited instruction “continue forever until I manually stop it” is not supported.
