using Quantara.Api.Supervisor;

namespace Quantara.Domain.Tests;

public sealed class SupervisorEngineeringValidationComparisonTests
{
    [Fact]
    public void CreateComparisonReturnsEvidenceLinkedBuildTestAndStrategyDeltas()
    {
        var before = CreateBundle(
            "before",
            [
                CreateEvidence("build.before", "build"),
                CreateEvidence("test.before", "test"),
                CreateEvidence("runtime.before", "runtime")
            ]);
        var after = CreateBundle(
            "after",
            [
                CreateEvidence("build.after", "build"),
                CreateEvidence("test.after", "test"),
                CreateEvidence("strategy.after", "strategy"),
                CreateEvidence("runtime.after", "runtime")
            ]);

        var created = SupervisorEngineeringValidationComparison.TryCreate(
            before,
            after,
            out var comparison,
            out var error);

        Assert.True(created, error);
        Assert.NotNull(comparison);
        Assert.Equal("before", comparison.BeforeBundleId);
        Assert.Equal("after", comparison.AfterBundleId);
        Assert.Equal(3, comparison.Domains.Count);
        Assert.DoesNotContain(comparison.Domains, item => item.Domain == "runtime");
        Assert.Contains(comparison.Domains, item =>
            item.Domain == "strategy"
            && item.BeforeCount == 0
            && item.AfterEvidenceIds.SequenceEqual(["strategy.after"]));
    }

    [Fact]
    public void CreateComparisonRejectsBundlesWithoutEngineeringValidationEvidence()
    {
        var before = CreateBundle("before", [CreateEvidence("runtime.before", "runtime")]);
        var after = CreateBundle("after", [CreateEvidence("journal.after", "journal")]);

        var created = SupervisorEngineeringValidationComparison.TryCreate(
            before,
            after,
            out var comparison,
            out var error);

        Assert.False(created);
        Assert.Null(comparison);
        Assert.Equal("engineering_validation_requires_build_test_or_strategy_evidence", error);
    }

    [Fact]
    public void CreateComparisonRejectsCredentialBearingEvidenceBeforeComparison()
    {
        var before = CreateBundle(
            "before",
            [CreateEvidence("test.before", "test") with { Summary = "authorization=unsafe-value" }]);
        var after = CreateBundle("after", [CreateEvidence("test.after", "test")]);

        var created = SupervisorEngineeringValidationComparison.TryCreate(
            before,
            after,
            out var comparison,
            out var error);

        Assert.False(created);
        Assert.Null(comparison);
        Assert.NotEqual(string.Empty, error);
    }

    private static SupervisorAnalysisRequestContract CreateBundle(
        string bundleId,
        IReadOnlyList<SupervisorEvidenceContract> evidence) =>
        new(
            bundleId,
            new DateTimeOffset(2026, 8, 14, 12, 0, 0, TimeSpan.Zero),
            evidence,
            "Compare deterministic engineering validation evidence.");

    private static SupervisorEvidenceContract CreateEvidence(string evidenceId, string domain) =>
        new(
            evidenceId,
            domain,
            "validation",
            new DateTimeOffset(2026, 8, 14, 11, 59, 0, TimeSpan.Zero),
            "Sanitized deterministic validation evidence.",
            "info",
            "engineering-validation",
            "1",
            "validation-1",
            null);
}
