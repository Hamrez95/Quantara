# Changelog

## 1.2.0-rc.2 — 2026-08-03

### Physical Samsung canary fixes

- Fixed a malformed Bitunix OHLC row in `AVAXUSDT|15m` aborting the entire realtime bootstrap and leaving health at `0/0`.
- Recent-history decoding now drops only a strictly bounded number of malformed rows and never coerces invalid prices into analysis.
- Failed symbol/timeframe streams are quarantined while healthy streams continue; startup still fails closed when every configured stream fails.
- Health now reports healthy/configured streams, quarantined stream count and degraded-live status.
- Reduced production bootstrap history to 120 closed candles, leaving reserve capacity in the bounded 200-row REST response.
- Added an explicit `Resume entries` action when Local Live is managing-only with zero open positions.
- Resume never occurs automatically and repeats account preflight plus every real-money confirmation; managing-only with an open protected position remains non-resumable.
- Added regressions for malformed AVAX history, malformed-row budget exhaustion, one-stream isolation, all-stream failure and explicit zero-position entry rearm.

### Safety

- No malformed market value is repaired or inferred.
- No private API permission, order sizing, leverage/risk bound, withdrawal/transfer capability or automatic trading authority was expanded.

## 1.2.0-rc.1 — 2026-08-03

### Realtime public market pipeline

- Added the audited `REST bootstrap → working candle → rollover → closed candle → gap detection → REST reconciliation → bounded event bus` pipeline.
- Added the public Bitunix WebSocket transport with deterministic sharding, reconnect/backoff, heartbeat, malformed-payload budget and explicit public-endpoint enforcement.
- Added bounded full-stream snapshots for strategy analysis and fail-closed handling while candle truth is uncertain.
- Added production foreground composition for up to 12 symbols across 5m, 15m, 1h and 4h.
- Added stream/shard health, reconnect/fault counts and p95 transport/processing latency to the application UI.

### Signals, Journal and trade management

- Added durable candidate audit before commit and projection.
- Added Signal Inbox organization, persisted setup metadata and mirrored hypothetical/user outcomes.
- Added guarded 5m Local Live settings without restoring armed or running state after restart.
- Added localized safe-skip execution reasons and versioned regime-aware profit-protection rules.
- Added durable Journal projection and recovery through the existing opportunity state store.

### Platforms and release engineering

- Added native Flutter Windows build and ZIP packaging on `windows-latest`.
- Added Android universal and arm64 APK artifacts, 16 KB ZIP-alignment verification and API 34/35/36 cold-start smoke tests.
- Added PWA release-bundle validation and offline-first build.
- Upgraded the client to Flutter 3.44.8 and Dart 3.12.2 validation gates.

### Safety

- Public realtime data remains isolated from private exchange and order authority.
- Withdrawal, transfer, cross margin, martingale, averaging down, duplicate entry and stop widening remain prohibited.
- Stable publication remains blocked until physical-device, upgrade and permanent-signing validation is complete.
