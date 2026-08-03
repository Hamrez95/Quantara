# Changelog

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
