namespace Quantara.Api.Supervisor;

public enum SupervisorProposalValidationState
{
    Draft,
    ValidationRunning,
    Validated,
    Rejected
}

public sealed record SupervisorProposalValidationEvidenceContract(
    IReadOnlyList<string> BeforeEvidenceIds,
    IReadOnlyList<string> AfterEvidenceIds,
    string OutcomeSummary);

public sealed record SupervisorProposalLifecycleContract(
    string ProposalId,
    string BranchName,
    int? PullRequestNumber,
    SupervisorProposalValidationState State,
    IReadOnlyList<string> EvidenceIds,
    SupervisorProposalValidationEvidenceContract? Validation,
    DateTimeOffset UpdatedAtUtc);

/// <summary>
/// In-memory review-work tracker for AI Supervisor engineering proposals.
/// It records review metadata only and deliberately has no Git, deployment,
/// exchange, live-strategy or live-configuration mutation capability.
/// </summary>
public sealed class SupervisorEngineeringProposalTracker
{
    private const int MaximumTrackedProposals = 256;
    private readonly object _sync = new();
    private readonly Dictionary<string, SupervisorProposalLifecycleContract> _items =
        new(StringComparer.Ordinal);
    private readonly Queue<string> _insertionOrder = new();
    private readonly TimeProvider _timeProvider;

    public SupervisorEngineeringProposalTracker(TimeProvider timeProvider)
    {
        _timeProvider = timeProvider;
    }

    public bool TryRegisterDraft(
        SupervisorEngineeringReviewRequestContract request,
        string branchName,
        out SupervisorProposalLifecycleContract? lifecycle,
        out string error)
    {
        lifecycle = null;
        if (!SupervisorEngineeringReviewValidator.TryValidate(request, out error))
        {
            return false;
        }

        if (!TryValidateFeatureBranch(branchName, out error))
        {
            return false;
        }

        var proposal = request.Proposal;
        var item = new SupervisorProposalLifecycleContract(
            proposal.ProposalId,
            branchName,
            null,
            SupervisorProposalValidationState.Draft,
            proposal.EvidenceIds.Distinct(StringComparer.Ordinal).Order(StringComparer.Ordinal).ToArray(),
            null,
            _timeProvider.GetUtcNow());

        lock (_sync)
        {
            if (_items.ContainsKey(item.ProposalId))
            {
                error = "engineering_proposal_already_tracked";
                return false;
            }

            _items[item.ProposalId] = item;
            _insertionOrder.Enqueue(item.ProposalId);
            TrimIfNeeded();
        }

        lifecycle = item;
        error = string.Empty;
        return true;
    }

    public bool TryAttachDraftPullRequest(
        string proposalId,
        int pullRequestNumber,
        out SupervisorProposalLifecycleContract? lifecycle,
        out string error)
    {
        lifecycle = null;
        if (pullRequestNumber <= 0)
        {
            error = "invalid_draft_pull_request_number";
            return false;
        }

        lock (_sync)
        {
            if (!_items.TryGetValue(proposalId, out var current))
            {
                error = "engineering_proposal_not_found";
                return false;
            }

            var updated = current with
            {
                PullRequestNumber = pullRequestNumber,
                UpdatedAtUtc = _timeProvider.GetUtcNow()
            };
            _items[proposalId] = updated;
            lifecycle = updated;
        }

        error = string.Empty;
        return true;
    }

    public bool TryStartValidation(
        string proposalId,
        IReadOnlyList<string> beforeEvidenceIds,
        out SupervisorProposalLifecycleContract? lifecycle,
        out string error)
    {
        lifecycle = null;
        if (!ValidEvidenceIds(beforeEvidenceIds))
        {
            error = "invalid_before_validation_evidence";
            return false;
        }

        lock (_sync)
        {
            if (!_items.TryGetValue(proposalId, out var current))
            {
                error = "engineering_proposal_not_found";
                return false;
            }

            if (current.State != SupervisorProposalValidationState.Draft)
            {
                error = "invalid_engineering_validation_transition";
                return false;
            }

            var validation = new SupervisorProposalValidationEvidenceContract(
                NormalizeEvidence(beforeEvidenceIds),
                Array.Empty<string>(),
                "validation_running");
            var updated = current with
            {
                State = SupervisorProposalValidationState.ValidationRunning,
                Validation = validation,
                UpdatedAtUtc = _timeProvider.GetUtcNow()
            };
            _items[proposalId] = updated;
            lifecycle = updated;
        }

        error = string.Empty;
        return true;
    }

    public bool TryCompleteValidation(
        string proposalId,
        bool passed,
        IReadOnlyList<string> afterEvidenceIds,
        string outcomeSummary,
        out SupervisorProposalLifecycleContract? lifecycle,
        out string error)
    {
        lifecycle = null;
        if (!ValidEvidenceIds(afterEvidenceIds) || string.IsNullOrWhiteSpace(outcomeSummary)
            || outcomeSummary.Length > 4_096)
        {
            error = "invalid_after_validation_evidence";
            return false;
        }

        lock (_sync)
        {
            return TryCompleteValidationLocked(
                proposalId,
                passed,
                afterEvidenceIds,
                outcomeSummary,
                out lifecycle,
                out error);
        }
    }

