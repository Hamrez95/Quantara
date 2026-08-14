using System.Net;
using System.Text;
using System.Text.Json;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Configuration;
using Quantara.Api.Supervisor;

namespace Quantara.Domain.Tests;

public sealed class SupervisorAnalysisTests
{
    [Fact]
    public void EvidenceValidatorRejectsCredentialBearingValuesAndKeys()
    {
        var rawBearer = ValidRequest(
            summary: "Authorization: Bearer abcdefghijklmnopqrstuvwxyz123456");
        Assert.False(SupervisorEvidenceValidator.TryValidate(rawBearer, out var bearerError));
        Assert.Equal("credential_like_evidence_rejected", bearerError);

        var secretKey = ValidRequest(
            attributes: new Dictionary<string, string>
            {
                ["apiKey"] = "[REDACTED_CREDENTIAL]"
            });
        Assert.False(SupervisorEvidenceValidator.TryValidate(secretKey, out var keyError));
        Assert.Equal("credential_like_evidence_rejected", keyError);
    }

    [Fact]
    public void EvidenceValidatorAcceptsAlreadyRedactedEvidence()
    {
        var request = ValidRequest(
            summary: "Authorization: [REDACTED_CREDENTIAL]",
            attributes: new Dictionary<string, string>
            {
                ["error"] = "signature=[REDACTED_CREDENTIAL]"
            });

        Assert.True(SupervisorEvidenceValidator.TryValidate(request, out var error));
        Assert.Equal(string.Empty, error);
    }

    [Fact]
    public void SupervisorAuthorityUsesDedicatedTokenAndFailsClosed()
    {
        const string token = "supervisor-token-0123456789abcdef-123456";
        var configuration = Configuration(
            new Dictionary<string, string?>
            {
                ["QUANTARA_SUPERVISOR_TOKEN"] = token
            });
        var context = new DefaultHttpContext();

        Assert.False(SupervisorEndpointAuthority.HasAuthority(context, configuration));

        context.Request.Headers[SupervisorEndpointAuthority.HeaderName] = token;
        Assert.True(SupervisorEndpointAuthority.HasAuthority(context, configuration));

        context.Request.Headers[SupervisorEndpointAuthority.HeaderName] =
            "different-token-0123456789abcdef-12345";
        Assert.False(SupervisorEndpointAuthority.HasAuthority(context, configuration));
    }

