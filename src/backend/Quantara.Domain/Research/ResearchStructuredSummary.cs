using System.Text.Json;

namespace Quantara.Domain.Research;

public enum ResearchStructuredSummaryCode
{
    Created,
    InvalidJson,
    InvalidSchema,
    UnsupportedEvidence,
    OversizedPayload
}

public sealed record ResearchStructuredClaim(
    string FactKey,
    string NormalizedValue,
    double Confidence,
    IReadOnlyList<ResearchEvidenceEnvelope> Evidence);

public sealed record ResearchStructuredSummary(
    string SchemaVersion,
    string ModelVersion,
    string PromptVersion,
    IReadOnlyList<ResearchStructuredClaim> Claims)
{
    public ResearchExecutionAuthority ExecutionAuthority =>
        Claims.Count > 0 && Claims[0].Evidence.Count > 0
            ? Claims[0].Evidence[0].ExecutionAuthority
            : ResearchExecutionAuthority.None;
}

public sealed record ResearchStructuredSummaryResult(
    bool IsCreated,
    ResearchStructuredSummaryCode Code,
    ResearchStructuredSummary? Summary);

public static class ResearchStructuredSummaryParser
{
    private const string SupportedSchemaVersion = "summary-v1";
    private const int MaxJsonLength = 65536;
    private const int MaxClaims = 64;
    private const int MaxEvidencePerClaim = 16;
    private static readonly HashSet<string> AllowedRootProperties =
        new(StringComparer.Ordinal)
        {
            "schemaVersion",
            "modelVersion",
            "promptVersion",
            "claims"
        };
    private static readonly HashSet<string> AllowedClaimProperties =
        new(StringComparer.Ordinal)
        {
            "factKey",
            "normalizedValue",
            "confidence",
            "evidenceIds"
        };

