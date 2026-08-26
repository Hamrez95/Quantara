# Quantara native Windows architecture

Status: Release Candidate foundation. Windows is a native Flutter desktop build, not a WebView or PWA wrapper.

## Current RC boundary

The RC package contains the foreground Quantara cockpit and public realtime monitoring. A dedicated Windows Service host is packaged and registered as `QuantaraExecutionService`, but the service currently owns **zero trading authority**: it has no exchange credentials, execution-engine wiring or authenticated application IPC yet. Every service start begins disarmed, and install/update never silently starts or arms it.

The service host exists to establish the native lifecycle boundary safely before execution capabilities are attached. Stop, shutdown, suspend and resume are handled fail-closed; resume requires reconciliation rather than restoring prior authority.

## Build and package

`scripts/build-windows.ps1 -Configuration Release -GenerateRunner -PackageZip`:

1. enables Flutter Windows desktop;
2. generates the native runner when it is absent;
3. runs canonical format, strict analyzer and the full Flutter test suite;
4. compiles the x64 Release bundle;
5. packages a ZIP suitable for internal RC testing.

`scripts/build-windows-service.ps1 -Configuration Release` separately builds `quantara_windows_service.exe` with the pinned Windows C++ toolchain and executes its fail-closed native self-test.

The Windows GitHub workflow builds both targets, exercises service registration/removal against the Windows Service Control Manager, compiles the Inno Setup installer and uploads the internal RC artifacts. The SCM smoke verifies that installation leaves the service stopped/disarmed and that uninstall removes the registration.

## Installation and service lifecycle

- The installer stops an existing `QuantaraExecutionService` before replacing its executable; failure to stop cancels the update rather than overwriting a running host.
- Installation registers one stable service identity with automatic boot startup, but does not start it during install/update.
- A later boot may start the service, and the service itself always initializes disarmed.
- Uninstall stops and removes the service before installed files are removed.
- Authenticated local IPC, Windows-protected trading credentials, tray controls and execution-engine ownership remain follow-up gates; none are implied by the service registration.

## Security boundary

- Public realtime data remains separate from private exchange and order authority.
- API secrets are never generated, copied or logged by the Windows build or installer.
- Local Live stays disarmed on launch and persisted settings cannot restore armed/running state.
- The service host cannot currently submit or manage exchange orders because no execution authority or exchange credentials are attached to it.
- The unsigned installer/ZIP is for internal testing only; stable distribution requires code signing and physical upgrade validation.

## Stable-release gates

Before a signed Windows Stable release:

1. clean install and in-place upgrade;
2. authenticated local IPC and Windows-protected credentials before private execution wiring;
3. keyboard navigation and text scaling;
4. sleep/hibernate and network-loss recovery;
5. tray/minimize behavior;
6. signed installer and SmartScreen publisher validation;
7. rollback and local-data recovery documentation;
8. physical Windows canary with tiny balance before any live-ready claim.
