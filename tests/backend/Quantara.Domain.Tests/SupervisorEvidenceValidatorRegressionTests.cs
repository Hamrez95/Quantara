using Quantara.Api.Supervisor;

namespace Quantara.Domain.Tests;

public sealed class SupervisorEvidenceValidatorRegressionTests
{
    [Fact]
    public void MixedRedactedAndRawCredentialTextStillFailsClosed()
    {
        var request = new SupervisorAnalysisRequestContract(
            "mixed-secret-regression",
            new DateTimeOffset(2026, 8, 14, 9, 0, 0, TimeSpan.Zero),
            [
                new SupervisorEvidenceContract(
                    "runtime.mixed-secret",
                    "runtime",
                    "diagnosticSection",
                    new DateTimeOffset(2026, 8, 14, 8, 59, 0, TimeSpan.Zero),
                    "sanitizer regression",
                    "warning",
                    "diagnostics",
                    "1",
                    null,
                    new Dictionary<string, string>
                    {
                        ["payload"] =
                            "signature=[REDACTED_CREDENTIAL]; apiKey=raw-secret-123456"
                    })
            ],
            null);

        Assert.False(SupervisorEvidenceValidator.TryValidate(request, out var error));
        Assert.Equal("credential_like_evidence_rejected", error);
    }

    [Fact]
    public void MultipleRedactedCredentialMarkersRemainAllowed()
    {
        var request = new SupervisorAnalysisRequestContract(
            "redacted-regression",
            new DateTimeOffset(2026, 8, 14, 9, 0, 0, TimeSpan.Zero),
            [
                new SupervisorEvidenceContract(
                    "runtime.redacted",
                    "runtime",
                    "diagnosticSection",
                    new DateTimeOffset(2026, 8, 14, 8, 59, 0, TimeSpan.Zero),
                    "sanitized payload",
                    "info",
                    "diagnostics",
                    "1",
                    null,
                    new Dictionary<string, string>
                    {
                        ["payload"] =
                            "signature=[REDACTED_CREDENTIAL]; apiKey=[REDACTED_CREDENTIAL]"
                    })
            ],
            null);

        Assert.True(SupervisorEvidenceValidator.TryValidate(request, out var error));
        Assert.Equal(string.Empty, error);
    }
}
