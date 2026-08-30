# Issue #360 — Windows management-only recovery physical QA

This checklist records owner-run evidence that cannot be established by repository CI alone. It does **not** grant new-entry authority and it must never be treated as proof that live trading is generally enabled.

## Preconditions

- Build comes from the exact reviewed commit under test.
- Windows installer/signature evidence is captured for that build.
- Bitunix credentials are trade-only and stored through the Windows-protected credential path.
- Any exchange position used for management testing is intentionally tiny-risk and already protected by exchange-native stop-loss and the expected take-profit ladder.
- No test begins from an ambiguous/external position and then assumes Quantara ownership.

## Required evidence

Record date/time, exact commit SHA, installer version, operator, and links/screenshots/logs for every item. Mark an item `PASS` only after observing the expected fail-closed state.

- [ ] **Signed install:** install completes; `QuantaraExecutionService` is registered against the packaged executable and remains stopped after installation.
- [ ] **First service start:** service starts `disarmed`; authenticated status reports no entry authority before fresh exchange reconciliation.
- [ ] **Reboot:** after Windows reboot, the service starts disarmed and does not silently re-arm or create a position.
- [ ] **Sleep/resume:** resume revokes/requires fresh reconciliation before management-only state can be republished.
- [ ] **Network loss/restore:** disconnect blocks opening risk; restore requires fresh exchange truth before any verified-existing-position management state.
- [ ] **Verified existing position:** only a position with durable Quantara ownership evidence and complete exchange-native protection can reach `manageExistingOnly`.
- [ ] **External/ambiguous position:** remains unmanaged/reconciliation-required and never gains local mutation authority.
- [ ] **Management close:** explicit close affects only the exact verified `positionId`, is reduce-only, and success is reported only after fresh exchange truth confirms the outcome.
- [ ] **Update:** installer stops the old service before replacement; the replacement remains stopped until an explicit later start and starts disarmed.
- [ ] **Failed update / rollback:** failure does not restore trading authority automatically; the recovered service starts disarmed and requires fresh reconciliation.
- [ ] **Uninstall:** service is stopped and removed; no background execution host remains registered.
- [ ] **Tiny-risk canary:** owner explicitly performs the final restricted-live canary only after every prior item passes and records exchange-side evidence.

## Evidence that remains invalid

Do not record any of the following as a pass:

- CI simulation standing in for reboot, sleep/resume, signed-install, or real network-loss evidence.
- Exchange ACK standing in for reconciled exchange truth.
- UI state standing in for durable Quantara ownership evidence.
- A successful management-only recovery standing in for permission to open new positions.
- Missing evidence inferred from logs, screenshots, or a previous release.

## Completion rule

Repository software work may merge while this checklist is pending. Issue #360 physical acceptance is complete only when every applicable item above has real owner-run evidence attached to the issue/release record. Until then, keep the physical QA status explicit as **Pending**.
