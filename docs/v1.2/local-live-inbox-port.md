# Local Live and Signal Inbox port

This branch ports the validated Local Live persistence, guarded 5m mode, Signal Inbox organization and regime-aware profit-protection work from the superseded stacked preview branches onto the current `dev` line.

The current `dev` workflow, version and realtime infrastructure remain authoritative. The old stacked PRs are not merged directly.

## Port boundary

- The current Flutter 3.44.8 / Dart 3.12.2 workflow is retained.
- The release version remains owned by the later RC branch.
- Local Live armed/running state is never restored automatically.
- The port adds no withdrawal, transfer, cross-margin, martingale, averaging-down or stop-widening authority.
- Full format, analyzer, test, PWA, Android, manifest, alignment and API 34–36 gates must pass again on this history.
