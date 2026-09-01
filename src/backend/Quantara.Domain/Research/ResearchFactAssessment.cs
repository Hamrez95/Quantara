namespace Quantara.Domain.Research;

public enum ResearchFactAssessmentCode
{
    Usable,
    InvalidObservation,
    NotYetAvailable,
    Expired,
    LowConfidence,
    Contradicted
}

public sealed record ResearchFactObservation(
    ResearchEvidenceEnvelope Evidence,
    string FactKey,
    string NormalizedValue,
    string ParserVersion,
    double Confidence)
{
    public ResearchExecutionAuthority ExecutionAuthority =>
        Evidence.ExecutionAuthority;
}

public sealed record ResearchFactAssessment(
    bool IsUsable,
    ResearchFactAssessmentCode Code,
    ResearchFactObservation? Selected,
    IReadOnlyList<ResearchFactObservation> Candidates);

public static class ResearchFactAssessmentEvaluator
{
    public static ResearchFactAssessment Evaluate(
        string factKey,
        IReadOnlyList<ResearchFactObservation>? observations,
        DateTimeOffset asOf,
        double minimumConfidence = 0.6d)
    {
        if (!ResearchIdentityRules.IsValidText(factKey, 256)
            || observations is null
            || observations.Count == 0
            || asOf == default
            || !double.IsFinite(minimumConfidence)
            || minimumConfidence < 0d
            || minimumConfidence > 1d
            || observations.Any(static observation => !IsValid(observation)))
        {
            return Rejected(ResearchFactAssessmentCode.InvalidObservation);
        }

        var asOfUtc = asOf.ToUniversalTime();
        var matching = observations
            .Where(observation => string.Equals(
                observation.FactKey,
                factKey,
                StringComparison.Ordinal))
            .ToArray();
        if (matching.Length == 0)
        {
            return Rejected(ResearchFactAssessmentCode.InvalidObservation);
        }

        var available = matching
            .Where(observation => observation.Evidence.RetrievedAt <= asOfUtc)
            .ToArray();
        if (available.Length == 0)
        {
            return Rejected(
                ResearchFactAssessmentCode.NotYetAvailable,
                matching);
        }

        var fresh = available
            .Where(observation =>
                !observation.Evidence.ExpiresAt.HasValue
                || observation.Evidence.ExpiresAt.Value > asOfUtc)
            .ToArray();
        if (fresh.Length == 0)
        {
            return Rejected(ResearchFactAssessmentCode.Expired, available);
        }

        var qualified = fresh
            .Where(observation => observation.Confidence >= minimumConfidence)
            .ToArray();
        if (qualified.Length == 0)
        {
            return Rejected(ResearchFactAssessmentCode.LowConfidence, fresh);
        }

        var values = qualified
            .Select(static observation => observation.NormalizedValue)
            .Distinct(StringComparer.Ordinal)
            .Take(2)
            .Count();
        if (values > 1)
        {
            return Rejected(
                ResearchFactAssessmentCode.Contradicted,
                qualified);
        }

        var selected = qualified
            .OrderByDescending(static observation => observation.Confidence)
            .ThenByDescending(static observation => observation.Evidence.RetrievedAt)
            .ThenBy(static observation => observation.Evidence.EvidenceId, StringComparer.Ordinal)
            .First();
        return new ResearchFactAssessment(
            true,
            ResearchFactAssessmentCode.Usable,
            selected,
            Array.AsReadOnly(qualified.ToArray()));
    }

    private static bool IsValid(ResearchFactObservation? observation)
    {
        return observation is not null
            && observation.Evidence is not null
            && ResearchIdentityRules.IsValidText(observation.FactKey, 256)
            && ResearchIdentityRules.IsValidText(observation.NormalizedValue, 4096)
            && ResearchIdentityRules.IsValidText(observation.ParserVersion, 128)
            && double.IsFinite(observation.Confidence)
            && observation.Confidence >= 0d
            && observation.Confidence <= 1d
            && observation.ExecutionAuthority == ResearchExecutionAuthority.None;
    }

    private static ResearchFactAssessment Rejected(
        ResearchFactAssessmentCode code,
        IReadOnlyList<ResearchFactObservation>? candidates = null)
    {
        return new ResearchFactAssessment(
            false,
            code,
            null,
            Array.AsReadOnly((candidates ?? Array.Empty<ResearchFactObservation>()).ToArray()));
    }
}
