using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace Quantara.Domain.Research;

public static class ResearchSourceRegistryLoader
{
    public static ResearchSourceRegistryBuildResult Load(
        string registryDocument,
        string expectedRegistrySha256,
        DateTimeOffset loadedAt)
    {
        if (string.IsNullOrWhiteSpace(registryDocument)
            || !ResearchIdentityRules.IsSha256(expectedRegistrySha256))
        {
            return Rejected(ResearchSourceRegistryCode.InvalidDocument);
        }

        var actualSha256 = Convert.ToHexString(
                SHA256.HashData(Encoding.UTF8.GetBytes(registryDocument)))
            .ToLowerInvariant();
        if (!string.Equals(
            actualSha256,
            expectedRegistrySha256,
            StringComparison.Ordinal))
        {
            return Rejected(ResearchSourceRegistryCode.InvalidRegistryHash);
        }

        try
        {
            using var document = JsonDocument.Parse(registryDocument);
            var root = document.RootElement;
            if (root.ValueKind != JsonValueKind.Object)
            {
                return Rejected(ResearchSourceRegistryCode.InvalidDocument);
            }

            if (!TryGetRequiredString(root, "schema_version", out var schemaVersion)
                || !string.Equals(
                    schemaVersion,
                    "source-registry-v1",
                    StringComparison.Ordinal))
            {
                return Rejected(ResearchSourceRegistryCode.UnsupportedSchema);
            }

            if (!TryGetRequiredString(
                    root,
                    "execution_authority",
                    out var executionAuthority)
                || !string.Equals(
                    executionAuthority,
                    "none",
                    StringComparison.Ordinal))
            {
                return Rejected(
                    ResearchSourceRegistryCode.ExecutionAuthorityViolation);
            }

            if (!TryGetRequiredString(
                    root,
                    "registry_version",
                    out var registryVersion)
                || !TryGetDate(root, "reviewed_at", out var reviewedAt)
                || !TryGetDate(root, "review_due_at", out var reviewDueAt)
                || !root.TryGetProperty("sources", out var sourcesElement)
                || sourcesElement.ValueKind != JsonValueKind.Array)
            {
                return Rejected(ResearchSourceRegistryCode.InvalidDocument);
            }

            var sources = new List<RegisteredResearchSource>();
            foreach (var sourceElement in sourcesElement.EnumerateArray())
            {
                if (!TryParseSource(sourceElement, out var source))
                {
                    return Rejected(ResearchSourceRegistryCode.InvalidSources);
                }

                sources.Add(source);
            }

            var result = ResearchSourceRegistrySnapshotFactory.Create(
                registryVersion,
                actualSha256,
                reviewedAt,
                reviewDueAt,
                sources);
            if (!result.IsCreated || result.Snapshot is null)
            {
                return result;
            }

            if (result.Snapshot.IsExpiredAt(loadedAt))
            {
                return Rejected(ResearchSourceRegistryCode.RegistryExpired);
            }

            return result;
        }
        catch (JsonException)
        {
            return Rejected(ResearchSourceRegistryCode.InvalidDocument);
        }
        catch (FormatException)
        {
            return Rejected(ResearchSourceRegistryCode.InvalidDocument);
        }
        catch (OverflowException)
        {
            return Rejected(ResearchSourceRegistryCode.InvalidDocument);
        }
    }

    private static bool TryParseSource(
        JsonElement element,
        out RegisteredResearchSource source)
    {
        source = null!;
        if (element.ValueKind != JsonValueKind.Object
            || !TryGetRequiredString(element, "id", out var sourceId)
            || !TryGetRequiredString(
                element,
                "canonical_url",
                out var canonicalUrl)
            || !Uri.TryCreate(canonicalUrl, UriKind.Absolute, out var canonicalUri)
            || !TryGetRequiredString(
                element,
                "decision_role",
                out var decisionRoleText)
            || !TryParseDecisionRole(decisionRoleText, out var decisionRole)
            || !TryGetRequiredString(
                element,
                "commercial_use_status",
                out var commercialUseText)
            || !TryParseCommercialUseStatus(
                commercialUseText,
                out var commercialUseStatus)
            || !element.TryGetProperty("enabled", out var enabledElement)
            || enabledElement.ValueKind is not JsonValueKind.True
                and not JsonValueKind.False)
        {
            return false;
        }

        source = new RegisteredResearchSource(
            sourceId,
            canonicalUri,
            decisionRole,
            commercialUseStatus,
            enabledElement.GetBoolean());
        return true;
    }

    private static bool TryGetRequiredString(
        JsonElement element,
        string propertyName,
        out string value)
    {
        value = string.Empty;
        if (!element.TryGetProperty(propertyName, out var property)
            || property.ValueKind != JsonValueKind.String)
        {
            return false;
        }

        var resolved = property.GetString();
        if (string.IsNullOrWhiteSpace(resolved))
        {
            return false;
        }

        value = resolved;
        return true;
    }

    private static bool TryGetDate(
        JsonElement element,
        string propertyName,
        out DateTimeOffset value)
    {
        value = default;
        if (!TryGetRequiredString(element, propertyName, out var text)
            || !DateOnly.TryParseExact(
                text,
                "yyyy-MM-dd",
                CultureInfo.InvariantCulture,
                DateTimeStyles.None,
                out var date))
        {
            return false;
        }

        value = new DateTimeOffset(
            date.ToDateTime(TimeOnly.MinValue, DateTimeKind.Utc));
        return true;
    }

    private static bool TryParseDecisionRole(
        string value,
        out ResearchDecisionRole role)
    {
        role = value switch
        {
            "direct_fact" => ResearchDecisionRole.DirectFact,
            "feature_input" => ResearchDecisionRole.FeatureInput,
            "validation_method" => ResearchDecisionRole.ValidationMethod,
            "hypothesis_only" => ResearchDecisionRole.HypothesisOnly,
            "compliance_only" => ResearchDecisionRole.ComplianceOnly,
            _ => default
        };
        return value is "direct_fact"
            or "feature_input"
            or "validation_method"
            or "hypothesis_only"
            or "compliance_only";
    }

    private static bool TryParseCommercialUseStatus(
        string value,
        out ResearchCommercialUseStatus status)
    {
        status = value switch
        {
            "approved_subject_to_terms" =>
                ResearchCommercialUseStatus.ApprovedSubjectToTerms,
            "blocked_pending_license" =>
                ResearchCommercialUseStatus.BlockedPendingLicense,
            "citation_only" => ResearchCommercialUseStatus.CitationOnly,
            "not_applicable" => ResearchCommercialUseStatus.NotApplicable,
            _ => default
        };
        return value is "approved_subject_to_terms"
            or "blocked_pending_license"
            or "citation_only"
            or "not_applicable";
    }

    private static ResearchSourceRegistryBuildResult Rejected(
        ResearchSourceRegistryCode code)
    {
        return new ResearchSourceRegistryBuildResult(
            false,
            Array.AsReadOnly([code]),
            null);
    }
}
