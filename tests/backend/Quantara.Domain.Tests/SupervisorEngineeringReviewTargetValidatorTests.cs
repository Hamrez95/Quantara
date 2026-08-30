using Quantara.Api.Supervisor;

namespace Quantara.Domain.Tests;

public sealed class SupervisorEngineeringReviewTargetValidatorTests
{
    [Fact]
    public void AcceptsDraftPullRequestOnIsolatedFeatureBranchToDev()
    {
        var valid = SupervisorEngineeringReviewTargetValidator.TryValidate(
            new SupervisorEngineeringReviewTargetContract(
                "feature/supervisor-proposal-185",
                "dev",
                201,
                IsDraft: true),
            out var error);

        Assert.True(valid, error);
    }

    [Theory]
    [InlineData(false, "feature/supervisor-proposal-185", "dev", "engineering_review_requires_draft_pull_request")]
    [InlineData(true, "main", "dev", "engineering_review_requires_feature_branch")]
    [InlineData(true, "dev", "dev", "engineering_review_requires_feature_branch")]
    [InlineData(true, "feature/supervisor-proposal-185", "main", "engineering_review_requires_dev_base")]
    public void RejectsNonDraftOrUnsafeReviewTargets(
        bool isDraft,
        string branchName,
        string baseBranch,
        string expectedError)
    {
        var valid = SupervisorEngineeringReviewTargetValidator.TryValidate(
            new SupervisorEngineeringReviewTargetContract(
                branchName,
                baseBranch,
                201,
                isDraft),
            out var error);

        Assert.False(valid);
        Assert.Equal(expectedError, error);
    }

    [Fact]
    public void RejectsInvalidPullRequestNumber()
    {
        var valid = SupervisorEngineeringReviewTargetValidator.TryValidate(
            new SupervisorEngineeringReviewTargetContract(
                "feature/supervisor-proposal-185",
                "dev",
                0,
                IsDraft: true),
            out var error);

        Assert.False(valid);
        Assert.Equal("invalid_draft_pull_request_number", error);
    }
}
