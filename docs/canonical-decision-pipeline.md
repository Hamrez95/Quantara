# Canonical decision pipeline

Quantara uses one versioned **pre-execution** decision contract across Replay, realtime Shadow, Paper and protected Live execution.

`MarketEvent / EventTime -> trusted market state -> versioned evidence and playbook -> candidate lifecycle -> economic/risk decision -> allocation intent -> environment adapter`

The canonical record owns event-time validation, candidate expiry/invalidation, exchange normalization when rules are known, leverage and risk sizing, estimated execution economics, portfolio/symbol heat gates and a deterministic pre-execution fingerprint. Environment mode is provenance only and is excluded from the parity fingerprint.

## Intentional environment differences

- **Replay** has no network or order authority. Captured/versioned evidence is replayed through the canonical decision record and simulated execution is downstream.
- **Shadow** observes realtime evidence but cannot place orders. Captured Shadow evidence can be replayed through the same canonical path and must reproduce the same pre-fill fingerprint.
- **Paper** consumes the canonical pre-fill quantity, leverage, margin and risk decision, then realizes conservative simulated fills, gaps, same-candle stop/target ambiguity and configured execution costs.
- **Live** consumes the same canonical pre-fill decision, but atomic portfolio reservation and the protected Bitunix executor remain the final authorities. Confirmed fills, fees, funding and realized slippage are separate facts and are never overwritten by simulated estimates.

Replay/Shadow adapters explicitly reject Paper/Live authority. The canonical decision core contains no exchange client, credential, transfer, withdrawal or order-placement dependency.

## Provenance and drift protection

Every canonical decision records pipeline/model versions, market dataset source/version, strategy configuration identity, build identity and environment. Cross-mode golden tests require identical deterministic inputs to produce identical parity JSON and pre-execution fingerprints. Runtime integration tests ensure Paper and Local Live actually consume the canonical result instead of reimplementing sizing formulas.

Captured `SignalJournalEntry` evidence is converted into the same versioned candidate contract by `trading_lab_canonical_replay.dart`. Replay and Shadow are allowed; Paper and Live are rejected by that adapter.

Future economic ranking (#192), portfolio allocation (#194), validation/promotion (#110) and autonomy authority (#195) must extend this shared contract rather than create environment-specific decision forks.
