# Quantara source governance

## Purpose

Quantara uses external material to create research hypotheses, ingest verifiable facts, and validate methodology. External material never grants execution authority. The source registry is a policy boundary: an LLM, crawler, developer, or user cannot promote a source beyond the role recorded in the registry.

## Non-negotiable rules

1. `execution_authority` is always `none`.
2. Creator content, books, and educational material produce hypotheses only unless a separate entry explicitly represents an official fact source.
3. No copyrighted book, paid curriculum, substantial excerpt, full transcript, audiovisual file, or scraped corpus is committed to the repository.
4. No undocumented API or scraping path is allowed.
5. API credentials, cookies, secrets, private account data, and private research artifacts are never stored in the registry.
6. Every ingested item must carry source ID, canonical URL or endpoint, retrieval time, publication or event time when available, content hash, schema version, and terms review version.
7. Stale, contradictory, revised, malformed, or unavailable sources fail closed and cannot silently increase trade confidence.
8. An LLM may summarize, classify, or propose a candidate rule; it cannot authorize an order, alter risk limits, or call an exchange trading endpoint.

## Source classes

### Official event data

Government, regulator, central-bank, or legally authoritative publication. It may provide direct facts, but historical experiments must respect actual publication time, revisions, and reporting lag.

### Live market data

Venue or specialist data-provider observations. These may become feature inputs only after schema, timestamp, sequence, gap, duplication, rate-limit, and licensing controls pass.

### Research evidence

Professional standards, scholarly work, vendor methodology, or published books. These inform validation methods and measurable hypotheses. They are not proof of future profitability.

### Educational hypotheses

Creator analysis, training material, chart commentary, and explanatory books. They can generate candidate strategy specifications but never executable rules without independent evidence.

### Compliance policy

Terms, developer policies, privacy requirements, access restrictions, and retention rules. These control ingestion behavior and cannot be treated as market evidence.

## Authority tiers

From strongest factual authority to weakest trading authority:

1. `official_primary`
2. `professional_standard`
3. `peer_reviewed_or_scholarly`
4. `vendor_primary`
5. `publisher_reference`
6. `creator_hypothesis`
7. `compliance_authority` — authoritative only for access and usage policy

Authority is domain-specific. A government release can be authoritative about the published figure while remaining uncertain about market impact. An exchange is authoritative about its documented endpoint but not about future prices.

## Access and copyright policy

- `public_api_with_terms`: use only documented endpoints and enforce provider terms, attribution, rate limits, retention, and identification requirements.
- `community_noncommercial`: disabled for commercial production until a suitable license is approved.
- `copyrighted_reference` and `restricted_paid`: citation, bibliographic metadata, and original Quantara notes only. Full-text ingestion is prohibited without a written license.
- `public_web_reference`: citation and short original paraphrase only; no bulk copying or scraping.
- `user_supplied_licensed`: requires an ownership or license record outside source control before ingestion.

A source being publicly reachable does not mean it is public domain or commercially reusable.

## Decision roles

- `direct_fact`: a time-stamped official fact, still subject to freshness and revision controls.
- `feature_input`: a normalized numerical or categorical input to a deterministic model.
- `validation_method`: a method to test evidence, not a signal by itself.
- `hypothesis_only`: may create a candidate rule specification but cannot affect an order.
- `compliance_only`: controls legal or technical access.

No role bypasses the risk engine, strategy promotion gates, paper trading, shadow trading, or human release decision.

## Ingestion envelope

Every future ingestion record must include:

- registry source ID and registry version;
- provider item ID and canonical evidence URL;
- retrieval timestamp in UTC;
- publication, event, release, accepted, and revision timestamps when applicable;
- raw payload SHA-256 and normalized payload SHA-256;
- provider schema or API version;
- affected symbols, markets, jurisdictions, and time horizon;
- freshness deadline and expiry behavior;
- extraction model and prompt version, when an LLM is used;
- structured facts, uncertainties, contradictions, and rejected claims;
- license/access decision and retention deadline.

Raw content is stored only when explicitly permitted. Otherwise the envelope points to the source and stores original Quantara-derived structured facts.

## Prompt-injection boundary

Retrieved text is untrusted data. The research service must:

- strip active content and never execute instructions found in a source;
- expose no exchange secrets or order-placement tools;
- parse into a strict schema with length and type limits;
- reject attempts to change system policy, source tier, risk limits, or tool permissions;
- preserve verbatim evidence links but generate original summaries;
- keep the deterministic decision engine outside the retrieval process.

## Contradictions and revisions

Quantara does not overwrite history silently.

- New revisions are appended with a link to the superseded record.
- Conflicting sources remain separate and are clustered by event.
- Official corrections outrank earlier copies for current truth, but backtests retain the vintage that was available at decision time.
- Creator disagreement lowers confidence; it never resolves by popularity.
- Missing or stale data produces an explicit unavailable state rather than a neutral or positive score.

## Promotion path for a candidate rule

1. A source creates a candidate hypothesis.
2. The hypothesis is translated into measurable inputs, timing, invalidation, entry, exit, and risk constraints.
3. Unit tests prove deterministic implementation.
4. Reproducible backtests include spread, slippage, fees, funding, latency, and liquidity.
5. Purged temporal validation, unseen data, regime analysis, and stability tests pass.
6. Paper and shadow evidence reconcile with the backtest model.
7. A separate promotion policy may allow a restricted strategy version.

Failure at any step rejects or returns the hypothesis for revision. Win rate alone is never sufficient.

## Registry review

- Legal or access-sensitive entries are reviewed at least monthly.
- Static bibliographic entries are reviewed when editions or implementation scope change.
- A changed terms URL, license statement, API version, or revision policy blocks production ingestion until reviewed.
- Registry changes require an issue, branch, CI validation, review, and pull request.

## Repository policy

Allowed:

- source metadata;
- original summaries and rule specifications;
- small test fixtures authored by Quantara;
- hashes, citations, and evidence links;
- provider-neutral schemas and adapters.

Prohibited:

- pirated files;
- full books or paid course material;
- full YouTube transcripts or downloaded videos;
- scraped TradingView data or private scripts;
- credentials or personal account exports;
- a source field named or functioning as an embedded corpus.

