# Research Reproducibility and Holdout Safety

Quantara does not treat a profitable backtest as evidence unless the exact code, data, split, costs, seed, parameters, and evaluation stage can be reproduced.

This slice establishes the research identity and anti-leakage boundary before implementing strategy returns or performance metrics.

## Identity layers

### Market content hash

`ContentSha256` identifies canonical candle and funding content.

The canonical stream includes:

- schema identifier;
- symbol and timeframe;
- candle count and ordered UTC timestamps;
- OHLCV values formatted from `decimal` with invariant culture;
- funding count, ordered UTC timestamps, and rates.

Dataset aliases, retrieval time, and provenance do not change the content hash. Changing one market value does.

### Dataset manifest hash

`ManifestSha256` binds the content hash to its provenance:

- provider;
- market type;
- source identifier;
- source schema version;
- retrieval timestamp;
- coverage, counts, symbol, and timeframe.

Administrative dataset ID and manifest creation time are excluded so rebuilding the same source manifest does not create false identity changes.

### Temporal split fingerprint

A split fingerprint binds:

- dataset content hash;
- train, validation, test, and holdout windows;
- minimum embargo.

All windows are half-open UTC intervals: `[start, end)`.

The split builder rejects:

- zero or negative windows;
- overlap or non-chronological order;
- insufficient embargo;
- boundaries not aligned to the candle timeframe;
- windows outside dataset coverage;
- train that does not begin at dataset start;
- holdout that does not end at dataset end.

This preserves an untouched final tail instead of allowing convenient omission around the holdout boundary.

### Experiment fingerprint

An experiment fingerprint includes:

- stable research lineage;
- strategy name and version;
- exact Git commit SHA;
- dataset manifest hash;
- temporal split fingerprint;
- train, validation, test, or holdout stage;
- random seed;
- cost-model version;
- execution-accounting version;
- parameters sorted by ordinal key.

Experiment ID and creation timestamp are excluded because they identify an execution record, not its reproducible configuration.

## Holdout consumption

A holdout-stage experiment must be authorized through `HoldoutAccessLedger`.

The ledger applies two independent locks for the same research lineage and holdout window:

1. **Content lock** — identical market content remains consumed even when its alias, provider, source identifier, or other provenance changes.
2. **Cohort lock** — the same market type, symbol, and timeframe remains consumed even when the data provider changes or market content is edited, refreshed, or replaced.

Provider is deliberately excluded from cohort identity. Changing a vendor label or switching to another feed for the same evaluation universe cannot reset the final holdout.

The first final experiment is authorized. Replaying the identical experiment is idempotent. A different fingerprint under either consumed scope is rejected as retuning against holdout data.

A new authorization requires both different content and a genuinely different market type, symbol, timeframe, or holdout window. Stable lineage governance and durable receipt persistence will be added before the laboratory exposes holdout execution through an API.

## Dataset validation

The builder rejects:

- empty datasets;
- invalid OHLCV relationships;
- mixed symbol or timeframe;
- duplicate, unordered, or missing candles;
- invalid, duplicate, unordered, mixed-symbol, or out-of-coverage funding points;
- incomplete provenance.

Missing candles are not silently interpolated by the research domain. A later ingestion layer must recover them from an official source and rebuild the manifest.

## Immutability and rehydration

Dataset manifests, temporal split plans, and experiment manifests have non-public constructors. They can only be created through validating builders.

Persisted holdout receipts are rehydrated by recomputing their scope identity and rejecting duplicate or inconsistent snapshots.

## Current limitations

This slice does not yet:

- execute a strategy;
- calculate returns or risk metrics;
- perform walk-forward analysis;
- model costs, latency, liquidity, or partial fills in a backtest;
- persist manifests or holdout receipts in PostgreSQL;
- cryptographically sign manifests against a malicious database administrator;
- enforce research-lineage ownership through authentication.

Those capabilities build on this trust boundary. No backtest or holdout result enables paper or live trading by itself, and live trading remains unavailable.