    public bool TryCompleteValidationFromBundles(
        string proposalId,
        bool passed,
        SupervisorAnalysisRequestContract? before,
        SupervisorAnalysisRequestContract? after,
        string outcomeSummary,
        out SupervisorProposalLifecycleContract? lifecycle,
        out SupervisorEngineeringValidationComparisonContract? comparison,
        out string error)
    {
        lifecycle = null;
        comparison = null;
        if (string.IsNullOrWhiteSpace(outcomeSummary) || outcomeSummary.Length > 4_096)
        {
            error = "invalid_after_validation_evidence";
            return false;
        }

        if (!SupervisorEngineeringValidationComparison.TryCreate(
                before,
                after,
                out comparison,
                out error))
        {
            return false;
        }

        var comparisonBeforeEvidenceIds = NormalizeEvidence(
            comparison.Domains.SelectMany(domain => domain.BeforeEvidenceIds));
        var comparisonAfterEvidenceIds = NormalizeEvidence(
            comparison.Domains.SelectMany(domain => domain.AfterEvidenceIds));

        if (!ValidEvidenceIds(comparisonBeforeEvidenceIds)
            || !ValidEvidenceIds(comparisonAfterEvidenceIds))
        {
            comparison = null;
            error = "invalid_engineering_validation_comparison_evidence";
            return false;
        }

        lock (_sync)
        {
            if (!_items.TryGetValue(proposalId, out var current))
            {
                comparison = null;
                error = "engineering_proposal_not_found";
                return false;
            }

            if (current.State != SupervisorProposalValidationState.ValidationRunning
                || current.Validation is null)
            {
                comparison = null;
                error = "invalid_engineering_validation_transition";
                return false;
            }

            if (!current.Validation.BeforeEvidenceIds.SequenceEqual(comparisonBeforeEvidenceIds))
            {
                comparison = null;
                error = "engineering_validation_before_evidence_mismatch";
                return false;
            }

            return TryCompleteValidationLocked(
                proposalId,
                passed,
                comparisonAfterEvidenceIds,
                outcomeSummary,
                out lifecycle,
                out error);
        }
    }

    public SupervisorProposalLifecycleContract? Get(string proposalId)
    {
        lock (_sync)
        {
            return _items.GetValueOrDefault(proposalId);
        }
    }

    private bool TryCompleteValidationLocked(
        string proposalId,
        bool passed,
        IReadOnlyList<string> afterEvidenceIds,
        string outcomeSummary,
        out SupervisorProposalLifecycleContract? lifecycle,
        out string error)
    {
        lifecycle = null;
        if (!_items.TryGetValue(proposalId, out var current))
        {
            error = "engineering_proposal_not_found";
            return false;
        }

        if (current.State != SupervisorProposalValidationState.ValidationRunning
            || current.Validation is null)
        {
            error = "invalid_engineering_validation_transition";
            return false;
        }

        var validation = current.Validation with
        {
            AfterEvidenceIds = NormalizeEvidence(afterEvidenceIds),
            OutcomeSummary = outcomeSummary
        };
        var updated = current with
        {
            State = passed
                ? SupervisorProposalValidationState.Validated
                : SupervisorProposalValidationState.Rejected,
            Validation = validation,
            UpdatedAtUtc = _timeProvider.GetUtcNow()
        };
        _items[proposalId] = updated;
        lifecycle = updated;
        error = string.Empty;
        return true;
    }

    private static bool TryValidateFeatureBranch(string branchName, out string error)
    {
        if (string.IsNullOrWhiteSpace(branchName)
            || branchName.Length > 255
            || string.Equals(branchName, "main", StringComparison.OrdinalIgnoreCase)
            || string.Equals(branchName, "dev", StringComparison.OrdinalIgnoreCase)
            || !branchName.StartsWith("feature/", StringComparison.Ordinal))
        {
            error = "engineering_proposal_requires_feature_branch";
            return false;
        }

        error = string.Empty;
        return true;
    }

    private static bool ValidEvidenceIds(IReadOnlyList<string>? evidenceIds) =>
        evidenceIds is { Count: > 0 and <= 128 }
        && evidenceIds.All(id => !string.IsNullOrWhiteSpace(id) && id.Length <= 256);

    private static string[] NormalizeEvidence(IEnumerable<string> evidenceIds) =>
        evidenceIds.Distinct(StringComparer.Ordinal).Order(StringComparer.Ordinal).ToArray();

    private void TrimIfNeeded()
    {
        while (_items.Count > MaximumTrackedProposals && _insertionOrder.Count > 0)
        {
            _items.Remove(_insertionOrder.Dequeue());
        }
    }
}
