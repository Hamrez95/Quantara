using Quantara.Api.Supervisor;

namespace Quantara.Domain.Tests;

public sealed class SupervisorEngineeringProposalFactoryTests
{
    [Fact]
    public void CreateExperimentDrafts_CreatesValidatedDraftLinkedToKnownEvidence()
    {
        var bundle = CreateBundle();
        var review = CreateReview(
            insufficientEvidence: false,
            new SupervisorExperimentContract(
                "Compare candidate strategy offline",
                "Measure whether the candidate improves deterministic replay outcomes.",
                new[] { "strategy-1" },
                new[] { "Run deterministic replay and compare the scorecard." },
                new[] { "Discard the candidate when replay quality regresses." }));

        var drafts = SupervisorEngineeringProposalFactory.CreateExperimentDrafts(bundle, review);

        var draft = Assert.Single(drafts);
        Assert.True(draft.Proposal.IsDraft);
        Assert.True(draft.Proposal.RequiresHumanReview);
        Assert.Equal(SupervisorProposalKind.StrategyExperiment, draft.Proposal.Kind);
        Assert.Equal(new[] { "strategy-1" }, draft.Proposal.EvidenceIds);
        Assert.True(SupervisorEngineeringReviewValidator.TryValidate(draft, out var error), error);
    }

    [Fact]
    public void CreateExperimentDrafts_DropsUnknownEvidenceAndUnsafeModelMaterial()
    {
        var bundle = CreateBundle();
        var review = CreateReview(
            insufficientEvidence: false,
            new SupervisorExperimentContract(
                "Unsafe candidate",
                "authorization=not-safe-material",
                new[] { "strategy-1", "unknown-1" },
                new[] { "Run deterministic replay." },
                new[] { "Discard the candidate on regression." }));

        var drafts = SupervisorEngineeringProposalFactory.CreateExperimentDrafts(bundle, review);

        Assert.Empty(drafts);
    }

    [Fact]
    public void CreateExperimentDrafts_ReturnsNothingWhenReviewReportsInsufficientEvidence()
    {
        var bundle = CreateBundle();
        var review = CreateReview(
            insufficientEvidence: true,
            new SupervisorExperimentContract(
                "Candidate",
                "Evaluate offline.",
                new[] { "strategy-1" },
                new[] { "Run deterministic replay." },
                new[] { "Discard on regression." }));

        Assert.Empty(SupervisorEngineeringProposalFactory.CreateExperimentDrafts(bundle, review));
    }

    private static SupervisorAnalysisRequestContract CreateBundle() =>
        new(
            "bundle-1",
            DateTimeOffset.UtcNow,
            new[]
            {
                new SupervisorEvidenceContract(
                    "strategy-1",
                    "strategy",
                    "scorecard",
                    DateTimeOffset.UtcNow,
                    "Candidate underperforms the baseline in deterministic replay.",
                    "warning",
                    "strategy-engine",
                    "1",
                    "corr-1",
                    null)
            },
            "Find reviewable engineering experiments.");

    private static SupervisorReviewContract CreateReview(
        bool insufficientEvidence,
        SupervisorExperimentContract experiment) =>
        new(
            "review-1",
            "Structured review",
            Array.Empty<SupervisorFactContract>(),
            Array.Empty<SupervisorHypothesisContract>(),
            Array.Empty<SupervisorAnomalyContract>(),
            Array.Empty<SupervisorStrategyFindingContract>(),
            new[] { experiment },
            insufficientEvidence,
            insufficientEvidence ? "More evidence is required." : string.Empty,
            "audit-1",
            "test-model");
}
