# Quantara Flutter client

The Quantara client is a shared Flutter application for Android, iOS, and web/PWA.

This first product slice is intentionally backed by deterministic demo data. It proves the visual system, responsive layout, accessibility states, and client-facing contracts before read-only market and durable paper-account APIs are connected.

## Current experience

- Persian right-to-left interface with English-ready strings.
- Light and dark themes.
- Phone bottom navigation and desktop side navigation.
- Clearly labelled demo environment.
- Market watchlist with simulated freshness and spread values.
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

## Quality checks

```bash
dart format --output=none --set-exit-if-changed lib test
flutter analyze --fatal-infos
flutter test
flutter build web --release
flutter build apk --debug
```

GitHub Actions runs these checks for every relevant pull request. The repository's existing backend checks run independently on the same change.

## Architecture boundary

Presentation code depends on `CockpitRepository`. `MockCockpitRepository` is the current deterministic implementation. Future API-backed repositories must preserve the same safety distinctions between demo, paper, shadow, and real-money-locked states.

See `docs/product/flutter-cockpit-foundation.md` for the cross-functional product and engineering decisions.
