# Quantara Release Rollback / Forward-Recovery Plan

Quantara releases are immutable. Do not mutate or overwrite a published build.

## Before promotion

- Keep the previously published release/tag and its manifest available.
- Confirm the candidate has green repository, Flutter/Android upgrade and Windows build evidence for the exact source SHA.
- Confirm release notes state known limitations and do not claim profit or live-safety evidence that was not observed.
- Keep Local Live fail-closed: stale/unknown account, reconciliation, protection, strategy identity or pause persistence must block new risk.

## If a release is unsafe before publication

Stop the release. Leave `main` unchanged or revert the release PR on `main` through a reviewed PR. Never bypass failed checks to publish.

## If a published build is unsafe

Use forward recovery:

1. Disable or fail-close the affected feature where possible without weakening protective/reduce-only behavior.
2. Revoke the affected build through the managed release manifest when supported.
3. Branch the minimal repair from the canonical stable source, add regression tests, and pass normal CI.
4. Publish a strictly newer build number/version. Do not replace assets under an existing tag/version.
5. Preserve diagnostics and incident evidence; never log credentials or signing material.

## Data and trading safety

- Rollback must not fabricate exchange/account/protection state.
- Never auto-resume scanning/trading after crash, update, reconnect or rollback.
- Never remove exchange-native protection merely to restore an older application state.
- Any unresolved live exposure is managed with risk-reducing behavior only until authoritative reconciliation succeeds.

Production/store publication remains an explicit operator action outside software CI.