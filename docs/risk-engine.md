# Risk Engine

The Quantara risk engine is deterministic, side-effect free, versioned, and independent of any LLM. It evaluates a structured request and returns an approval or every applicable rejection reason together with normalized prices, sizing, and exposure calculations.

## Evaluation contract

A result contains:

- approval status and primary decision code;
- all rejection codes, not only the first failure;
- warnings that do not silently change risk;
- normalized entry, stop-loss, and take-profit prices;
- monetary risk budget;
- raw and exchange-normalized quantity;
- required margin, fees, and slippage estimates;
- portfolio exposure before and after the proposed trade;
- correlation group and correlated exposure before and after the proposal;
- evaluation timestamp and risk-policy version.

All financial calculations use `decimal`.

## Opening-trade gates

Opening risk is rejected when any configured or observed condition is unsafe, including:

- invalid policy, instrument rules, or correlation context;
- invalid equity, balance, entry, stop, target, risk percentage, or cost estimate;
- incorrect long/short stop or take-profit direction;
- minimum risk/reward failure;
- daily loss, weekly loss, or drawdown limit;
- leverage, concurrent position, portfolio exposure, symbol exposure, correlated exposure, or allocation limit;
- spread or slippage limit;
- stale market data or exchange disconnection;
- circuit breaker, cooldown, consecutive-loss breaker, or kill switch;
- insufficient balance, minimum quantity, or minimum notional.

Invalid configuration fails closed before opening-trade calculations continue.

## Conservative price normalization

All proposal prices are normalized to the instrument tick size before risk/reward and position size are calculated. The normalization deliberately assumes a less favorable execution outcome:

| Direction | Entry | Stop loss | Take profit |
|---|---|---|---|
| Long | Round up | Round down | Round down |
| Short | Round down | Round up | Round up |

This widens or preserves loss distance and narrows or preserves expected reward. A warning is returned whenever any proposal price changes. Tick size and quantity step must be representable by their declared precision; incompatible instrument rules fail closed.

## Position sizing

The risk budget is derived from account equity and requested risk percentage. Per-unit loss includes the normalized stop distance, contract size, estimated round-trip fees, and estimated slippage.

Quantity is always normalized downward to the exchange quantity step and precision. It is never rounded upward in a way that can exceed the approved monetary risk. When an instrument maximum is lower than the calculated quantity, the quantity is capped downward and a warning is returned.

Leverage changes required margin but never increases the monetary risk budget.

## Correlated exposure

The versioned `RiskPolicy` owns the maximum correlated exposure percentage. A caller cannot weaken this cap through proposal metadata.

An optional correlation context groups positions whose risks may move together, such as large-cap crypto assets or tokens sharing the same ecosystem. It contains:

- a stable correlation-group identifier;
- current gross exposure in that group;
- a conservative factor from `0` to `1` representing how much of the proposed notional contributes to the group.

The engine adds proposed notional multiplied by this factor to current group exposure and compares the result with the policy-owned limit. It uses gross exposure and does not assume that a short position safely offsets a long position. This is intentionally conservative until a validated portfolio covariance model exists.

A malformed correlation context rejects opening risk. Invalid correlation output is sanitized so UI clients never receive negative or malformed exposure values. Absence of a correlation context preserves previous behavior. Reduce-only requests may proceed with a warning when correlation metadata is malformed because exposure reduction must not be blocked by unrelated opening-risk configuration.

## Emergency exposure reduction

Reduce-only requests use an explicit requested quantity and cannot increase portfolio or correlated exposure. They remain eligible during kill-switch state and do not depend on opening-policy validity. Instrument quantity rules still apply so malformed close requests fail safely.

Execution connectivity and exchange acknowledgement remain responsibilities of the execution layer; risk approval does not claim that an exit was submitted or filled.

## Prohibited behavior

Martingale, unlimited averaging down, loss chasing, LLM-controlled order execution, and withdrawal functionality remain prohibited. Opening orders are blocked during unsafe states, while tested reduce-only paths remain available for exposure reduction.

