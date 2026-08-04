# Local Live armed-intent resilience

This document defines the runtime boundary validated by physical Samsung testing for Quantara `1.2.0-rc.2`.

## User intent

After the user explicitly completes preflight and starts guarded Local Live, a transient failure in the app-side private-account projection must not permanently erase that armed intent.

The following app-projection states are transient signals rather than service stop commands:

- a reconciliation request is still in flight;
- a previously valid private snapshot becomes temporarily stale after one failed poll;
- the app projection is temporarily unavailable while the Android foreground service continues running.

The foreground service still fetches fresh account and position truth independently before any scan can create an order. A failed service exchange cycle creates no entry. Three consecutive service-cycle failures retain the existing circuit breaker and block new entries.

## Immediate hard blocks

New entries remain fail-closed when any of these conditions is confirmed:

- the user disconnects the private Bitunix credentials;
- Local Live and the private-account projection disagree about open-position count;
- unmanaged exchange exposure is detected;
- existing exposure lacks complete exchange-confirmed protection or required history;
- daily loss, portfolio risk, reserved margin, exchange minimum, isolated-margin, one-position, stop-side, duplicate-entry, or protection gates fail.

A hard block never re-arms automatically. Fresh preflight and explicit user action are required.

## Physical acceptance

On a flat account, start Local Live and leave the app foregrounded, backgrounded, and screen-off for several hours. Short private-API or connectivity interruptions may skip cycles and surface warnings, but must not change the service from Active to Manage-only unless a hard-block condition is confirmed. Force Stop, reboot, revoked credentials, or Android stopping the foreground service remain manual-restart boundaries.
