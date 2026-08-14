using Quantara.Api.Supervisor;

namespace Quantara.Domain.Tests;

public sealed class SupervisorEngineeringProposalTrackerTests
{
    private static readonly string[] BeforeEvidenceIds = ["test.before"];
    private static readonly string[] MismatchedBeforeEvidenceIds = ["test.started"];

    [Fact]
    public void CompleteValidationFromBundlesRecordsComparedEvidence()
    {
        var tracker = CreateStartedTracker(BeforeEvidenceIds);
        var before = CreateBundle(
            "validation-before",
            CreateEvidence("test.before", "test"));
        var after = CreateBundle(
            "validation-after",
            CreateEvidence("test.after", "test"),
            CreateEvidence("runtime.after", "runtime"));

        var completed = tracker.TryCompleteValidationFromBundles(
            "proposal-185",
            passed: true,
            before,
            after,
            "Deterministic validation passed.",
            out var lifecycle,
            out var comparison,
            out var error);

        Assert.True(completed, error);
        Assert.NotNull(lifecycle);
        Assert.NotNull(comparison);
        Assert.Equal(SupervisorProposalValidationState.Validated, lifecycle.State);
        Assert.Equal(BeforeEvidenceIds, lifecycle.Validation!.BeforeEvidenceIds);
        Assert.Equal(["test.after"], lifecycle.Validation.AfterEvidenceIds);
        Assert.Equal("validation-before", comparison.BeforeBundleId);
        Assert.Equal("validation-after", comparison.AfterBundleId);
        Assert.DoesNotContain(comparison.Domains, domain => domain.Domain == "runtime");
    }

    [Fact]
    public void CompleteValidationFromBundlesRejectsDifferentStartingEvidence()
    {
        var tracker = CreateStartedTracker(MismatchedBeforeEvidenceIds);
        var before = CreateBundle(
            "validation-before",
            CreateEvidence("test.before", "test"));
        var after = CreateBundle(
            "validation-after",
            CreateEvidence("test.after", "test"));

        var completed = tracker.TryCompleteValidationFromBundles(
            "proposal-185",
            passed: false,
            before,
            after,
            "Validation still fails.",
            out var lifecycle,
            out var comparison,
            out var error);

        Assert.False(completed);
        Assert.Null(lifecycle);
        Assert.Null(comparison);
        Assert.Equal("engineering_validation_before_evidence_mismatch", error);
        Assert.Equal(
            SupervisorProposalValidationState.ValidationRunning,
            tracker.Get("proposal-185")!.State);
    }

    private static SupervisorEngineeringProposalTracker CreateStartedTracker(
        IReadOnlyList<string> beforeEvidenceIds)
    {
        var tracker = new SupervisorEngineeringProposalTracker(TimeProvider.System);
        Assert.True(
            tracker.TryRegisterDraft(
                CreateRequest(),
                "feature/proposal-185",
                out _,
                out var registrationError),
            registrationError);
        Assert.True(
            tracker.TryStartValidation(
                "proposal-185",
                beforeEvidenceIds,
                out _,
                out var startError),
            startError);
        return tracker;
    }

    private static SupervisorEngineeringReviewRequestContract CreateRequest()
    {
        var evidence = CreateEvidence("proposal.evidence", "test");
        var bundle = CreateBundle("proposal-bundle", evidence);
        var proposal = new SupervisorEngineeringProposalContract(
            "proposal-185",
            SupervisorProposalKind.DeterministicTest,
            "Validate the Supervisor engineering proposal",
            "Run deterministic validation against sanitized evidence.",
            ["proposal.evidence"],
            [
                new SupervisorDraftArtifactContract(
                    "tests/backend/Quantara.Domain.Tests/SupervisorProposalCandidateTests.cs",
                    "Draft deterministic test candidate.",
                    "// Review-only deterministic test candidate")
            ],
            ["Run backend deterministic tests"],
            ["Validation remains red"],
            ["Revert the isolated proposal commit"],
            IsDraft: true,
            RequiresHumanReview: true);
        return new SupervisorEngineeringReviewRequestContract(bundle, proposal);
    }

    private static SupervisorAnalysisRequestContract CreateBundle(
        string bundleId,
        params SupervisorEvidenceContract[] evidence) =>
        new(
            bundleId,
            new DateTimeOffset(2026, 8, 14, 18, 0, 0, TimeSpan.Zero),
            evidence,
            "Compare sanitized deterministic engineering validation evidence.");

    private static SupervisorEvidenceContract CreateEvidence(string evidenceId, string domain) =>
        new(
            evidenceId,
            domain,
            "validation",
            new DateTimeOffset(2026, 8, 14, 17, 59, 0, TimeSpan.Zero),
            "Sanitized deterministic validation evidence.",
            "info",
            "engineering-validation",
            "1",
            "validation-185",
            null);
}
