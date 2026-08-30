using System.Text.RegularExpressions;

namespace Quantara.Api.Supervisor;

public enum SupervisorProposalKind
{
    CodeFix,
    DeterministicTest,
    StrategyExperiment,
    ConfigExperiment
}

public sealed record SupervisorDraftArtifactContract(
    string Path,
    string Summary,
    string Content);

public sealed record SupervisorEngineeringProposalContract(
    string ProposalId,
    SupervisorProposalKind Kind,
    string Title,
    string Rationale,
    IReadOnlyList<string> EvidenceIds,
    IReadOnlyList<SupervisorDraftArtifactContract> Artifacts,
    IReadOnlyList<string> ValidationSteps,
    IReadOnlyList<string> FailureModes,
    IReadOnlyList<string> RollbackCriteria,
    bool IsDraft = true,
    bool RequiresHumanReview = true);

public sealed record SupervisorEngineeringReviewRequestContract(
    SupervisorAnalysisRequestContract EvidenceBundle,
    SupervisorEngineeringProposalContract Proposal);

public static partial class SupervisorEngineeringReviewValidator
{
    private const int MaximumArtifacts = 32;
    private const int MaximumArtifactCharacters = 200_000;
    private const int MaximumListItems = 64;
    private const int MaximumTextCharacters = 32_000;

    private static readonly string[] ForbiddenLiveMutationFragments =
    [
        "live-order",
        "live_order",
        "live-position",
        "live_position",
        "set-leverage",
        "set_leverage",
        "stop-loss",
        "stop_loss",
        "take-profit",
        "take_profit",
        "risk-limit",
        "risk_limit",
        "transfer-funds",
        "transfer_funds",
        "promote-live",
        "promote_live"
    ];

    public static bool TryValidate(
        SupervisorEngineeringReviewRequestContract? request,
        out string error)
    {
        if (request is null)
        {
            error = "engineering_review_request_required";
            return false;
        }

        if (!SupervisorEvidenceValidator.TryValidate(request.EvidenceBundle, out error))
        {
            return false;
        }

        var proposal = request.Proposal;
        if (proposal is null
            || !ValidText(proposal.ProposalId, 128)
            || !ValidText(proposal.Title, 512)
            || !ValidText(proposal.Rationale, MaximumTextCharacters))
        {
            error = "invalid_engineering_proposal";
            return false;
        }

        if (ContainsCredentialLikeMaterial(proposal.Title)
            || ContainsCredentialLikeMaterial(proposal.Rationale))
        {
            error = "credential_like_engineering_proposal_rejected";
            return false;
        }

        if (!proposal.IsDraft || !proposal.RequiresHumanReview)
        {
            error = "engineering_proposal_must_remain_draft";
            return false;
        }

        if (proposal.EvidenceIds is null || proposal.EvidenceIds.Count == 0)
        {
            error = "engineering_proposal_requires_evidence";
            return false;
        }

        var knownEvidenceIds = request.EvidenceBundle.Evidence
            .Select(item => item.EvidenceId)
            .ToHashSet(StringComparer.Ordinal);
        if (proposal.EvidenceIds.Any(id => !knownEvidenceIds.Contains(id)))
        {
            error = "engineering_proposal_unknown_evidence";
            return false;
        }

        if (!TryValidateTextList(proposal.ValidationSteps, "validation_steps", out error)
            || !TryValidateTextList(proposal.FailureModes, "failure_modes", out error)
            || !TryValidateTextList(proposal.RollbackCriteria, "rollback_criteria", out error))
        {
            return false;
        }

        if (proposal.Artifacts is null || proposal.Artifacts.Count is < 1 or > MaximumArtifacts)
        {
            error = "invalid_engineering_artifact_count";
            return false;
        }

        foreach (var artifact in proposal.Artifacts)
        {
            if (!TryValidateArtifact(artifact, out error))
            {
                return false;
            }
        }

        error = string.Empty;
        return true;
    }

    private static bool TryValidateArtifact(
        SupervisorDraftArtifactContract artifact,
        out string error)
    {
        if (artifact is null
            || !ValidText(artifact.Path, 1_024)
            || !ValidText(artifact.Summary, MaximumTextCharacters)
            || !ValidText(artifact.Content, MaximumArtifactCharacters))
        {
            error = "invalid_engineering_artifact";
            return false;
        }

        if (artifact.Path.StartsWith(".github/workflows/", StringComparison.OrdinalIgnoreCase)
            && artifact.Content.Contains("secrets.", StringComparison.OrdinalIgnoreCase))
        {
            error = "secret_reference_in_engineering_artifact_rejected";
            return false;
        }

        if (ContainsCredentialLikeMaterial(artifact.Path)
            || ContainsCredentialLikeMaterial(artifact.Summary)
            || ContainsCredentialLikeMaterial(artifact.Content))
        {
            error = "credential_like_engineering_artifact_rejected";
            return false;
        }

        var searchable = $"{artifact.Path}\n{artifact.Summary}\n{artifact.Content}";
        if (ForbiddenLiveMutationFragments.Any(fragment =>
                searchable.Contains(fragment, StringComparison.OrdinalIgnoreCase)))
        {
            error = "live_mutation_engineering_artifact_rejected";
            return false;
        }

        error = string.Empty;
        return true;
    }

    private static bool TryValidateTextList(
        IReadOnlyList<string>? values,
        string field,
        out string error)
    {
        if (values is null || values.Count is < 1 or > MaximumListItems
            || values.Any(value => !ValidText(value, MaximumTextCharacters)
                || ContainsCredentialLikeMaterial(value)))
        {
            error = $"invalid_{field}";
            return false;
        }

        error = string.Empty;
        return true;
    }

    private static bool ValidText(string? value, int maximumLength) =>
        !string.IsNullOrWhiteSpace(value) && value.Length <= maximumLength;

    private static bool ContainsCredentialLikeMaterial(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return false;
        }

        return AuthorizationCredentialRegex().IsMatch(value)
            || CredentialAssignmentRegex().IsMatch(value)
            || PrivateKeyRegex().IsMatch(value);
    }

    [GeneratedRegex(
        @"(?i)\b(?:bearer|basic)\s+(?!\[?REDACTED)[A-Za-z0-9._~+/=-]{8,}",
        RegexOptions.CultureInvariant)]
    private static partial Regex AuthorizationCredentialRegex();

    [GeneratedRegex(
        "(?i)\\b(?:api[_-]?(?:key|secret)|secret[_-]?key|access[_-]?token|refresh[_-]?token|session[_-]?token|password|private[_-]?key|signing[_-]?(?:key|material)|signature|authorization)\\s*[:=]\\s*[\\\"']?(?!\\[?REDACTED)[^\\s,;}\\\"']{4,}",
        RegexOptions.CultureInvariant)]
    private static partial Regex CredentialAssignmentRegex();

    [GeneratedRegex(
        @"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----",
        RegexOptions.IgnoreCase | RegexOptions.CultureInvariant)]
    private static partial Regex PrivateKeyRegex();
}
