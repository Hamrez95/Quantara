# Quantara native Windows architecture

Status: Release Candidate foundation. Windows is a native Flutter desktop build, not a WebView or PWA wrapper.

## Current RC boundary

The RC package contains the foreground Quantara cockpit and public realtime monitoring. A dedicated Windows Service host is packaged and registered as `QuantaraExecutionService`. The service currently owns **zero trading authority**: no exchange execution engine is wired into it, no IPC request can mutate trading state, and every service start begins disarmed. Install/update never silently starts or arms it.

The service boundary now includes a kernel-authenticated local named pipe for versioned **read-only status** IPC, bounded request replay rejection, a Windows DPAPI credential-vault primitive with protected ACLs, deterministic SCM stop/shutdown handling, fail-closed power transitions, and network-interface change monitoring. These foundations do not themselves grant order authority or provision exchange credentials.

Suspend moves the service into an interrupted state. Resume and any network-interface change require reconciliation rather than restoring prior authority. Repeated recovery events are idempotently fail-closed.

## Build and package

`scripts/build-windows.ps1 -Configuration Release -GenerateRunner -PackageZip`:

1. enables Flutter Windows desktop;
2. generates the native runner when it is absent;
3. runs canonical format, strict analyzer and the full Flutter test suite;
4. compiles the x64 Release bundle;
5. packages a ZIP suitable for internal RC testing.

`scripts/build-windows-service.ps1 -Configuration Release` separately builds `quantara_windows_service.exe` with the pinned Windows C++ toolchain and executes bounded native self-tests for the service host, credential vault, read-only response/session/listener contracts and network-change recovery.

The Windows GitHub workflow builds both targets, exercises service registration/removal against the Windows Service Control Manager, compiles the Inno Setup installer and uploads the internal RC artifacts. The SCM smoke verifies that installation leaves the service stopped/disarmed and that uninstall removes the registration.

## Installation and service lifecycle

- The installer stops an existing `QuantaraExecutionService` before replacing its executable; failure to stop cancels the update rather than overwriting a running host.
- Installation registers one stable service identity with automatic boot startup, but does not start it during install/update.
- A later boot may start the service, and the service itself always initializes disarmed.
- Uninstall stops and removes the service before installed files are removed.
- The local status pipe authenticates the connected Windows peer before reading a bounded message and only accepts the versioned read-only request allowlist.
- Duplicate request IDs are rejected within a bounded replay window.
- The DPAPI vault is only a protected-storage primitive; authenticated credential provisioning and execution-engine ownership remain separate future gates.

## Security boundary

- Public realtime data remains separate from private exchange and order authority.
- API secrets are never generated, copied or logged by the Windows build or installer.
- Local Live stays disarmed on launch and persisted settings cannot restore armed/running state.
- The Windows Service currently cannot submit, cancel or manage exchange orders because no protected executor is attached to it.
- Read-only IPC does not expose an unauthenticated LAN endpoint and does not accept mutating command kinds.
- Network/power lifecycle changes never restore authority; they downgrade trust and require reconciliation.
- The unsigned installer/ZIP is for internal testing only; stable distribution requires code signing and physical upgrade validation.

## Stable-release gates

Before a signed Windows Stable release:

1. clean install and in-place upgrade with retained local settings/secure credentials;
2. authenticated credential provisioning plus explicit platform-neutral execution-engine wiring through deterministic Risk/Allocation/Autonomy gates;
3. native tray/minimize controls with no hidden authority escalation;
4. keyboard navigation and text scaling;
5. physical reboot/service-restart/sleep/hibernate/network-switch recovery evidence;
6. signed installer and SmartScreen publisher validation;
7. rollback and local-data recovery documentation/evidence;
8. physical Windows canary with tiny balance before any live-ready claim.
