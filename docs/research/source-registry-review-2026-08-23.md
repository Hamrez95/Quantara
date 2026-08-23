# Source registry review — 2026-08-23

Issue: #270

## Scope

This review renews the monthly legal/access-sensitive source review required by `docs/research/source-governance.md`. It does not grant trading authority, does not approve copyrighted corpus ingestion, and does not claim a source is commercially reusable merely because it is publicly reachable.

`execution_authority` remains `none`.

## Current-source checks

### YouTube API / Trade City Pro metadata

Reviewed:
- https://developers.google.com/youtube/terms/developer-policies
- https://developers.google.com/youtube/terms/revision-history
- https://developers.google.com/youtube/v3/revision_history

Decision:
- Keep creator material `hypothesis_only` / citation-oriented.
- Keep automated scraping prohibited.
- No execution authority.
- The 2026 YouTube policy/API revisions do not justify widening the registered role or retention boundary.

### CMT / books

The CMT entry remains a restricted/citation-only validation source. Book entries remain static bibliographic/copyrighted references only. No full-text ingestion, paid-curriculum ingestion, or corpus storage was approved in this review.

### TradingView

Reviewed:
- https://www.tradingview.com/policies/
- https://www.tradingview.com/support/solutions/43000562362-what-are-strategies-backtesting-and-forward-testing/

Decision:
- Keep TradingView as citation-only validation guidance.
- Do not use TradingView content or market data as non-display automated-trading input.
- No scraping, private-script copying, or undocumented endpoint use.

### FRED / ALFRED

Reviewed:
- https://fred.stlouisfed.org/docs/api/fred/overview.html
- https://fred.stlouisfed.org/docs/api/terms_of_use.html
- https://fred.stlouisfed.org/legal/terms/

Finding:
Current FRED terms are materially stricter than the registry assumptions that previously allowed retained API results and production enablement. The terms explicitly preserve third-party series restrictions and include restrictions on storing/caching/archiving FRED API content and specified machine-learning-related uses.

Decision:
- Fail closed: set `fred-alfred-api` to `enabled: false`.
- Change commercial status to `blocked_pending_license`.
- Remove production-retention assumptions from permitted uses.
- Require a separate compatible usage/retention design and terms review before re-enabling.

This is a conservative policy decision, not legal advice.

### CFTC COT

Reviewed:
- https://www.cftc.gov/MarketReports/CommitmentsofTraders/index.htm
- https://www.cftc.gov/WebPolicy/index.htm

Decision:
The current registry posture remains conservative: official aggregate facts, publication-lag/revision controls, acknowledgement, and no inference of individual identities.

### SEC EDGAR

Reviewed:
- https://www.sec.gov/search-filings/edgar-application-programming-interfaces
- https://www.sec.gov/about/developer-resources
- https://www.sec.gov/privacy.htm

Decision:
Keep official API access enabled subject to fair-access controls, efficient requests, identifying user-agent requirements where applicable, immutable filing/accession provenance, and no future-data leakage.

### Coin Metrics Community / Talos

Reviewed:
- https://docs.coinmetrics.io/api
- https://docs.coinmetrics.io/api/v4/
- https://www.talos.com/our-solutions/data/community-resources
- https://www.talos.com/legals/terms

Finding:
Coin Metrics is now presented under Talos. Community API documentation still describes Community data as free for non-commercial use, while the legacy Coin Metrics terms URL now redirects into Talos properties.

Decision:
- Keep `coinmetrics-community-api` production-disabled.
- Keep `blocked_pending_license`.
- Update the registry terms link to the current Talos legal landing page.
- Require review of the current Coin Metrics Master Terms before any enablement.

### Bitunix

Reviewed:
- https://www.bitunix.com/api-docs/futures/common/introduction.html
- https://www.bitunix.com/api-docs/futures/market/get_depth.html
- https://www.bitunix.com/hub/helpcenter/article/bitunix-user-agreement?id=144
- https://www.bitunix.com/hub/helpcenter/article/risk-disclosure?id=149

Finding:
The Bitunix User Agreement was updated after the previous registry review. Current OpenAPI documentation still explicitly separates unauthenticated public market-data interfaces from signed private account/order interfaces.

Decision:
- Refresh terms links to the current User Agreement and Risk Disclosure.
- Keep the existing API source role and strict secret/reconciliation controls.
- This registry review does not expand Quantara order authority or enable withdrawals/transfers.

## Registry decision

- Registry version: `1.0.1`.
- Reviewed at: `2026-08-23`.
- Next review due: `2026-09-23`.
- FRED: disabled pending a compatible terms/licensing design.
- Coin Metrics Community: remains disabled/non-commercial.
- Bitunix terms links refreshed.
- All source roles remain subordinate to deterministic strategy, risk, allocation, autonomy, execution-protection, reconciliation, and journal boundaries.

## Validation required before merge

- `python3 scripts/validate_source_registry.py`
- `python3 scripts/test_validate_source_registry.py`
- repository CI

No physical-device, live-trading, profitability, licensing, or legal-certification evidence is claimed by this review.