    [Fact]
    public async Task OpenAiServiceSendsStrictNonStoredRequestWithoutApiKeyInBody()
    {
        const string apiKey = "sk-test-supervisor-0123456789abcdef";
        var responseBody = CompletedResponse("runtime.scan.42");
        var handler = new CapturingHandler(HttpStatusCode.OK, responseBody);
        using var client = new HttpClient(handler);
        var configuration = Configuration(
            new Dictionary<string, string?>
            {
                ["OPENAI_API_KEY"] = apiKey,
                ["QUANTARA_SUPERVISOR_OPENAI_MODEL"] = "gpt-5",
                ["QUANTARA_SUPERVISOR_REQUESTS_PER_MINUTE"] = "10",
                ["QUANTARA_SUPERVISOR_MAX_CONCURRENCY"] = "2"
            });
        using var gate = new SupervisorAnalysisGate(new FixedTimeProvider(), configuration);
        var service = new OpenAiSupervisorAnalysisService(client, configuration, gate);

        var result = await service.ReviewAsync(ValidRequest(), CancellationToken.None);

        Assert.Equal(SupervisorAnalysisCode.Completed, result.Code);
        Assert.NotNull(result.Review);
        Assert.Equal("runtime.scan.42", Assert.Single(result.Review.Facts).EvidenceIds.Single());
        Assert.Equal("quantara-supervisor-v1", result.Review.PromptVersion);
        Assert.NotNull(result.Review.Usage);
        Assert.Equal(123, result.Review.Usage.InputTokens);
        Assert.Equal(45, result.Review.Usage.OutputTokens);
        Assert.Equal(168, result.Review.Usage.TotalTokens);
        Assert.True(result.Review.Usage.LatencyMilliseconds >= 0);
        Assert.NotNull(handler.LastRequest);
        Assert.Equal(HttpMethod.Post, handler.LastRequest.Method);
        Assert.Equal("https://api.openai.com/v1/responses", handler.LastRequest.RequestUri?.ToString());
        Assert.Equal("Bearer", handler.LastRequest.Headers.Authorization?.Scheme);
        Assert.Equal(apiKey, handler.LastRequest.Headers.Authorization?.Parameter);
        Assert.True(handler.LastRequest.Headers.Contains("X-Client-Request-Id"));
        Assert.DoesNotContain(apiKey, handler.LastBody, StringComparison.Ordinal);
        Assert.Contains("\"store\":false", handler.LastBody, StringComparison.Ordinal);
        Assert.Contains("\"type\":\"json_schema\"", handler.LastBody, StringComparison.Ordinal);
        Assert.Contains("\"strict\":true", handler.LastBody, StringComparison.Ordinal);
        Assert.Contains("Prompt version: quantara-supervisor-v1", handler.LastBody, StringComparison.Ordinal);
        Assert.DoesNotContain("place_order", handler.LastBody, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task OpenAiServiceFailsClosedWhenModelCitesUnknownEvidence()
    {
        var handler = new CapturingHandler(
            HttpStatusCode.OK,
            CompletedResponse("evidence-that-was-not-supplied"));
        using var client = new HttpClient(handler);
        var configuration = Configuration(
            new Dictionary<string, string?>
            {
                ["OPENAI_API_KEY"] = "sk-test-supervisor-0123456789abcdef"
            });
        using var gate = new SupervisorAnalysisGate(new FixedTimeProvider(), configuration);
        var service = new OpenAiSupervisorAnalysisService(client, configuration, gate);

        var result = await service.ReviewAsync(ValidRequest(), CancellationToken.None);

        Assert.Equal(SupervisorAnalysisCode.InvalidModelOutput, result.Code);
        Assert.Null(result.Review);
    }

    [Fact]
    public async Task OpenAiServiceDoesNotCallNetworkWhenNotConfigured()
    {
        var handler = new CapturingHandler(HttpStatusCode.OK, CompletedResponse("runtime.scan.42"));
        using var client = new HttpClient(handler);
        var configuration = Configuration(new Dictionary<string, string?>());
        using var gate = new SupervisorAnalysisGate(new FixedTimeProvider(), configuration);
        var service = new OpenAiSupervisorAnalysisService(client, configuration, gate);

        var result = await service.ReviewAsync(ValidRequest(), CancellationToken.None);

        Assert.Equal(SupervisorAnalysisCode.NotConfigured, result.Code);
        Assert.Null(handler.LastRequest);
    }

    private static SupervisorAnalysisRequestContract ValidRequest(
        string summary = "scanner completed cycle",
        IReadOnlyDictionary<string, string>? attributes = null) =>
        new(
            "bundle-1",
            new DateTimeOffset(2026, 8, 14, 8, 0, 0, TimeSpan.Zero),
            [
                new SupervisorEvidenceContract(
                    "runtime.scan.42",
                    "runtime",
                    "scannerHeartbeat",
                    new DateTimeOffset(2026, 8, 14, 7, 59, 0, TimeSpan.Zero),
                    summary,
                    "info",
                    "local_live_trade_controller",
                    "1.2.0-rc.3+126",
                    "scan-42",
                    attributes ?? new Dictionary<string, string>
                    {
                        ["state"] = "armed"
                    })
            ],
            "diagnose runtime consistency");

    private static IConfiguration Configuration(
        IDictionary<string, string?> values) =>
        new ConfigurationBuilder()
            .AddInMemoryCollection(values)
            .Build();

    private static string CompletedResponse(string evidenceId)
    {
        var review = JsonSerializer.Serialize(
            new
            {
                reviewId = "review-1",
                summary = "Runtime evidence is internally consistent.",
                facts = new[]
                {
                    new
                    {
                        statement = "The scanner completed a cycle.",
                        evidenceIds = new[] { evidenceId }
                    }
                },
                hypotheses = Array.Empty<object>(),
                anomalies = Array.Empty<object>(),
                strategyFindings = Array.Empty<object>(),
                recommendedExperiments = Array.Empty<object>(),
                insufficientEvidence = false,
                insufficientEvidenceReason = string.Empty
            });
        return JsonSerializer.Serialize(
            new
            {
                status = "completed",
                usage = new
                {
                    input_tokens = 123,
                    output_tokens = 45,
                    total_tokens = 168
                },
                output = new[]
                {
                    new
                    {
                        content = new[]
                        {
                            new { type = "output_text", text = review }
                        }
                    }
                }
            });
    }

    private sealed class CapturingHandler(HttpStatusCode statusCode, string responseBody)
        : HttpMessageHandler
    {
        public HttpRequestMessage? LastRequest { get; private set; }
        public string LastBody { get; private set; } = string.Empty;

        protected override async Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request,
            CancellationToken cancellationToken)
        {
            LastRequest = request;
            LastBody = request.Content is null
                ? string.Empty
                : await request.Content.ReadAsStringAsync(cancellationToken).ConfigureAwait(false);
            return new HttpResponseMessage(statusCode)
            {
                Content = new StringContent(responseBody, Encoding.UTF8, "application/json")
            };
        }
    }

    private sealed class FixedTimeProvider : TimeProvider
    {
        public override DateTimeOffset GetUtcNow() =>
            new(2026, 8, 14, 8, 0, 0, TimeSpan.Zero);
    }
}
