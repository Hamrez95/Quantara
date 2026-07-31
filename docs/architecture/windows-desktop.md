# Quantara native Windows architecture

Status: foundation draft for issue #80. This does not enable Windows live execution yet.

## Product boundary

The Windows product is a native Flutter desktop application, not a WebView or PWA wrapper. The distributable target is `QuantaraSetup.exe`, which installs:

- `Quantara.exe` for the desktop cockpit;
- a supervised local execution worker for scanning, risk reservation, Bitunix execution and reconciliation;
- a tray process/control surface;
- Start Menu and optional Desktop shortcuts;
- an uninstaller that stops the worker and offers an explicit local-data removal choice.

## Process model

```text
Quantara.exe (UI)
    |
    | authenticated local IPC only
    v
Quantara.Execution.Worker
    |
    | HTTPS + signed Bitunix requests
    v
Bitunix
```

The UI may close or minimize without silently terminating management of an already protected position. The worker must never expose an unauthenticated LAN endpoint.

## Shared execution contract

Android and Windows must share the same platform-neutral contracts for:

- dynamic portfolio risk budgeting;
- execution mode (`READ_ONLY`, `APPROVAL_REQUIRED`, `GUARDED_AUTO`);
- idempotent client order identifiers;
- partial-fill cancellation and reduce-only cleanup;
- exchange-confirmed full stop and staged targets;
- reconciliation, circuit breaking and audit events.

Platform adapters own only lifecycle, secure storage, notifications/tray and IPC.

## Security

- API keys are read/trade only; withdrawal and transfer permissions are prohibited.
- Secrets are protected with Windows credentials/DPAPI and never written to plaintext config, logs or crash reports.
- The installer and updater verify publisher identity and SHA-256 before replacement.
- Updating never auto-arms trading.

## Reliability gates

Before a Windows build is promoted from Canary:

1. cold launch and clean install on supported Windows versions;
2. in-place upgrade preserving settings and secure credentials;
3. UI close/minimize policy and tray behavior;
4. service restart, reboot and network-loss recovery;
5. sleep/hibernate warning and reconciliation;
6. stale signal, duplicate order, partial fill and missing-stop fault tests;
7. tiny-balance physical Bitunix canary;
8. signed installer and rollback evidence.

## Delivery phases

1. **Build foundation:** generate/commit Windows runner, compile in CI and package unsigned internal ZIP.
2. **Desktop cockpit:** responsive workspace, keyboard/mouse navigation, native notifications and tray shell.
3. **Execution worker:** extract Android foreground-task assumptions behind a platform-neutral coordinator.
4. **Installer:** branded Inno Setup package with stable application identity and upgrade path.
5. **Signing and canary:** code signing, SmartScreen reputation plan, physical tests and guarded release.
