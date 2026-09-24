# Source registry review — 2026-09-24

Issue: #545

## Scope

This is the scheduled monthly legal/access-sensitive review required by
`docs/research/source-governance.md`. It does not grant trading authority,
approve copyrighted corpus ingestion, or certify legal/commercial reuse.

`execution_authority` remains `none`.

## Current-source checks

### YouTube API / creator metadata

Reviewed:
- https://developers.google.com/youtube/terms/api-services-terms-of-service
- https://developers.google.com/youtube/terms/developer-policies
- https://developers.google.com/youtube/terms/revision-history
- https://developers.google.com/youtube/v3/revision_history

Finding:
The September 2026 API documentation/revision changes do not justify widening
Quantara's source authority or retention boundary.

Decision:
- Keep Trade City Pro/creator material `hypothesis_only`.
- Keep metadata/citation use only.
- Keep automated scraping prohibited.
- No execution authority.

### CMT and book references

Reviewed the registered CMT learning-objectives page and the registered
Penguin/Wiley bibliographic pages for Murphy, López de Prado, and O'Hara.

Decision:
- Keep CMT as restricted/citation-only validation material.
- Keep books as bibliographic/copyrighted references only.
- No full-text, paid-curriculum, or corpus ingestion.

### TradingView

Reviewed:
- https://www.tradingview.com/policies/
- https://www.tradingview.com/support/solutions/43000562362-what-are-strategies-backtesting-and-forward-testing/

Finding:
Current TradingView policy still restricts non-display algorithmic use of its
market data/content.

Decision:
- Keep citation-only validation guidance.
- Do not use TradingView market data/content as automated decision or execution
  input.
- No scraping or undocumented endpoint use.

### FRED / ALFRED

Reviewed:
- https://fred.stlouisfed.org/docs/api/fred/overview.html
- https://fred.stlouisfed.org/docs/api/terms_of_use.html
- https://fred.stlouisfed.org/legal/terms/

Finding:
The restrictions that caused the August fail-closed decision remain material,
including restrictions relevant to machine-learning use and storage/caching of
FRED API content.

Decision:
- Keep `fred-alfred-api` disabled.
- Keep `blocked_pending_license`.
- Require a separate compatible usage/retention design and terms review before
  any re-enable.

### CFTC COT

Reviewed:
- https://www.cftc.gov/MarketReports/CommitmentsofTraders/index.htm
- https://www.cftc.gov/WebPolicy/index.htm

Decision:
Keep the existing official aggregate-fact role with publication/revision
controls and no identity inference.

### SEC EDGAR

Reviewed:
- https://www.sec.gov/search-filings/edgar-application-programming-interfaces
- https://www.sec.gov/about/privacy-information

Decision:
- Keep official API access subject to fair-access and provenance controls.
- Update the registry privacy URL to the current canonical destination.
- No source-authority expansion.

### Coin Metrics Community / Talos

Reviewed:
- https://docs.coinmetrics.io/api
- https://www.talos.com/legals/terms

Decision:
- Keep Community production-disabled.
- Keep `blocked_pending_license`.
- Require current compatible commercial terms before any enablement.

### Bitunix

Reviewed:
- https://www.bitunix.com/api-docs/futures/common/introduction.html
- https://www.bitunix.com/hub/helpcenter/article/bitunix-user-agreement?id=144
- https://www.bitunix.com/hub/helpcenter/article/risk-disclosure?id=149

Decision:
- Keep the official Bitunix API role and current terms links.
- Keep strict secret, reconciliation, and protected-execution boundaries.
- This registry review does not expand order authority and never permits
  withdrawals/transfers.

## Registry decision

- Registry version: `1.0.2`.
- Reviewed at: `2026-09-24`.
- Next review due: `2026-10-24`.
- FRED remains disabled.
- Coin Metrics Community remains disabled.
- SEC privacy URL is refreshed to its current canonical destination.
- All source roles remain subordinate to deterministic strategy, risk,
  allocation, protected execution, reconciliation, and Journal boundaries.

## Validation required before merge

- `python3 scripts/validate_source_registry.py`
- `python3 scripts/test_validate_source_registry.py`
- repository CI

No physical-device, live-trading, profitability, licensing, or legal
certification evidence is claimed by this review.
