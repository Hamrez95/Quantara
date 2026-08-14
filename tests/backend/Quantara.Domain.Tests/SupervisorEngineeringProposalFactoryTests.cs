using Quantara.Api.Supervisor;

namespace Quantara.Domain.Tests;

public sealed class SupervisorEngineeringProposalFactoryTests
{
    private static readonly string[] StrategyEvidenceIds = ["strategy-1"];
    private static readonly string[] StrategyAndUnknownEvidenceIds = ["strategy-1", "unknown-1"];
    private static readonly string[] ReplayValidationPlan = ["Run deterministic replay and compare the scorecard."];
    private static readonly string[] ReplayValidationPlanShort = ["Run deterministic replay."];
    private static readonly string[] ReplayRollbackCriteria = ["Discard the candidate when replay quality regresses."];
    private static readonly string[] ReplayRollbackCriteriaShort = ["Discard the candidate on regression."];
    private static readonly string[] RegressionRollbackCriteria = ["Discard on regression."];

    [Fact]
    public void CreateExperimentDraftsCreatesValidatedDraftLinkedToKnownEvidence()
    {
        var bundle = CreateBundle();
        var review = CreateReview(
            insufficientEvidence: false,
            new SupervisorExperimentContract(
                "Compare candidate strategy offline",
                "Measure whether the candidate improves deterministic replay outcomes.",
                StrategyEvidenceIds,
                ReplayValidationPlan,
                ReplayRollbackCriteria));

        var drafts = SupervisorEngineeringProposalFactory.CreateExperimentDrafts(bundle, review);

        var draft = Assert.Single(drafts);
        Assert.True(draft.Proposal.IsDraft);
        Assert.True(draft.Proposal.RequiresHumanReview);
        Assert.Equal(SupervisorProposalKind.StrategyExperiment, draft.Proposal.Kind);
        Assert.Equal(StrategyEvidenceIds, draft.Proposal.EvidenceIds);
        Assert.True(SupervisorEngineeringReviewValidator.TryValidate(draft, out var error), error);
    }

    [Fact]
    public void CreateExperimentDraftsDropsUnknownEvidenceAndUnsafeModelMaterial()
    {
        var bundle = CreateBundle();
        var review = CreateReview(
            insufficientEvidence: false,
            new SupervisorExperimentContract(
                "Unsafe candidate",
                "authorization=not-safe-material",
                StrategyAndUnknownEvidenceIds,
                ReplayValidationPlanShort,
                ReplayRollbackCriteriaShort));

        var drafts = SupervisorEngineeringProposalFactory.CreateExperimentDrafts(bundle, review);

        Assert.Empty(drafts);
    }

    [Fact]
    public void CreateExperimentDraftsReturnsNothingWhenReviewReportsInsufficientEvidence()
    {
        var bundle = CreateBundle();
        var review = CreateReview(
            insufficientEvidence: true,
            new SupervisorExperimentContract(
                "Candidate",
                "Evaluate offline.",
                StrategyEvidenceIds,
                ReplayValidationPlanShort,
                RegressionRollbackCriteria));

        Assert.Empty(SupervisorEngineeringProposalFactory.CreateExperimentDrafts(bundle, review));
    }

    private static SupervisorAnalysisRequestContract CreateBundle() =>
        new(
            "bundle-1",
            DateTimeOffset.UtcNow,
            [
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
            ],
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
            [experiment],
            insufficientEvidence,
            insufficientEvidence ? "More evidence is required." : string.Empty,
            "audit-1",
            "test-model");
}
