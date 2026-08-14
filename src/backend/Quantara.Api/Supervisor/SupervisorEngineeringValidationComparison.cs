namespace Quantara.Api.Supervisor;

public sealed record SupervisorValidationDomainDeltaContract(
    string Domain,
    int BeforeCount,
    int AfterCount,
    IReadOnlyList<string> BeforeEvidenceIds,
    IReadOnlyList<string> AfterEvidenceIds);

public sealed record SupervisorEngineeringValidationComparisonContract(
    string BeforeBundleId,
    string AfterBundleId,
    IReadOnlyList<SupervisorValidationDomainDeltaContract> Domains);

/// <summary>
/// Produces a bounded, evidence-linked comparison for engineering validation only.
/// It deliberately compares sanitized build/test/strategy evidence and has no
/// deployment, Git mutation, exchange, live-strategy or live-config capability.
/// </summary>
public static class SupervisorEngineeringValidationComparison
{
    private static readonly string[] ValidationDomains = ["build", "test", "strategy"];

    public static bool TryCreate(
        SupervisorAnalysisRequestContract? before,
        SupervisorAnalysisRequestContract? after,
        out SupervisorEngineeringValidationComparisonContract? comparison,
        out string error)
    {
        comparison = null;
        error = string.Empty;

        if (before is null || !SupervisorEvidenceValidator.TryValidate(before, out error))
        {
            error = string.IsNullOrWhiteSpace(error) ? "invalid_before_validation_bundle" : error;
            return false;
        }

        if (after is null || !SupervisorEvidenceValidator.TryValidate(after, out error))
        {
            error = string.IsNullOrWhiteSpace(error) ? "invalid_after_validation_bundle" : error;
            return false;
        }

        var domains = ValidationDomains
            .Select(domain => CreateDomainDelta(domain, before.Evidence, after.Evidence))
            .Where(delta => delta.BeforeCount > 0 || delta.AfterCount > 0)
            .ToArray();

        if (domains.Length == 0)
        {
            error = "engineering_validation_requires_build_test_or_strategy_evidence";
            return false;
        }

        comparison = new SupervisorEngineeringValidationComparisonContract(
            before.BundleId,
            after.BundleId,
            domains);
        return true;
    }

    private static SupervisorValidationDomainDeltaContract CreateDomainDelta(
        string domain,
        IReadOnlyList<SupervisorEvidenceContract> before,
        IReadOnlyList<SupervisorEvidenceContract> after)
    {
        var beforeIds = EvidenceIdsForDomain(before, domain);
        var afterIds = EvidenceIdsForDomain(after, domain);
        return new SupervisorValidationDomainDeltaContract(
            domain,
            beforeIds.Length,
            afterIds.Length,
            beforeIds,
            afterIds);
    }

    private static string[] EvidenceIdsForDomain(
        IEnumerable<SupervisorEvidenceContract> evidence,
        string domain) =>
        evidence
            .Where(item => string.Equals(item.Domain, domain, StringComparison.Ordinal))
            .Select(item => item.EvidenceId)
            .Distinct(StringComparer.Ordinal)
            .Order(StringComparer.Ordinal)
            .ToArray();
}
