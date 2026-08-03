# Quantara native Windows architecture

Status: Release Candidate foundation. Windows is a native Flutter desktop build, not a WebView or PWA wrapper.

## Current RC boundary

The RC package contains the foreground Quantara cockpit and public realtime monitoring while the application is open. It does not install a background execution worker and does not auto-arm trading after launch, update, reboot or crash recovery.

## Build and package

`scripts/build-windows.ps1 -Configuration Release -GenerateRunner -PackageZip`:

1. enables Flutter Windows desktop;
2. generates the native runner when it is absent;
3. runs canonical format, strict analyzer and the full Flutter test suite;
4. compiles the x64 Release bundle;
5. packages a ZIP suitable for internal RC testing.

The Windows GitHub workflow runs this sequence on `windows-latest` and uploads the ZIP as an artifact.

## Security boundary

- Public realtime data remains separate from private exchange and order authority.
- API secrets are never generated, copied or logged by the Windows build.
- Local Live stays disarmed on launch and persisted settings cannot restore armed/running state.
- The unsigned ZIP is for internal testing only; stable distribution requires code signing and installer upgrade testing.

## Stable-release gates

Before a signed Windows Stable release:

1. clean install and in-place upgrade;
2. keyboard navigation and text scaling;
3. sleep/hibernate and network-loss recovery;
4. tray/minimize behavior;
5. signed installer and SmartScreen publisher validation;
6. rollback and local-data recovery documentation.
