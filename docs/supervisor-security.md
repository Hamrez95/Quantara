# Supervisor security contract

Quantara Supervisor support is read-only. A successful health check or support session proves connectivity only; it never grants trading execution authority.

## Session boundary

- A user must explicitly start a session.
- Sessions must have a positive duration and are capped at one hour.
- Stop/Disconnect revokes the session immediately.
- Expired or stopped sessions cannot emit gateway evidence.

## Exact outbound allow-list

Only scalar values for these keys may cross the Supervisor gateway:

- `connectionStatus`
- `lastSuccessfulHealthCheckAt`
- `diagnosticCode`
- `appVersion`
- `platform`

Unknown fields are denied by default.

## Denied data and authority

The gateway must not send exchange API keys/secrets, request signatures, authorization headers, control-token values, exchange credential objects, or raw nested payloads.

The Supervisor must not receive or exercise authority to place/cancel orders, change stop loss/take profit, change leverage, transfer funds, change risk limits, or start automatic trading. Corresponding mutation-shaped fields are explicitly denied by the mobile sanitizer as defense in depth.

Any change to the allow-list is security-sensitive and requires review plus deterministic regression tests.
