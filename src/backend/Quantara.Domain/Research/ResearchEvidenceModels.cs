using Quantara.Domain.Trading;

namespace Quantara.Domain.Research;

public enum ResearchDecisionRole
{
    DirectFact,
    FeatureInput,
    ValidationMethod,
    HypothesisOnly,
    ComplianceOnly
}

public enum ResearchEvidenceKind
{
    OfficialFact,
    FeatureObservation,
    CandidateHypothesis,
    ComplianceDecision
}

public enum ResearchExecutionAuthority
{
    None
}

public enum ResearchEvidenceCode
{
    Created,
    InvalidEvidenceIdentity,
    InvalidSourceIdentity,
    InvalidTimestamp,
    InvalidHash,
    InvalidSchemaVersion,
    InvalidSymbols,
    InvalidExtractionMetadata,
    IncompatibleDecisionRole
}

public sealed record RegisteredResearchSource(
    string RegistryVersion,
    string SourceId,
    Uri CanonicalUri,
    ResearchDecisionRole DecisionRole);

public sealed class ResearchEvidenceEnvelope
{
    private readonly IReadOnlyList<Symbol> _affectedSymbols;

    internal ResearchEvidenceEnvelope(
        string evidenceId,
        RegisteredResearchSource source,
        string providerItemId,
        DateTimeOffset retrievedAt,
        DateTimeOffset? publishedAt,
        DateTimeOffset? eventAt,
        string rawSha256,
        string normalizedSha256,
        string schemaVersion,
        ResearchEvidenceKind kind,
        IReadOnlyList<Symbol> affectedSymbols,
        DateTimeOffset? expiresAt,
        string? extractionModelVersion,
        string? promptVersion)
    {
        EvidenceId = evidenceId;
        Source = source;
        ProviderItemId = providerItemId;
        RetrievedAt = retrievedAt.ToUniversalTime();
        PublishedAt = publishedAt?.ToUniversalTime();
        EventAt = eventAt?.ToUniversalTime();
        RawSha256 = rawSha256;
        NormalizedSha256 = normalizedSha256;
        SchemaVersion = schemaVersion;
        Kind = kind;
        _affectedSymbols = Array.AsReadOnly(affectedSymbols.ToArray());
        ExpiresAt = expiresAt?.ToUniversalTime();
        ExtractionModelVersion = extractionModelVersion;
        PromptVersion = promptVersion;
    }

    public string EvidenceId { get; }

    public RegisteredResearchSource Source { get; }

    public string ProviderItemId { get; }

    public DateTimeOffset RetrievedAt { get; }

    public DateTimeOffset? PublishedAt { get; }

    public DateTimeOffset? EventAt { get; }

    public string RawSha256 { get; }

    public string NormalizedSha256 { get; }

    public string SchemaVersion { get; }

    public ResearchEvidenceKind Kind { get; }

    public IReadOnlyList<Symbol> AffectedSymbols => _affectedSymbols;

    public DateTimeOffset? ExpiresAt { get; }

    public string? ExtractionModelVersion { get; }

    public string? PromptVersion { get; }

    public ResearchExecutionAuthority ExecutionAuthority => ResearchExecutionAuthority.None;
}

public sealed record ResearchEvidenceBuildResult(
    bool IsCreated,
    IReadOnlyList<ResearchEvidenceCode> RejectionReasons,
    ResearchEvidenceEnvelope? Envelope);
