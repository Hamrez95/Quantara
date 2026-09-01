namespace Quantara.Domain.Research;

public enum ResearchFundamentalScoreCode
{
    Created,
    InvalidPolicy,
    InvalidInput,
    UnusableResearch
}

public sealed record ResearchFundamentalScoreRule(
    string RuleId,
    string FactKey,
    decimal Weight);

public sealed record ResearchFundamentalScorePolicy(
    string PolicyVersion,
    double MinimumConfidence,
    IReadOnlyList<ResearchAuthorityTier> AllowedAuthorityTiers,
    IReadOnlyList<ResearchFundamentalScoreRule> Rules);

public sealed record ResearchFundamentalScoreInput(
    string FactKey,
    decimal NormalizedContribution,
    ResearchFactAssessment Assessment);

public sealed record ResearchFundamentalScoreComponent(
    string RuleId,
    string FactKey,
    decimal Weight,
    decimal NormalizedContribution,
    decimal WeightedContribution,
    double Confidence,
    IReadOnlyList<string> EvidenceIds,
    ResearchFactObservation SelectedObservation);

public sealed record ResearchFundamentalScore(
    string PolicyVersion,
    DateTimeOffset GeneratedAt,
    decimal Score,
    decimal Uncertainty,
    IReadOnlyList<ResearchFundamentalScoreComponent> Components)
{
    public ResearchExecutionAuthority ExecutionAuthority =>
        Components.Count > 0
            ? Components[0].SelectedObservation.ExecutionAuthority
            : ResearchExecutionAuthority.None;
}

public sealed record ResearchFundamentalScoreResult(
    bool IsCreated,
    ResearchFundamentalScoreCode Code,
    ResearchFundamentalScore? Score);

public static class ResearchFundamentalScoreEvaluator
{
    private const int MaxRules = 32;

    public static ResearchFundamentalScoreResult Evaluate(
        ResearchFundamentalScorePolicy? policy,
        IReadOnlyList<ResearchFundamentalScoreInput>? inputs,
        DateTimeOffset generatedAt)
    {
        if (!IsValidPolicy(policy))
        {
            return Rejected(ResearchFundamentalScoreCode.InvalidPolicy);
        }

        if (inputs is null
            || inputs.Count != policy!.Rules.Count
            || generatedAt == default
            || generatedAt.Offset != TimeSpan.Zero
            || inputs.Any(static input => input is null)
            || inputs.Any(static input =>
                !ResearchIdentityRules.IsValidText(input.FactKey, 256)
                || input.NormalizedContribution < -1m
                || input.NormalizedContribution > 1m))
        {
            return Rejected(ResearchFundamentalScoreCode.InvalidInput);
        }

        Dictionary<string, ResearchFundamentalScoreInput> inputByFactKey;
        try
        {
            inputByFactKey = inputs.ToDictionary(
                static input => input.FactKey,
                StringComparer.Ordinal);
        }
        catch (ArgumentException)
        {
            return Rejected(ResearchFundamentalScoreCode.InvalidInput);
        }

        var allowedAuthorityTiers = policy.AllowedAuthorityTiers.ToHashSet();
        var components = new List<ResearchFundamentalScoreComponent>(policy.Rules.Count);
        foreach (var rule in policy.Rules)
        {
            if (!inputByFactKey.TryGetValue(rule.FactKey, out var input)
                || !TryCreateComponent(
                    policy.MinimumConfidence,
                    allowedAuthorityTiers,
                    rule,
                    input,
                    generatedAt,
                    out var component))
            {
                return Rejected(ResearchFundamentalScoreCode.UnusableResearch);
            }

            components.Add(component!);
        }

        var rawScore = components.Sum(static component => component.WeightedContribution);
        var score = 50m + (rawScore * 50m);
        var uncertainty = components.Sum(component =>
            component.Weight * (1m - (decimal)component.Confidence));

        return new ResearchFundamentalScoreResult(
            true,
            ResearchFundamentalScoreCode.Created,
            new ResearchFundamentalScore(
                policy.PolicyVersion,
                generatedAt,
                decimal.Round(score, 6, MidpointRounding.ToEven),
                decimal.Round(uncertainty, 6, MidpointRounding.ToEven),
                Array.AsReadOnly(components.ToArray())));
    }

