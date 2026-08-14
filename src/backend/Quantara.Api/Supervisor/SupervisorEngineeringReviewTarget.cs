namespace Quantara.Api.Supervisor;

public sealed record SupervisorEngineeringReviewTargetContract(
    string BranchName,
    string BaseBranch,
    int PullRequestNumber,
    bool IsDraft);

/// <summary>
/// Validates the Git review target for Supervisor engineering work.
/// This contract deliberately permits review metadata only; it grants no Git,
/// deployment, exchange, strategy-promotion or live-trading authority.
/// </summary>
public static class SupervisorEngineeringReviewTargetValidator
{
    public static bool TryValidate(
        SupervisorEngineeringReviewTargetContract? target,
        out string error)
    {
        if (target is null)
        {
            error = "engineering_review_target_required";
            return false;
        }

        if (!target.IsDraft)
        {
            error = "engineering_review_requires_draft_pull_request";
            return false;
        }

        if (target.PullRequestNumber <= 0)
        {
            error = "invalid_draft_pull_request_number";
            return false;
        }

        if (!IsIsolatedFeatureBranch(target.BranchName))
        {
            error = "engineering_review_requires_feature_branch";
            return false;
        }

        if (!string.Equals(target.BaseBranch, "dev", StringComparison.Ordinal))
        {
            error = "engineering_review_requires_dev_base";
            return false;
        }

        error = string.Empty;
        return true;
    }

    private static bool IsIsolatedFeatureBranch(string branchName) =>
        !string.IsNullOrWhiteSpace(branchName)
        && branchName.Length <= 255
        && branchName.StartsWith("feature/", StringComparison.Ordinal)
        && !string.Equals(branchName, "feature/main", StringComparison.OrdinalIgnoreCase)
        && !string.Equals(branchName, "feature/dev", StringComparison.OrdinalIgnoreCase);
}
