# Owner Alpha client performance evidence — issue #543

Date: 2026-09-24

## Evidence boundary

This document records reproducible software/CI evidence for the Owner Alpha client performance pass. It does **not** claim physical Samsung-device battery, thermal, network, signing, exchange-side, or profitability evidence. Those remain separate manual/release gates.

## Baseline

Baseline before the #543 implementation slices:

- source: `8dcdbe033ee05deed520e11d241b08f1a352542f`
- Flutter CI: run `35963846912`
- baseline diagnostics artifact: `10793576321`
- synthetic hot-path combined elapsed: `577036 µs`
- process RSS: `167657472 -> 210083840` bytes (about 40.46 MiB growth)
- Android emulator cold-start totals:
  - API 34: `4423 ms`
  - API 35: `5719 ms`
  - API 36: `7740 ms`

## Before / after evidence

### 1. Startup dependency fan-out

Before #550, `OwnerAlphaPage.initState` immediately started five controller/service paths: core Owner Alpha, Trading Lab, private account truth, Unattended Auto, and Journal.

After #550, only core Owner Alpha and private account truth start immediately. Trading Lab, Unattended Auto, and Journal initialize on first destination use. This reduces immediate controller/service initialization calls from 5 to 2 (60%) while intentionally keeping account truth eager for Setup/manual-trade safety.

Cold-start emulator evidence after the lazy-init + inbox work (#551 candidate, Flutter CI run `36009753066`):

| API | Baseline | Candidate | Change |
| --- | ---: | ---: | ---: |
| 34 | 4423 ms | 4102 ms | -7.3% |
| 35 | 5719 ms | 4482 ms | -21.6% |
| 36 | 7740 ms | 7954 ms | +2.8% |
| Mean | 5961 ms | 5513 ms | -7.5% |

The matrix is emulator/CI evidence and is noisy: API 36 regressed slightly, so this is not presented as a uniform startup speedup.

### 2. Setup Inbox eager construction

Before #551, the filtered Signal Inbox expanded every result into a `_SignalJournalCard` in a `Column`. An 82-entry journal therefore constructed all 82 heavy card subtrees eagerly.

After #551:

- Setup Inbox owns a `CustomScrollView`;
- cards are provided by `SliverChildBuilderDelegate`;
- `childCount` still exposes the complete filtered result set;
- deterministic regression coverage creates 82 entries, proves the first viewport materializes only a subset, then scrolls and proves a different subset materializes;
- report/journal work remains deferred until Performance Report is opened;
- manual Open Trade and RTL/LTR/responsive behavior remain covered.

#551 certification:
- CI `36009752623`: PASS
- PWA `36009752786`: PASS
- Flutter + Android API 34/35/36 `36009753066`: PASS
- Windows `36009753028`: PASS
- Android diagnostics artifacts: `10812482952`, `10812537913`, `10813295548`
- Windows candidate artifact: `10812742596`

### 3. Duplicate scan and idle rebuild work

#553 coalesces concurrent pure manual refreshes onto the active scan future. Selection/settings mutations still wait and execute with their original semantics. The regression test verifies concurrent manual refreshes do not create an additional repository scan.

#555 suppresses identical `RealtimeMarketMonitorSnapshot` publications. Its deterministic test polls every 250 ms, observes one initial notification across 620 ms of unchanged health, then observes exactly one additional notification after a real event counter changes. Degraded-recovery checks still execute every poll.

A same-workload software benchmark after #553/#555:
- source: `e0fa7a7e2390f41711c06b52601b505203005cb9`
- Flutter CI: run `36006111444`
- diagnostics artifact: `10809669501`
- combined elapsed: `474858 µs` versus baseline `577036 µs` (about 17.7% lower)
- process RSS growth: about 40.41 MiB versus baseline 40.46 MiB (effectively flat)

This benchmark improvement is evidence for the CI synthetic workload/runner class only, not a physical-device claim.

## Rebuild boundaries

#552 limits Journal-derived radar map construction to destination 6 (Journal).

#554 removes the broad Signal Inbox listener that previously called whole-view `setState` on account-state changes. Only the Open Trade availability/block-reason surface listens to account state, while all existing fail-closed preflight checks remain authoritative.

## Safety invariants preserved

Performance changes do not:

- treat stale market/account data as fresh;
- skip Bitunix reconciliation, protection, PnL, or risk readiness checks;
- introduce automatic trade entry/resume;
- change setup trading decisions to improve UI timing;
- weaken closed-candle or exchange-truth requirements.

## Remaining evidence boundary

Long-duration physical-device battery/thermal/network-idle and 5/15/30-minute physical memory observations are not inferred from CI. They remain part of the explicit physical-device release gate, not a fabricated software PASS.