    private static bool IsValidPolicy(ResearchFundamentalScorePolicy? policy)
    {
        if (policy is null
            || !ResearchIdentityRules.IsValidText(policy.PolicyVersion, 128)
            || !double.IsFinite(policy.MinimumConfidence)
            || policy.MinimumConfidence < 0d
            || policy.MinimumConfidence > 1d
            || policy.AllowedAuthorityTiers is null
            || policy.AllowedAuthorityTiers.Count == 0
            || policy.AllowedAuthorityTiers.Any(tier =>
                !Enum.IsDefined(typeof(ResearchAuthorityTier), tier))
            || policy.AllowedAuthorityTiers.Distinct().Count()
                != policy.AllowedAuthorityTiers.Count
            || policy.Rules is null
            || policy.Rules.Count == 0
            || policy.Rules.Count > MaxRules
            || policy.Rules.Any(static rule => rule is null)
            || policy.Rules.Any(static rule =>
                !ResearchIdentityRules.IsValidText(rule.RuleId, 128)
                || !ResearchIdentityRules.IsValidText(rule.FactKey, 256)
                || rule.Weight <= 0m
                || rule.Weight > 1m)
            || policy.Rules.Select(static rule => rule.RuleId).Distinct(StringComparer.Ordinal).Count()
                != policy.Rules.Count
            || policy.Rules.Select(static rule => rule.FactKey).Distinct(StringComparer.Ordinal).Count()
                != policy.Rules.Count)
        {
            return false;
        }

        return policy.Rules.Sum(static rule => rule.Weight) == 1m;
    }

    private static bool TryCreateComponent(
        double minimumConfidence,
        HashSet<ResearchAuthorityTier> allowedAuthorityTiers,
        ResearchFundamentalScoreRule rule,
        ResearchFundamentalScoreInput input,
        DateTimeOffset generatedAt,
        out ResearchFundamentalScoreComponent? component)
    {
        component = null;
        var assessment = input.Assessment;
        if (assessment is null
            || !assessment.IsUsable
            || assessment.Code != ResearchFactAssessmentCode.Usable
            || assessment.Selected is null
            || assessment.Candidates is null
            || assessment.Candidates.Count == 0
            || !string.Equals(input.FactKey, rule.FactKey, StringComparison.Ordinal)
            || !string.Equals(assessment.Selected.FactKey, rule.FactKey, StringComparison.Ordinal))
        {
            return false;
        }

        var selectedValue = assessment.Selected.NormalizedValue;
        foreach (var candidate in assessment.Candidates)
        {
            if (candidate is null
                || !string.Equals(candidate.FactKey, rule.FactKey, StringComparison.Ordinal)
                || !string.Equals(candidate.NormalizedValue, selectedValue, StringComparison.Ordinal)
                || candidate.Confidence < minimumConfidence
                || candidate.ExecutionAuthority != ResearchExecutionAuthority.None
                || candidate.Evidence.RetrievedAt > generatedAt
                || (candidate.Evidence.ExpiresAt.HasValue
                    && candidate.Evidence.ExpiresAt.Value <= generatedAt)
                || !allowedAuthorityTiers.Contains(candidate.Evidence.Source.AuthorityTier))
            {
                return false;
            }
        }

        if (!assessment.Candidates.Any(candidate =>
            string.Equals(
                candidate.Evidence.EvidenceId,
                assessment.Selected.Evidence.EvidenceId,
                StringComparison.Ordinal)))
        {
            return false;
        }

        var evidenceIds = assessment.Candidates
            .Select(static candidate => candidate.Evidence.EvidenceId)
            .Distinct(StringComparer.Ordinal)
            .Order(StringComparer.Ordinal)
            .ToArray();
        component = new ResearchFundamentalScoreComponent(
            rule.RuleId,
            rule.FactKey,
            rule.Weight,
            input.NormalizedContribution,
            input.NormalizedContribution * rule.Weight,
            assessment.Selected.Confidence,
            Array.AsReadOnly(evidenceIds),
            assessment.Selected);
        return true;
    }

    private static ResearchFundamentalScoreResult Rejected(
        ResearchFundamentalScoreCode code)
    {
        return new ResearchFundamentalScoreResult(false, code, null);
    }
}
