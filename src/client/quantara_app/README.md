# Quantara Flutter client

The Quantara client is a shared Flutter application for Android, iOS, and web/PWA.

Version 0.2.0 is an offline-first stable demo/read-only cockpit. It uses deterministic demo data by default and can consume the versioned Quantara cockpit API when an origin is provided at build time.

## Current experience

- Persian right-to-left interface with English-ready strings.
- Light and dark themes.
- Phone bottom navigation and desktop side navigation.
- Clearly labelled demo environment.
- Market watchlist with simulated freshness and spread values.
- Deterministic candlestick charts and explainable price zones for four intervals.
- Strict read-only API parsing with timeout, freshness, schema, numeric, and safety validation.
- Explicit deterministic fallback for unavailable API transport.
- Explainable analysis with a first-class `NO_TRADE` outcome.
- Paper-account summary and daily-risk usage.
- Explicitly locked real-money capability.

No credential entry, exchange submission, withdrawal, or real-money control exists in this client.

## Run locally

From `src/client/quantara_app`:

```bash
flutter pub get
flutter run -d chrome
```

To run on a connected Android device or emulator:

```bash
flutter devices
flutter run -d <device-id>
```

To connect the read-only API during development:

```bash
flutter run -d chrome \
  --dart-define=QUANTARA_API_BASE_URL=http://localhost:5081
```

Release builds accept HTTPS API origins only. Android permits cleartext traffic solely in the debug manifest for loopback and emulator development.

## Quality checks

```bash
dart format --output=none --set-exit-if-changed lib test
flutter analyze --fatal-infos
flutter test
flutter build web --release
flutter build apk --release
```

GitHub Actions runs these checks for every relevant pull request. The repository's existing backend checks run independently on the same change.

## Architecture boundary

Presentation code depends on `CockpitRepository`. `MockCockpitRepository` is the deterministic offline implementation; `ApiCockpitRepository` validates the read-only HTTP contract. `FallbackCockpitRepository` falls back only for transport/service failures and never hides malformed or unsafe API data.

See `docs/product/flutter-cockpit-foundation.md` for the cross-functional product and engineering decisions.
