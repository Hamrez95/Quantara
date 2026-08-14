namespace Quantara.Api.Supervisor;

/// <summary>
/// Converts already-validated, structured Supervisor analysis into bounded Draft-only
/// engineering experiment proposals. This component creates review artifacts only;
/// it has no Git, deployment, exchange, strategy-promotion, or configuration-write capability.
/// </summary>
public static class SupervisorEngineeringProposalFactory
{
    private const int MaximumGeneratedProposals = 16;
    private static readonly string[] DefaultFailureModes =
    {
        "The observed behavior may not reproduce under deterministic validation."
    };

    public static IReadOnlyList<SupervisorEngineeringReviewRequestContract> CreateExperimentDrafts(
        SupervisorAnalysisRequestContract evidenceBundle,
        SupervisorReviewContract review)
    {
        if (!SupervisorEvidenceValidator.TryValidate(evidenceBundle, out _)
            || review is null
            || review.InsufficientEvidence
            || review.RecommendedExperiments is null)
        {
            return Array.Empty<SupervisorEngineeringReviewRequestContract>();
        }

        var knownEvidenceIds = evidenceBundle.Evidence
            .Select(item => item.EvidenceId)
            .ToHashSet(StringComparer.Ordinal);
        var drafts = new List<SupervisorEngineeringReviewRequestContract>();

        foreach (var (experiment, index) in review.RecommendedExperiments
                     .Take(MaximumGeneratedProposals)
                     .Select((item, index) => (item, index)))
        {
            if (experiment is null)
            {
                continue;
            }

            var evidenceIds = experiment.EvidenceIds?
                .Where(knownEvidenceIds.Contains)
                .Distinct(StringComparer.Ordinal)
                .Order(StringComparer.Ordinal)
                .ToArray() ?? Array.Empty<string>();
            if (evidenceIds.Length == 0)
            {
                continue;
            }

            var proposalId = BuildProposalId(review.ReviewId, index);
            var proposal = new SupervisorEngineeringProposalContract(
                proposalId,
                SupervisorProposalKind.StrategyExperiment,
                Truncate(experiment.Title, 512),
                Truncate(experiment.Rationale, 32_000),
                evidenceIds,
                new[]
                {
                    new SupervisorDraftArtifactContract(
                        $"supervisor/drafts/{proposalId}.md",
                        "Draft experiment plan generated from sanitized Supervisor evidence.",
                        BuildArtifactContent(proposalId, evidenceIds))
                },
                NormalizeList(experiment.ValidationTests),
                DefaultFailureModes,
                NormalizeList(experiment.RollbackCriteria),
                IsDraft: true,
                RequiresHumanReview: true);

            var request = new SupervisorEngineeringReviewRequestContract(evidenceBundle, proposal);
            if (SupervisorEngineeringReviewValidator.TryValidate(request, out _))
            {
                drafts.Add(request);
            }
        }

        return drafts;
    }

    private static string BuildProposalId(string? reviewId, int index)
    {
        var safeReviewId = new string((reviewId ?? "review")
            .Where(character => char.IsLetterOrDigit(character) || character is '-' or '_')
            .Take(96)
            .ToArray());
        if (string.IsNullOrWhiteSpace(safeReviewId))
        {
            safeReviewId = "review";
        }

        return $"{safeReviewId}-experiment-{index + 1:D2}";
    }

    private static string BuildArtifactContent(string proposalId, IReadOnlyList<string> evidenceIds) =>
        $"# Draft engineering experiment\n\nProposal: {proposalId}\n\n" +
        $"Evidence: {string.Join(", ", evidenceIds)}\n\n" +
        "This artifact is a review-only plan. A human reviewer must approve implementation and validation.";

    private static string[] NormalizeList(IReadOnlyList<string>? values) =>
        values?
            .Where(value => !string.IsNullOrWhiteSpace(value))
            .Take(64)
            .Select(value => Truncate(value, 32_000))
            .ToArray() ?? Array.Empty<string>();

    private static string Truncate(string? value, int maximumLength)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return string.Empty;
        }

        return value.Length <= maximumLength ? value : value[..maximumLength];
    }
}
