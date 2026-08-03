# Issue 136 — Durable trading journal and position timeline

## Truth model

The journal is an append-only observer. Immutable plans and exchange/Quantara/user events are stored separately. UI cards and statistics are projections rebuilt from that ledger. Exchange facts retain position, order and trade identity plus source, quality, scope, currency and `asOf` metadata.

Duplicate exchange events are idempotent. The same identity with different economic content makes the journal unverified instead of overwriting history.

Gross PnL, fee and funding remain independent facts. Net PnL is unavailable until all three components are explicit; a missing fee or funding value is never treated as zero. Entry and exit fees are both included through the authoritative exchange fill projection.

## Durability

Journal state uses two checksummed local slots and a commit pointer outside foreground-task state. A write is committed only after inactive-slot read-back succeeds and the pointer flips. A damaged active slot falls back to the previous verified snapshot with an explicit recovery warning. The store reloads platform state before reads/writes and serializes writers in the current process. If both slots are unreadable, integrity is explicitly unverified and no values are fabricated.

JSON/CSV exports remove client IDs and recursively remove secret-like fields. Passphrase export uses PBKDF2-HMAC-SHA256 and authenticated AES-256-GCM; raw exchange credentials are never journal fields.

## Position timeline

The first XRP fixture represents:

1. short entry quantity 21.4 at about 1.0665;
2. original stop confirmation;
3. TP1 quantity 13.91 at about 1.0603;
4. profit-lock stop request and exchange confirmation;
5. remaining quantity 7.49 closed at stop;
6. gross PnL, entry/exit fees, funding, net PnL, realized R and holding duration.

The TP1 result remains realized and is not erased by the later stop. Timeline order uses exchange occurrence time, then record time and stable local identity. Entry fills, target fills, non-target partial closes and final closes are classified separately. Profit-lock confirmations use promotion-specific identities and cannot collide with the original stop confirmation.

## Safety boundary

Journal load, import, export, filters, statistics and UI have no dependency on an exchange mutation client. Journal plan/event persistence failures are swallowed by the observer and never trigger a compensating order action or fail an already-protected position cycle. Phase 1 real entries remain disabled.

## Automated evidence

Focused format, fatal-infos analyzer and journal/trading-safety tests passed on clean implementation head `45ab6a8d77594523dec82a088d390a42a6dbbc34`.

Review regressions additionally prove:

- Net remains unavailable until fee and funding are explicit;
- entry fee is included in the final TP1-then-stop net result;
- stop-promotion identity does not conflict with the original stop;
- journal persistence failure does not escape into exchange management;
- nested secret-like export fields are recursively redacted;
- a recovered valid slot remains available after another interrupted write.

All temporary patch/export workflows and payloads were removed from the final diff before the full release gates.

## Physical Samsung checklist — external/read-only

Do not open a new position and do not change any existing exchange order.

1. Open Journal and verify explicit loading/empty/error states.
2. Verify Persian layout is RTL and English layout is LTR.
3. Open an XRP record and verify Entry precedes TP/SL/Close events.
4. Verify each exchange event displays its fact source/quality and is not duplicated after refresh/restart.
5. Verify gross, fee, funding and net are separate; unavailable values are not displayed as zero.
6. Restart the app and verify the same timeline and immutable pre-trade plan return.
7. Export privacy JSON/CSV and confirm no API key, secret, credential, token or client ID exists, including nested detail objects.
8. Export an encrypted archive, import it with the correct passphrase and confirm a wrong passphrase fails authentication.
9. Confirm no journal action can place, cancel, modify or re-arm an order.

`main` and Draft Release PR #131 remain untouched.
