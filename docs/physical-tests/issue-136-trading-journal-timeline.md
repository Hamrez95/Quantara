# Issue 136 — Durable trading journal and position timeline

## Truth model

The journal is an append-only observer. Immutable plans and exchange/Quantara/user events are stored separately. UI cards and statistics are projections rebuilt from that ledger. Exchange facts retain position, order and trade identity plus source, quality, scope, currency and `asOf` metadata.

Duplicate exchange events are idempotent. The same identity with different economic content makes the journal unverified instead of overwriting history.

## Durability

Journal state uses two checksummed local slots and a commit pointer outside foreground-task state. A write is committed only after inactive-slot read-back succeeds and the pointer flips. A damaged active slot falls back to the previous verified snapshot with an explicit recovery warning.

JSON/CSV exports remove client IDs and secret-like fields. Passphrase export uses PBKDF2-HMAC-SHA256 and authenticated AES-256-GCM; raw exchange credentials are never journal fields.

## Position timeline

The first XRP fixture represents:

1. short entry quantity 21.4 at about 1.0665;
2. original stop confirmation;
3. TP1 quantity 13.91 at about 1.0603;
4. profit-lock stop request and exchange confirmation;
5. remaining quantity 7.49 closed at stop;
6. gross PnL, fee, funding, net PnL, realized R and holding duration.

The TP1 result remains realized and is not erased by the later stop. Timeline order uses exchange occurrence time, then record time and stable local identity.

## Safety boundary

Journal load, import, export, filters, statistics and UI have no dependency on an exchange mutation client. Journal persistence failures are swallowed by the observer and never trigger a compensating order action. Phase 1 real entries remain disabled.

## Physical Samsung checklist — external/read-only

Do not open a new position and do not change any existing exchange order.

1. Open Journal and verify explicit loading/empty/error states.
2. Verify Persian layout is RTL and English layout is LTR.
3. Open an XRP record and verify Entry precedes TP/SL/Close events.
4. Verify each exchange event displays its fact source/quality and is not duplicated after refresh/restart.
5. Verify gross, fee, funding and net are separate; unavailable values are not displayed as zero.
6. Restart the app and verify the same timeline and immutable pre-trade plan return.
7. Export privacy JSON/CSV and confirm no API key, secret, credential, token or client ID exists.
8. Export an encrypted archive, import it with the correct passphrase and confirm a wrong passphrase fails authentication.
9. Confirm no journal action can place, cancel, modify or re-arm an order.

`main` and Draft Release PR #131 remain untouched.
