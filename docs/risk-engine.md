# Risk Engine

The risk engine is deterministic and independent of any LLM. It approves, rejects, or annotates proposed decisions before execution.

## Required Rules
Risk policies include risk per trade, daily loss, weekly loss, total drawdown, leverage, portfolio exposure, symbol exposure, correlated exposure, concurrent positions, minimum risk/reward, spread, slippage, consecutive-loss circuit breaker, cooldown, stale-data protection, exchange-disconnection protection, duplicate-order protection, and emergency kill switch.

## Position Sizing
Position size is calculated from account equity, configured risk percentage, entry price, stop-loss distance, contract rules, estimated fees, and estimated slippage. Leverage changes required margin but must not increase configured monetary risk.

## Prohibited Behavior
Martingale, unlimited averaging down, and loss-chasing are disabled. Opening orders are blocked when data is stale, exchange connectivity is unhealthy, or the global kill switch is active. Reduce-only and closing actions remain available during kill-switch state.
