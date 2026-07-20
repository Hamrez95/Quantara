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

public enum ResearchCommercialUseStatus
{
    ApprovedSubjectToTerms,
    BlockedPendingLicense,
    CitationOnly,
    NotApplicable
}

public enum ResearchEvidenceKind
{
    OfficialFact,
    ScheduledEvent,
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
    RegistryExpired,
    SourceDisabled,
    SourceLicenseBlocked,
    InvalidTimestamp,
    InvalidHash,
    InvalidSchemaVersion,
    InvalidSymbols,
    InvalidExtractionMetadata,
    IncompatibleDecisionRole
}

public sealed class RegisteredResearchSource
{
    internal RegisteredResearchSource(
        string sourceId,
        Uri canonicalUri,
        ResearchDecisionRole decisionRole,
        ResearchCommercialUseStatus commercialUseStatus,
        bool isEnabled)
    {
        SourceId = sourceId;
        CanonicalUri = canonicalUri;
        DecisionRole = decisionRole;
        CommercialUseStatus = commercialUseStatus;
        IsEnabled = isEnabled;
    }

    public string SourceId { get; }

    public Uri CanonicalUri { get; }

    public ResearchDecisionRole DecisionRole { get; }

    public ResearchCommercialUseStatus CommercialUseStatus { get; }

    public bool IsEnabled { get; }
}

public sealed class ResearchEvidenceEnvelope
{
    private readonly IReadOnlyList<Symbol> _affectedSymbols;

    internal ResearchEvidenceEnvelope(
        string evidenceId,
        string registryVersion,
        string registrySha256,
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
        RegistryVersion = registryVersion;
        RegistrySha256 = registrySha256;
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
        ExecutionAuthority = ResearchExecutionAuthority.None;
    }

    public string EvidenceId { get; }

    public string RegistryVersion { get; }

    public string RegistrySha256 { get; }

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

    public ResearchExecutionAuthority ExecutionAuthority { get; }
}

public sealed record ResearchEvidenceBuildResult(
    bool IsCreated,
    IReadOnlyList<ResearchEvidenceCode> RejectionReasons,
    ResearchEvidenceEnvelope? Envelope);
