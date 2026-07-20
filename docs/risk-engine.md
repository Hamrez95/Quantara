# Risk Engine

The Quantara risk engine is deterministic, side-effect free, versioned, and independent of any LLM. It evaluates a structured request and returns an approval or every applicable rejection reason together with sizing and exposure calculations.

## Evaluation contract

A result contains:

- approval status and primary decision code;
- all rejection codes, not only the first failure;
- warnings that do not silently change risk;
- monetary risk budget;
- raw and exchange-normalized quantity;
- required margin, fees, and slippage estimates;
- portfolio exposure before and after the proposed trade;
- evaluation timestamp and risk-policy version.

All financial calculations use `decimal`.

## Opening-trade gates

Opening risk is rejected when any configured or observed condition is unsafe, including:

- invalid policy or instrument rules;
- invalid equity, balance, entry, stop, target, risk percentage, or cost estimate;
- incorrect long/short stop or take-profit direction;
- minimum risk/reward failure;
- daily loss, weekly loss, or drawdown limit;
- leverage, concurrent position, portfolio exposure, symbol exposure, or allocation limit;
- spread or slippage limit;
- stale market data or exchange disconnection;
- circuit breaker, cooldown, consecutive-loss breaker, or kill switch;
- insufficient balance, minimum quantity, or minimum notional.

Invalid configuration fails closed before opening-trade calculations continue.

## Position sizing

The risk budget is derived from account equity and requested risk percentage. Per-unit loss includes stop distance, contract size, estimated round-trip fees, and estimated slippage.

Quantity is always normalized downward to the exchange quantity step and precision. It is never rounded upward in a way that can exceed the approved monetary risk. When an instrument maximum is lower than the calculated quantity, the quantity is capped downward and a warning is returned.

Leverage changes required margin but never increases the monetary risk budget.

## Emergency exposure reduction

Reduce-only requests use an explicit requested quantity and cannot increase portfolio exposure. They remain eligible during kill-switch state and do not depend on opening-policy validity. Instrument quantity rules still apply so malformed close requests fail safely.

Execution connectivity and exchange acknowledgement remain responsibilities of the execution layer; risk approval does not claim that an exit was submitted or filled.

## Prohibited behavior

Martingale, unlimited averaging down, loss chasing, LLM-controlled order execution, and withdrawal functionality remain prohibited. Opening orders are blocked during unsafe states, while tested reduce-only paths remain available for exposure reduction.
