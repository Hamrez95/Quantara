namespace Quantara.Domain.Research;

public enum ResearchSeverity
{
    Informational,
    Low,
    Medium,
    High,
    Critical
}

public enum ResearchHorizon
{
    Intraday,
    ShortTerm,
    MediumTerm,
    LongTerm,
    Structural
}

public enum ResearchNormalizedItemCode
{
    Created,
    InvalidInput,
    TooManyFacts,
    MismatchedEvidence,
    DuplicateFact
}

public sealed class ResearchNormalizedItem
{
    private readonly IReadOnlyList<ResearchFactObservation> _extractedFacts;

    internal ResearchNormalizedItem(
        ResearchEvidenceEnvelope evidence,
        ResearchSeverity severity,
        ResearchHorizon horizon,
        double confidence,
        IReadOnlyList<ResearchFactObservation> extractedFacts)
    {
        Evidence = evidence;
        Severity = severity;
        Horizon = horizon;
        Confidence = confidence;
        _extractedFacts = Array.AsReadOnly(extractedFacts.ToArray());
    }

    public ResearchEvidenceEnvelope Evidence { get; }

    public ResearchSeverity Severity { get; }

    public ResearchHorizon Horizon { get; }

    public double Confidence { get; }

    public IReadOnlyList<ResearchFactObservation> ExtractedFacts => _extractedFacts;

    public Uri SourceUrl => Evidence.Source.CanonicalUri;

    public DateTimeOffset RetrievedAt => Evidence.RetrievedAt;

    public DateTimeOffset? PublishedAt => Evidence.PublishedAt;

    public string ContentSha256 => Evidence.NormalizedSha256;

    public IReadOnlyList<Quantara.Domain.Trading.Symbol> AffectedSymbols =>
        Evidence.AffectedSymbols;

    public DateTimeOffset? ExpiresAt => Evidence.ExpiresAt;

    public ResearchExecutionAuthority ExecutionAuthority =>
        Evidence.ExecutionAuthority;
}

public sealed record ResearchNormalizedItemResult(
    bool IsCreated,
    ResearchNormalizedItemCode Code,
    ResearchNormalizedItem? Item);

public static class ResearchNormalizedItemFactory
{
    private const int MaxFacts = 64;

    public static ResearchNormalizedItemResult Create(
        ResearchEvidenceEnvelope? evidence,
        ResearchSeverity severity,
        ResearchHorizon horizon,
        IReadOnlyList<ResearchFactObservation>? extractedFacts)
    {
        if (evidence is null
            || evidence.ExecutionAuthority != ResearchExecutionAuthority.None
            || !Enum.IsDefined(typeof(ResearchSeverity), severity)
            || !Enum.IsDefined(typeof(ResearchHorizon), horizon)
            || extractedFacts is null
            || extractedFacts.Count == 0
            || extractedFacts.Any(static fact => fact is null))
        {
            return Rejected(ResearchNormalizedItemCode.InvalidInput);
        }

        if (extractedFacts.Count > MaxFacts)
        {
            return Rejected(ResearchNormalizedItemCode.TooManyFacts);
        }

        if (extractedFacts.Any(fact => !IsValidFact(fact)))
        {
            return Rejected(ResearchNormalizedItemCode.InvalidInput);
        }

        if (extractedFacts.Any(fact => !IsSameEvidence(evidence, fact.Evidence)))
        {
            return Rejected(ResearchNormalizedItemCode.MismatchedEvidence);
        }

        if (extractedFacts
            .Select(static fact => fact.FactKey)
            .Distinct(StringComparer.Ordinal)
            .Count() != extractedFacts.Count)
        {
            return Rejected(ResearchNormalizedItemCode.DuplicateFact);
        }

        var facts = extractedFacts
            .OrderBy(static fact => fact.FactKey, StringComparer.Ordinal)
            .ToArray();
        var confidence = facts.Min(static fact => fact.Confidence);

        return new ResearchNormalizedItemResult(
            true,
            ResearchNormalizedItemCode.Created,
            new ResearchNormalizedItem(
                evidence,
                severity,
                horizon,
                confidence,
                facts));
    }

    private static bool IsValidFact(ResearchFactObservation fact)
    {
        return fact.Evidence is not null
            && ResearchIdentityRules.IsValidText(fact.FactKey, 256)
            && ResearchIdentityRules.IsValidText(fact.NormalizedValue, 4096)
            && ResearchIdentityRules.IsValidText(fact.ParserVersion, 128)
            && double.IsFinite(fact.Confidence)
            && fact.Confidence >= 0d
            && fact.Confidence <= 1d
            && fact.ExecutionAuthority == ResearchExecutionAuthority.None;
    }

    private static bool IsSameEvidence(
        ResearchEvidenceEnvelope expected,
        ResearchEvidenceEnvelope actual)
    {
        return string.Equals(expected.EvidenceId, actual.EvidenceId, StringComparison.Ordinal)
            && string.Equals(expected.RegistryVersion, actual.RegistryVersion, StringComparison.Ordinal)
            && string.Equals(expected.RegistrySha256, actual.RegistrySha256, StringComparison.Ordinal)
            && string.Equals(expected.Source.SourceId, actual.Source.SourceId, StringComparison.Ordinal)
            && expected.Source.CanonicalUri == actual.Source.CanonicalUri
            && string.Equals(expected.ProviderItemId, actual.ProviderItemId, StringComparison.Ordinal)
            && expected.RetrievedAt == actual.RetrievedAt
            && expected.PublishedAt == actual.PublishedAt
            && expected.EventAt == actual.EventAt
            && string.Equals(expected.RawSha256, actual.RawSha256, StringComparison.Ordinal)
            && string.Equals(expected.NormalizedSha256, actual.NormalizedSha256, StringComparison.Ordinal)
            && string.Equals(expected.SchemaVersion, actual.SchemaVersion, StringComparison.Ordinal)
            && expected.Kind == actual.Kind
            && expected.ExpiresAt == actual.ExpiresAt
            && string.Equals(
                expected.ExtractionModelVersion,
                actual.ExtractionModelVersion,
                StringComparison.Ordinal)
            && string.Equals(expected.PromptVersion, actual.PromptVersion, StringComparison.Ordinal)
            && expected.ExecutionAuthority == actual.ExecutionAuthority
            && expected.AffectedSymbols.SequenceEqual(actual.AffectedSymbols);
    }

    private static ResearchNormalizedItemResult Rejected(
        ResearchNormalizedItemCode code)
    {
        return new ResearchNormalizedItemResult(false, code, null);
    }
}