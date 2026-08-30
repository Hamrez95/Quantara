using Quantara.Api.Supervisor;

namespace Quantara.Domain.Tests;

public sealed class SupervisorEngineeringReviewValidatorTests
{
    [Fact]
    public void EvidenceLinkedDraftProposalIsAccepted()
    {
        var request = CreateRequest();

        Assert.True(SupervisorEngineeringReviewValidator.TryValidate(request, out var error));
        Assert.Equal(string.Empty, error);
    }

    [Fact]
    public void UnknownEvidenceIdIsRejected()
    {
        var request = CreateRequest() with
        {
            Proposal = CreateProposal() with { EvidenceIds = ["missing.evidence"] }
        };

        Assert.False(SupervisorEngineeringReviewValidator.TryValidate(request, out var error));
        Assert.Equal("engineering_proposal_unknown_evidence", error);
    }

    [Fact]
    public void NonDraftProposalIsRejected()
    {
        var request = CreateRequest() with
        {
            Proposal = CreateProposal() with { IsDraft = false }
        };

        Assert.False(SupervisorEngineeringReviewValidator.TryValidate(request, out var error));
        Assert.Equal("engineering_proposal_must_remain_draft", error);
    }

    [Fact]
    public void ProposalWithoutHumanReviewIsRejected()
    {
        var request = CreateRequest() with
        {
            Proposal = CreateProposal() with { RequiresHumanReview = false }
        };

        Assert.False(SupervisorEngineeringReviewValidator.TryValidate(request, out var error));
        Assert.Equal("engineering_proposal_must_remain_draft", error);
    }

    [Fact]
    public void CredentialLikeArtifactIsRejected()
    {
        var request = CreateRequest() with
        {
            Proposal = CreateProposal() with
            {
                Artifacts =
                [
                    new SupervisorDraftArtifactContract(
                        "src/backend/example.cs",
                        "unsafe sample",
                        "apiKey=raw-secret-123456")
                ]
            }
        };

        Assert.False(SupervisorEngineeringReviewValidator.TryValidate(request, out var error));
        Assert.Equal("credential_like_engineering_artifact_rejected", error);
    }

    [Fact]
    public void WorkflowSecretReferenceIsRejectedFromDraftArtifact()
    {
        var request = CreateRequest() with
        {
            Proposal = CreateProposal() with
            {
                Artifacts =
                [
                    new SupervisorDraftArtifactContract(
                        ".github/workflows/supervisor.yml",
                        "unsafe workflow proposal",
                        "env:\n  TOKEN: ${{ secrets.PRODUCTION_TOKEN }}")
                ]
            }
        };

        Assert.False(SupervisorEngineeringReviewValidator.TryValidate(request, out var error));
        Assert.Equal("secret_reference_in_engineering_artifact_rejected", error);
    }

    [Fact]
    public void LiveMutationArtifactIsRejected()
    {
        var request = CreateRequest() with
        {
            Proposal = CreateProposal() with
            {
                Artifacts =
                [
                    new SupervisorDraftArtifactContract(
                        "src/backend/risk/change.cs",
                        "attempt direct live mutation",
                        "set_leverage for the live account")
                ]
            }
        };

        Assert.False(SupervisorEngineeringReviewValidator.TryValidate(request, out var error));
        Assert.Equal("live_mutation_engineering_artifact_rejected", error);
    }

    private static SupervisorEngineeringReviewRequestContract CreateRequest() =>
        new(CreateEvidenceBundle(), CreateProposal());

    private static SupervisorAnalysisRequestContract CreateEvidenceBundle() =>
        new(
            "engineering-review-bundle",
            new DateTimeOffset(2026, 8, 14, 10, 0, 0, TimeSpan.Zero),
            [
                new SupervisorEvidenceContract(
                    "test.supervisor.failure",
                    "test",
                    "testFailure",
                    new DateTimeOffset(2026, 8, 14, 9, 59, 0, TimeSpan.Zero),
                    "deterministic supervisor regression",
                    "error",
                    "Quantara.Domain.Tests",
                    "1",
                    "ci-123",
                    new Dictionary<string, string>
                    {
                        ["testName"] = "SupervisorRegression"
                    })
            ],
            "Draft an isolated engineering fix and deterministic validation plan.");

    private static SupervisorEngineeringProposalContract CreateProposal() =>
        new(
            "proposal-185-1",
            SupervisorProposalKind.CodeFix,
            "Fix deterministic supervisor regression",
            "The referenced CI evidence reproduces the failure.",
            ["test.supervisor.failure"],
            [
                new SupervisorDraftArtifactContract(
                    "src/backend/Quantara.Api/Supervisor/example.cs",
                    "Reviewable code-only candidate",
                    "// candidate change remains isolated on a feature branch")
            ],
            ["Run the targeted deterministic test", "Run backend CI"],
            ["Regression remains reproducible", "Unexpected behavior changes"],
            ["Revert the isolated proposal commit"],
            IsDraft: true,
            RequiresHumanReview: true);
}
