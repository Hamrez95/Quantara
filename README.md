# Quantara

Quantara is a safety-first crypto market analysis, signal monitoring and guarded automation platform. The monorepo contains a .NET backend, PostgreSQL/Redis infrastructure, a Flutter Android and web/PWA cockpit, and deterministic research/risk components.

## Quantara 1.0 scope

The 1.0 source candidate provides:

- real public Bitunix Futures prices and closed-candle analysis;
- watchlist scanning on 15m, 1h and 4h with explicit wait/rejection reasons;
- explainable setups with Entry, SL, TP1/TP2/TP3 and leverage-aware risk sizing;
- Signal Inbox and hypothetical outcome tracking for taken and untaken suggestions;
- exact symbol/timeframe setup navigation and frozen chart overlays;
- Strategy Lab historical replay and forward-paper monitoring;
- Persian/English, RTL/LTR and light/dark themes;
- Android Preview and web/PWA builds;
- optional Bitunix account connection and **Guarded Local Live Canary** behind an explicit Start action.

The analysis, monitoring and paper features are the Stable 1.0 product surface. Local real execution remains an explicit opt-in Canary: it is restricted to hard safety limits, may stop when Android or connectivity stops the local service, and is never described as unattended or guaranteed. Server Auto remains visible but locked. Withdrawals, transfers, martingale, averaging down, stop widening and unrestricted multi-position execution are not supported.

## Android identities and upgrades

Internal Preview builds use `com.quantara.quantara_app.alpha` so they can coexist with Stable. Public Stable builds use `com.quantara.quantara_app` and require the permanent owner-managed signing key. Stable signing fails closed when its protected inputs are absent.

The first move from an old Preview to Stable is a one-time clean migration because earlier candidates used a different package/signing identity. Before removing Preview, use **Profile > Settings backup** to copy the watchlist and non-sensitive risk preferences, then restore them after installing Stable. API credentials are intentionally excluded. Once Stable 1.0 is installed, future Stable APKs use the same package ID and signing key and can update in place without clearing app data.

See [`docs/releases/v1.0.0.fa.md`](docs/releases/v1.0.0.fa.md).

## PWA on Windows / VS Code

From the repository root:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Run-QuantaraPwa.ps1
```

This runs the app in Chrome development mode. To build and serve the Release PWA locally:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Run-QuantaraPwa.ps1 -ReleasePreview
```

Then open `http://localhost:8080`. Full Persian instructions are in [`docs/guides/pwa-windows-vscode.fa.md`](docs/guides/pwa-windows-vscode.fa.md).

## Quality policy

A successful build or a strong backtest does not prove profitability. Strategy candidates must pass chronological out-of-sample, walk-forward, realistic-cost, regime, stability, paper and shadow gates before broader execution can be considered. Win rate is reported beside expectancy, drawdown, profit factor, uncertainty and sample size; it is never guaranteed or used alone.

Key documents:

- [`docs/product-scope.md`](docs/product-scope.md)
- [`docs/architecture.md`](docs/architecture.md)
- [`docs/quality-gates.md`](docs/quality-gates.md)
- [`docs/branching-and-release.md`](docs/branching-and-release.md)
- [`docs/risk-engine.md`](docs/risk-engine.md)
- [`docs/order-state-machine.md`](docs/order-state-machine.md)
- [`docs/threat-model.md`](docs/threat-model.md)
- [`docs/releases/v1.0.0.fa.md`](docs/releases/v1.0.0.fa.md)
- [`docs/releases/local-release-builder.md`](docs/releases/local-release-builder.md)

## Local validation

With the pinned .NET 8 SDK, Python 3 and Docker Compose installed:

```bash
dotnet restore Quantara.sln
dotnet format whitespace Quantara.sln --verify-no-changes --no-restore
dotnet build Quantara.sln --configuration Release --no-restore
dotnet test Quantara.sln --configuration Release --no-build
python3 scripts/validate-milestone1.py
docker compose config --quiet
```

Flutter validation runs from `src/client/quantara_app`:

```bash
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze --fatal-infos
flutter test
flutter build web --release
flutter build apk --release
```

Public market analysis uses documented HTTPS endpoints and requires no API key. Malformed, stale or unavailable market data fails closed. Private Bitunix credentials, when explicitly configured for the Android Canary, remain in platform Secure Storage and are not written to ordinary logs, backups or source control.
