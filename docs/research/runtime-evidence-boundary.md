# Runtime research evidence boundary

## Purpose

The source registry is not only documentation. Runtime evidence must be bound to the exact reviewed registry artifact that authorized the source role, commercial-use state, and enablement state.

## Trust chain

1. The repository registry is JSON-compatible YAML.
2. CI validates its schema, semantic policy, review due date, source IDs, licenses, roles, URLs, and prohibition on embedded corpora.
3. Deployment pins the SHA-256 of the exact registry document selected for the release.
4. `ResearchSourceRegistryLoader` recalculates the document hash and rejects a mismatch.
5. The loader requires schema version `source-registry-v1`, execution authority `none`, valid review dates, and supported source fields.
6. The loader creates an immutable `ResearchSourceRegistrySnapshot`.
7. Application code asks `ResearchEvidenceEnvelopeFactory` to resolve a source by ID from that snapshot. It cannot provide a caller-authored source role or URL.
8. Every accepted evidence envelope stores the registry version and exact registry SHA-256.

A caller cannot turn Trade City Pro into an official fact by constructing a source object. Source constructors and snapshot factories are internal; production consumers load the pinned registry document.

Regression tests alter registry fields by their semantic JSON property identity rather than relying on source-code indentation, so missing-field and unknown-field attacks remain effective even when raw-string formatting changes.

## Registry freshness

The registry review deadline is enforced twice:

- CI rejects the repository registry after `review_due_at` passes in UTC.
- Runtime rejects a stale registry at load time and rejects evidence whose retrieval date is after the snapshot review deadline.

Historical evidence can retain the registry version that was valid when it was retrieved. New evidence cannot be created under an expired policy snapshot.

## Source enablement and licensing

Runtime source policy contains:

- source ID;
- canonical HTTPS URI;
- decision role;
- commercial-use status;
- enablement state.

Evidence creation fails when:

- the source ID is absent;
- the source is disabled;
- commercial use is blocked pending a license;
- the requested evidence kind is incompatible with the source decision role.

A disabled source remains visible in the reviewed registry for planning and licensing work but cannot become a production evidence input.

## Event-time semantics

Future information and future schedules are different concepts.

- `OfficialFact`, `FeatureObservation`, and `CandidateHypothesis` may not claim an `EventAt` later than retrieval time. This prevents look-ahead evidence.
- `ScheduledEvent` requires an event time strictly after retrieval time. It represents a known future calendar event, not a known future result.
- A `ScheduledEvent` also requires `ExpiresAt` at or after the event time. This prevents a calendar item from remaining indefinitely actionable after the scheduled event has occurred.
- `ComplianceDecision` may omit event time.
- Publication time may never be later than retrieval time.

This separation allows economic-calendar reminders without allowing CPI results, announcements, or market outcomes to leak into historical decisions before publication.

## Evidence envelope

An envelope contains provenance and normalized identity only:

- evidence ID;
- registry version and hash;
- resolved registered source;
- provider item ID;
- retrieval, publication, event, and expiry timestamps;
- raw and normalized SHA-256 values;
- normalized schema version;
- evidence kind;
- affected symbols;
- extraction model and prompt versions when an LLM participated;
- immutable execution authority `None`.

The envelope deliberately contains no full article, book, transcript, prompt instructions from a source, order command, credentials, or exchange tool handle.

## Normalized research item

`ResearchNormalizedItem` binds the provenance envelope to the decision-facing metadata required by the research pipeline without expanding authority:

- explicit severity and horizon;
- extracted facts, each carrying parser version and fact-level confidence;
- conservative item confidence equal to the minimum confidence of its bound extracted facts;
- source URL, retrieval/publication/expiry timestamps, normalized content hash, and affected symbols inherited from the immutable evidence envelope;
- immutable execution authority `None`.

The factory rejects empty or unbounded fact collections, invalid confidence values, duplicate fact keys, and facts bound to different evidence. This prevents a normalized item from silently mixing provenance or inflating support.

## Downstream research gates already implemented

The current domain pipeline also provides:

- freshness and not-yet-available rejection at fact-consumption time;
- contradiction rejection rather than silent winner selection;
- bounded event clustering and duplicate suppression;
- strict structured-summary schema validation with unknown/tool-call fields rejected and prompt-injection-looking text kept inert;
- provenance-bound deterministic fundamental scoring with source-tier, confidence, freshness, policy-version and uncertainty gates.

None of these components exposes exchange credentials, trading tools, or mutation authority.

## Future integration work

The trust/domain contract intentionally does not itself provide source-specific network connectors, PostgreSQL persistence, or an LLM invocation service. Any future integration must preserve the same reviewed-source registry, provenance binding, fail-closed research gates, and `ResearchExecutionAuthority.None`, and must add its own tests, audit records, and release gates before production use.
