using System.Diagnostics;
using System.Net;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;

namespace Quantara.Api.Supervisor;

public interface ISupervisorAnalysisService
{
    Task<SupervisorAnalysisResult> ReviewAsync(
        SupervisorAnalysisRequestContract request,
        CancellationToken cancellationToken);
}

public sealed class OpenAiSupervisorAnalysisService : ISupervisorAnalysisService
{
    private const int MaximumRequestCharacters = 500_000;
    private const string ResponsesEndpoint = "https://api.openai.com/v1/responses";
    private const string PromptVersion = "quantara-supervisor-v1";

    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);
    private static readonly JsonElement ReviewSchema = JsonDocument.Parse(
        """
        {
          "type": "object",
          "additionalProperties": false,
          "required": [
            "reviewId",
            "summary",
            "facts",
            "hypotheses",
            "anomalies",
            "strategyFindings",
            "recommendedExperiments",
            "insufficientEvidence",
            "insufficientEvidenceReason"
          ],
          "properties": {
            "reviewId": { "type": "string" },
            "summary": { "type": "string" },
            "facts": {
              "type": "array",
              "items": {
                "type": "object",
                "additionalProperties": false,
                "required": ["statement", "evidenceIds"],
                "properties": {
                  "statement": { "type": "string" },
                  "evidenceIds": { "type": "array", "items": { "type": "string" } }
                }
              }
            },
            "hypotheses": {
              "type": "array",
              "items": {
                "type": "object",
                "additionalProperties": false,
                "required": ["statement", "confidence", "evidenceIds"],
                "properties": {
                  "statement": { "type": "string" },
                  "confidence": { "type": "number", "minimum": 0, "maximum": 1 },
                  "evidenceIds": { "type": "array", "items": { "type": "string" } }
                }
              }
            },
            "anomalies": {
              "type": "array",
              "items": {
                "type": "object",
                "additionalProperties": false,
                "required": ["statement", "severity", "evidenceIds"],
                "properties": {
                  "statement": { "type": "string" },
                  "severity": { "type": "string", "enum": ["info", "warning", "error", "critical"] },
                  "evidenceIds": { "type": "array", "items": { "type": "string" } }
                }
              }
            },
            "strategyFindings": {
              "type": "array",
              "items": {
                "type": "object",
                "additionalProperties": false,
                "required": ["statement", "confidence", "evidenceIds"],
                "properties": {
                  "statement": { "type": "string" },
                  "confidence": { "type": "number", "minimum": 0, "maximum": 1 },
                  "evidenceIds": { "type": "array", "items": { "type": "string" } }
                }
              }
            },
            "recommendedExperiments": {
              "type": "array",
              "items": {
                "type": "object",
                "additionalProperties": false,
                "required": ["title", "rationale", "evidenceIds", "validationTests", "rollbackCriteria"],
                "properties": {
                  "title": { "type": "string" },
                  "rationale": { "type": "string" },
                  "evidenceIds": { "type": "array", "items": { "type": "string" } },
                  "validationTests": { "type": "array", "items": { "type": "string" } },
                  "rollbackCriteria": { "type": "array", "items": { "type": "string" } }
                }
              }
            },
            "insufficientEvidence": { "type": "boolean" },
            "insufficientEvidenceReason": { "type": "string" }
          }
        }
        """).RootElement.Clone();

    private readonly HttpClient _httpClient;
    private readonly IConfiguration _configuration;
    private readonly SupervisorAnalysisGate _gate;

    public OpenAiSupervisorAnalysisService(
        HttpClient httpClient,
        IConfiguration configuration,
        SupervisorAnalysisGate gate)
    {
        _httpClient = httpClient;
        _configuration = configuration;
        _gate = gate;
    }

    public async Task<SupervisorAnalysisResult> ReviewAsync(
        SupervisorAnalysisRequestContract request,
        CancellationToken cancellationToken)
    {
        var auditId = Guid.NewGuid().ToString("N");
        if (!SupervisorEvidenceValidator.TryValidate(request, out var validationError))
        {
            return SupervisorAnalysisResult.Fail(
                SupervisorAnalysisCode.InvalidEvidence,
                auditId,
                validationError);
        }

        var apiKey = _configuration["OPENAI_API_KEY"];
        var model = _configuration["QUANTARA_SUPERVISOR_OPENAI_MODEL"] ?? "gpt-5";
        if (string.IsNullOrWhiteSpace(apiKey) || apiKey.Length < 20)
        {
            return SupervisorAnalysisResult.Fail(
                SupervisorAnalysisCode.NotConfigured,
                auditId,
                "openai_not_configured");
        }

        await using var lease = await _gate.TryAcquireAsync(cancellationToken)
            .ConfigureAwait(false);
        if (lease is null)
        {
            return SupervisorAnalysisResult.Fail(
                SupervisorAnalysisCode.RateLimited,
                auditId,
                "supervisor_rate_limited");
        }

        var evidenceJson = JsonSerializer.Serialize(request, JsonOptions);
        if (evidenceJson.Length > MaximumRequestCharacters)
        {
            return SupervisorAnalysisResult.Fail(
                SupervisorAnalysisCode.InvalidEvidence,
                auditId,
                "evidence_bundle_too_large");
        }

        var maxOutputTokens = ParseBounded(
            _configuration["QUANTARA_SUPERVISOR_MAX_OUTPUT_TOKENS"],
            fallback: 4_000,
            minimum: 512,
            maximum: 12_000);
        var timeoutSeconds = ParseBounded(
            _configuration["QUANTARA_SUPERVISOR_TIMEOUT_SECONDS"],
            fallback: 45,
            minimum: 5,
            maximum: 120);

        var payload = BuildPayload(model, maxOutputTokens, request.ReviewGoal, evidenceJson);
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(TimeSpan.FromSeconds(timeoutSeconds));

        HttpResponseMessage? response = null;
        var stopwatch = Stopwatch.StartNew();
        try
        {
            for (var attempt = 0; attempt < 2; attempt++)
            {
                response?.Dispose();
                response = await SendAsync(apiKey, auditId, payload, timeout.Token)
                    .ConfigureAwait(false);
                if (!ShouldRetry(response.StatusCode) || attempt == 1)
                {
                    break;
                }

                await Task.Delay(TimeSpan.FromMilliseconds(250), timeout.Token)
                    .ConfigureAwait(false);
            }

            if (response is null || !response.IsSuccessStatusCode)
            {
                return SupervisorAnalysisResult.Fail(
                    SupervisorAnalysisCode.UpstreamFailure,
                    auditId,
                    "openai_request_failed");
            }

            var body = await response.Content.ReadAsStringAsync(timeout.Token)
                .ConfigureAwait(false);
            stopwatch.Stop();
            if (!TryParseCompletedReview(
                    body,
                    request,
                    auditId,
                    model,
                    stopwatch.ElapsedMilliseconds,
                    out var review))
            {
                return SupervisorAnalysisResult.Fail(
                    SupervisorAnalysisCode.InvalidModelOutput,
                    auditId,
                    "openai_review_invalid");
            }

            return new SupervisorAnalysisResult(
                SupervisorAnalysisCode.Completed,
                review,
                null,
                auditId);
        }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            return SupervisorAnalysisResult.Fail(
                SupervisorAnalysisCode.UpstreamFailure,
                auditId,
                "openai_request_timeout");
        }
        catch (HttpRequestException)
        {
            return SupervisorAnalysisResult.Fail(
                SupervisorAnalysisCode.UpstreamFailure,
                auditId,
                "openai_transport_failure");
        }
        finally
        {
            stopwatch.Stop();
            response?.Dispose();
        }
    }

    private async Task<HttpResponseMessage> SendAsync(
        string apiKey,
        string auditId,
        string payload,
        CancellationToken cancellationToken)
    {
        using var request = new HttpRequestMessage(HttpMethod.Post, ResponsesEndpoint);
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", apiKey);
        request.Headers.TryAddWithoutValidation("X-Client-Request-Id", auditId);
        request.Content = new StringContent(payload, Encoding.UTF8, "application/json");
        return await _httpClient.SendAsync(request, cancellationToken).ConfigureAwait(false);
    }

    private static string BuildPayload(
        string model,
        int maxOutputTokens,
        string? reviewGoal,
        string evidenceJson)
    {
        var instruction =
            "You are Quantara's read-only engineering and trading supervisor. " +
            $"Prompt version: {PromptVersion}. " +
            "Use only supplied evidence. Every factual claim must cite evidence IDs. " +
            "Separate facts from hypotheses. Never request, infer, reveal, or invent credentials. " +
            "Never propose direct mutation of live orders, positions, leverage, stops, take-profit, " +
            "transfers, risk limits, or silent live-strategy promotion. Recommendations must be " +
            "reviewable experiments with validation tests and rollback criteria.";
        var inputText = string.IsNullOrWhiteSpace(reviewGoal)
            ? $"Review this sanitized Quantara evidence bundle:\n{evidenceJson}"
            : $"Review goal: {reviewGoal}\nSanitized Quantara evidence bundle:\n{evidenceJson}";

        var payload = new
        {
            model,
            store = false,
            max_output_tokens = maxOutputTokens,
            instructions = instruction,
            input = new object[]
            {
                new
                {
                    role = "user",
                    content = new object[]
                    {
                        new { type = "input_text", text = inputText }
                    }
                }
            },
            text = new
            {
                format = new
                {
                    type = "json_schema",
                    name = "quantara_supervisor_review",
                    strict = true,
                    schema = ReviewSchema
                }
            }
        };
        return JsonSerializer.Serialize(payload, JsonOptions);
    }

    private static bool TryParseCompletedReview(
        string body,
        SupervisorAnalysisRequestContract request,
        string auditId,
        string model,
        long latencyMilliseconds,
        out SupervisorReviewContract? review)
    {
        review = null;
        try
        {
            using var response = JsonDocument.Parse(body);
            if (!response.RootElement.TryGetProperty("status", out var status)
                || !string.Equals(status.GetString(), "completed", StringComparison.Ordinal))
            {
                return false;
            }

            var outputText = FindOutputText(response.RootElement);
            if (string.IsNullOrWhiteSpace(outputText))
            {
                return false;
            }

            var modelReview = JsonSerializer.Deserialize<ModelReview>(outputText, JsonOptions);
            if (modelReview is null || !ValidateModelReview(modelReview, request))
            {
                return false;
            }

            review = new SupervisorReviewContract(
                modelReview.ReviewId,
                modelReview.Summary,
                modelReview.Facts,
                modelReview.Hypotheses,
                modelReview.Anomalies,
                modelReview.StrategyFindings,
                modelReview.RecommendedExperiments,
                modelReview.InsufficientEvidence,
                modelReview.InsufficientEvidenceReason,
                auditId,
                model,
                PromptVersion,
                ParseUsage(response.RootElement, latencyMilliseconds));
            return true;
        }
        catch (JsonException)
        {
            return false;
        }
    }

    private static SupervisorUsageContract ParseUsage(
        JsonElement root,
        long latencyMilliseconds)
    {
        var inputTokens = 0;
        var outputTokens = 0;
        var totalTokens = 0;
        if (root.TryGetProperty("usage", out var usage)
            && usage.ValueKind == JsonValueKind.Object)
        {
            inputTokens = ReadNonNegativeInt(usage, "input_tokens");
            outputTokens = ReadNonNegativeInt(usage, "output_tokens");
            totalTokens = ReadNonNegativeInt(usage, "total_tokens");
        }

        return new SupervisorUsageContract(
            inputTokens,
            outputTokens,
            totalTokens,
            Math.Max(0, latencyMilliseconds));
    }

    private static int ReadNonNegativeInt(JsonElement parent, string propertyName)
    {
        if (!parent.TryGetProperty(propertyName, out var value)
            || value.ValueKind != JsonValueKind.Number
            || !value.TryGetInt32(out var parsed))
        {
            return 0;
        }

        return Math.Max(0, parsed);
    }

    private static string? FindOutputText(JsonElement root)
    {
        if (!root.TryGetProperty("output", out var output) || output.ValueKind != JsonValueKind.Array)
        {
            return null;
        }

        foreach (var item in output.EnumerateArray())
        {
            if (!item.TryGetProperty("content", out var content)
                || content.ValueKind != JsonValueKind.Array)
            {
                continue;
            }

            foreach (var part in content.EnumerateArray())
            {
                if (part.TryGetProperty("type", out var type)
                    && type.GetString() == "output_text"
                    && part.TryGetProperty("text", out var text))
                {
                    return text.GetString();
                }
            }
        }

        return null;
    }

    private static bool ValidateModelReview(
        ModelReview review,
        SupervisorAnalysisRequestContract request)
    {
        if (string.IsNullOrWhiteSpace(review.ReviewId)
            || string.IsNullOrWhiteSpace(review.Summary)
            || review.Facts is null
            || review.Hypotheses is null
            || review.Anomalies is null
            || review.StrategyFindings is null
            || review.RecommendedExperiments is null)
        {
            return false;
        }

        if (review.InsufficientEvidence
            && string.IsNullOrWhiteSpace(review.InsufficientEvidenceReason))
        {
            return false;
        }

        var evidenceIds = request.Evidence
            .Select(item => item.EvidenceId)
            .ToHashSet(StringComparer.Ordinal);

        return review.Facts.All(item =>
                ValidStatement(item.Statement)
                && ValidEvidenceReferences(item.EvidenceIds, evidenceIds, requireAny: true))
            && review.Hypotheses.All(item =>
                ValidStatement(item.Statement)
                && ValidConfidence(item.Confidence)
                && ValidEvidenceReferences(item.EvidenceIds, evidenceIds, requireAny: false))
            && review.Anomalies.All(item =>
                ValidStatement(item.Statement)
                && item.Severity is "info" or "warning" or "error" or "critical"
                && ValidEvidenceReferences(item.EvidenceIds, evidenceIds, requireAny: true))
            && review.StrategyFindings.All(item =>
                ValidStatement(item.Statement)
                && ValidConfidence(item.Confidence)
                && ValidEvidenceReferences(item.EvidenceIds, evidenceIds, requireAny: true))
            && review.RecommendedExperiments.All(item =>
                ValidStatement(item.Title)
                && ValidStatement(item.Rationale)
                && ValidEvidenceReferences(item.EvidenceIds, evidenceIds, requireAny: true)
                && item.ValidationTests is { Count: > 0 }
                && item.RollbackCriteria is { Count: > 0 });
    }

    private static bool ValidStatement(string? value) =>
        !string.IsNullOrWhiteSpace(value) && value.Length <= 32_000;

    private static bool ValidConfidence(double value) =>
        double.IsFinite(value) && value is >= 0 and <= 1;

    private static bool ValidEvidenceReferences(
        IReadOnlyList<string>? references,
        HashSet<string> available,
        bool requireAny) =>
        references is not null
        && (!requireAny || references.Count > 0)
        && references.All(reference => available.Contains(reference));

    private static bool ShouldRetry(HttpStatusCode statusCode) =>
        statusCode == HttpStatusCode.TooManyRequests || (int)statusCode >= 500;

    private static int ParseBounded(
        string? raw,
        int fallback,
        int minimum,
        int maximum) =>
        int.TryParse(raw, out var parsed)
            ? Math.Clamp(parsed, minimum, maximum)
            : fallback;

    private sealed record ModelReview(
        string ReviewId,
        string Summary,
        IReadOnlyList<SupervisorFactContract> Facts,
        IReadOnlyList<SupervisorHypothesisContract> Hypotheses,
        IReadOnlyList<SupervisorAnomalyContract> Anomalies,
        IReadOnlyList<SupervisorStrategyFindingContract> StrategyFindings,
        IReadOnlyList<SupervisorExperimentContract> RecommendedExperiments,
        bool InsufficientEvidence,
        string InsufficientEvidenceReason);
}