    public static ResearchStructuredSummaryResult Parse(
        string? json,
        IReadOnlyList<ResearchEvidenceEnvelope>? availableEvidence)
    {
        if (string.IsNullOrWhiteSpace(json))
        {
            return Rejected(ResearchStructuredSummaryCode.InvalidJson);
        }

        if (json.Length > MaxJsonLength)
        {
            return Rejected(ResearchStructuredSummaryCode.OversizedPayload);
        }

        if (availableEvidence is null
            || availableEvidence.Count == 0
            || availableEvidence.Any(static evidence => evidence is null)
            || availableEvidence.Any(static evidence =>
                evidence.ExecutionAuthority != ResearchExecutionAuthority.None))
        {
            return Rejected(ResearchStructuredSummaryCode.UnsupportedEvidence);
        }

        Dictionary<string, ResearchEvidenceEnvelope> evidenceById;
        try
        {
            evidenceById = availableEvidence.ToDictionary(
                static evidence => evidence.EvidenceId,
                StringComparer.Ordinal);
        }
        catch (ArgumentException)
        {
            return Rejected(ResearchStructuredSummaryCode.UnsupportedEvidence);
        }

        try
        {
            using var document = JsonDocument.Parse(
                json,
                new JsonDocumentOptions
                {
                    AllowTrailingCommas = false,
                    CommentHandling = JsonCommentHandling.Disallow,
                    MaxDepth = 16
                });
            var root = document.RootElement;
            if (root.ValueKind != JsonValueKind.Object
                || !HasOnlyProperties(root, AllowedRootProperties)
                || !TryReadText(root, "schemaVersion", 64, out var schemaVersion)
                || !string.Equals(
                    schemaVersion,
                    SupportedSchemaVersion,
                    StringComparison.Ordinal)
                || !TryReadText(root, "modelVersion", 128, out var modelVersion)
                || !TryReadText(root, "promptVersion", 128, out var promptVersion)
                || !root.TryGetProperty("claims", out var claimsElement)
                || claimsElement.ValueKind != JsonValueKind.Array
                || claimsElement.GetArrayLength() == 0
                || claimsElement.GetArrayLength() > MaxClaims)
            {
                return Rejected(ResearchStructuredSummaryCode.InvalidSchema);
            }

            var claims = new List<ResearchStructuredClaim>(claimsElement.GetArrayLength());
            foreach (var claimElement in claimsElement.EnumerateArray())
            {
                if (claimElement.ValueKind != JsonValueKind.Object
                    || !HasOnlyProperties(claimElement, AllowedClaimProperties)
                    || !TryReadText(claimElement, "factKey", 256, out var factKey)
                    || !TryReadText(claimElement, "normalizedValue", 4096, out var normalizedValue)
                    || !claimElement.TryGetProperty("confidence", out var confidenceElement)
                    || confidenceElement.ValueKind != JsonValueKind.Number
                    || !confidenceElement.TryGetDouble(out var confidence)
                    || !double.IsFinite(confidence)
                    || confidence < 0d
                    || confidence > 1d
                    || !claimElement.TryGetProperty("evidenceIds", out var evidenceIdsElement)
                    || evidenceIdsElement.ValueKind != JsonValueKind.Array
                    || evidenceIdsElement.GetArrayLength() == 0
                    || evidenceIdsElement.GetArrayLength() > MaxEvidencePerClaim)
                {
                    return Rejected(ResearchStructuredSummaryCode.InvalidSchema);
                }

                var claimEvidence = new List<ResearchEvidenceEnvelope>(
                    evidenceIdsElement.GetArrayLength());
                var seenEvidence = new HashSet<string>(StringComparer.Ordinal);
                foreach (var evidenceIdElement in evidenceIdsElement.EnumerateArray())
                {
                    if (evidenceIdElement.ValueKind != JsonValueKind.String)
                    {
                        return Rejected(ResearchStructuredSummaryCode.InvalidSchema);
                    }

                    var evidenceId = evidenceIdElement.GetString();
                    if (!ResearchIdentityRules.IsValidText(evidenceId, 128)
                        || !seenEvidence.Add(evidenceId!)
                        || !evidenceById.TryGetValue(evidenceId!, out var evidence))
                    {
                        return Rejected(ResearchStructuredSummaryCode.UnsupportedEvidence);
                    }

                    claimEvidence.Add(evidence);
                }

                claims.Add(new ResearchStructuredClaim(
                    factKey!,
                    normalizedValue!,
                    confidence,
                    Array.AsReadOnly(claimEvidence.ToArray())));
            }

            return new ResearchStructuredSummaryResult(
                true,
                ResearchStructuredSummaryCode.Created,
                new ResearchStructuredSummary(
                    schemaVersion!,
                    modelVersion!,
                    promptVersion!,
                    Array.AsReadOnly(claims.ToArray())));
        }
        catch (JsonException)
        {
            return Rejected(ResearchStructuredSummaryCode.InvalidJson);
        }
    }

    private static bool HasOnlyProperties(
        JsonElement element,
        HashSet<string> allowedProperties)
    {
        var seen = new HashSet<string>(StringComparer.Ordinal);
        foreach (var property in element.EnumerateObject())
        {
            if (!allowedProperties.Contains(property.Name)
                || !seen.Add(property.Name))
            {
                return false;
            }
        }

        return seen.Count == allowedProperties.Count;
    }

    private static bool TryReadText(
        JsonElement element,
        string propertyName,
        int maximumLength,
        out string? value)
    {
        value = null;
        if (!element.TryGetProperty(propertyName, out var property)
            || property.ValueKind != JsonValueKind.String)
        {
            return false;
        }

        value = property.GetString();
        return ResearchIdentityRules.IsValidText(value, maximumLength);
    }

    private static ResearchStructuredSummaryResult Rejected(
        ResearchStructuredSummaryCode code)
    {
        return new ResearchStructuredSummaryResult(false, code, null);
    }
}
