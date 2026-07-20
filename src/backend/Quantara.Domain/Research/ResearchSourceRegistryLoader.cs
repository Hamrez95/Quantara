using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace Quantara.Domain.Research;

internal static class ResearchSourceRegistryLoader
{
    private static readonly HashSet<string> RootFields = new(
        [
            "schema_version",
            "registry_version",
            "reviewed_at",
            "review_due_at",
            "execution_authority",
            "sources"
        ],
        StringComparer.Ordinal);

    private static readonly HashSet<string> RequiredSourceFields = new(
        [
            "id",
            "title",
            "publisher",
            "canonical_url",
            "terms_urls",
            "source_class",
            "authority_tier",
            "access_class",
            "ingestion_mode",
            "decision_role",
            "commercial_use_status",
            "update_cadence",
            "domains",
            "permitted_uses",
            "prohibited_uses",
            "validation_requirements",
            "attribution_required",
            "automated_scraping_allowed",
            "retention_policy",
            "revision_policy",
            "enabled"
        ],
        StringComparer.Ordinal);

    private static readonly HashSet<string> AllowedSourceFields = new(
        RequiredSourceFields.Append("notes"),
        StringComparer.Ordinal);

    public static ResearchSourceRegistryBuildResult Load(
        string registryDocument,
        string trustedRegistrySha256,
        DateTimeOffset loadedAt)
    {
        if (string.IsNullOrWhiteSpace(registryDocument)
            || !ResearchIdentityRules.IsSha256(trustedRegistrySha256))
        {
            return Rejected(ResearchSourceRegistryCode.InvalidDocument);
        }

        var actualSha256 = Convert.ToHexString(
                SHA256.HashData(Encoding.UTF8.GetBytes(registryDocument)))
            .ToLowerInvariant();
        if (!string.Equals(
            actualSha256,
            trustedRegistrySha256,
            StringComparison.Ordinal))
        {
            return Rejected(ResearchSourceRegistryCode.InvalidRegistryHash);
        }

        try
        {
            using var document = JsonDocument.Parse(registryDocument);
            var root = document.RootElement;
            if (root.ValueKind != JsonValueKind.Object
                || !HasExactProperties(root, RootFields, RootFields))
            {
                return Rejected(ResearchSourceRegistryCode.InvalidDocument);
            }

            if (!TryGetRequiredString(root, "schema_version", 64, out var schemaVersion)
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
                    32,
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
                    64,
                    out var registryVersion)
                || !TryGetDate(root, "reviewed_at", out var reviewedAt)
                || !TryGetDate(root, "review_due_at", out var reviewDueAt)
                || !root.TryGetProperty("sources", out var sourcesElement)
                || sourcesElement.ValueKind != JsonValueKind.Array
                || sourcesElement.GetArrayLength() == 0)
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
            || !HasExactProperties(
                element,
                RequiredSourceFields,
                AllowedSourceFields)
            || !TryGetRequiredString(element, "id", 128, out var sourceId)
            || !TryGetRequiredString(element, "title", 200, out _)
            || !TryGetRequiredString(element, "publisher", 160, out _)
            || !TryGetSecureUri(element, "canonical_url", out var canonicalUri)
            || !TryGetSecureUriArray(element, "terms_urls", out var termsUris)
            || !TryGetRequiredString(
                element,
                "source_class",
                64,
                out var sourceClassText)
            || !TryParseSourceClass(sourceClassText, out var sourceClass)
            || !TryGetRequiredString(
                element,
                "authority_tier",
                64,
                out var authorityTierText)
            || !TryParseAuthorityTier(authorityTierText, out var authorityTier)
            || !TryGetRequiredString(
                element,
                "access_class",
                64,
                out var accessClassText)
            || !TryParseAccessClass(accessClassText, out var accessClass)
            || !TryGetRequiredString(
                element,
                "ingestion_mode",
                64,
                out var ingestionModeText)
            || !TryParseIngestionMode(ingestionModeText, out var ingestionMode)
            || !TryGetRequiredString(
                element,
                "decision_role",
                64,
                out var decisionRoleText)
            || !TryParseDecisionRole(decisionRoleText, out var decisionRole)
            || !TryGetRequiredString(
                element,
                "commercial_use_status",
                64,
                out var commercialUseText)
            || !TryParseCommercialUseStatus(
                commercialUseText,
                out var commercialUseStatus)
            || !TryGetRequiredString(element, "update_cadence", 100, out _)
            || !TryGetNonEmptyStringArray(element, "domains", 240)
            || !TryGetNonEmptyStringArray(element, "permitted_uses", 240)
            || !TryGetNonEmptyStringArray(element, "prohibited_uses", 240)
            || !TryGetNonEmptyStringArray(
                element,
                "validation_requirements",
                240)
            || !TryGetRequiredBoolean(
                element,
                "attribution_required",
                out var attributionRequired)
            || !TryGetRequiredBoolean(
                element,
                "automated_scraping_allowed",
                out var automatedScrapingAllowed)
            || !TryGetRequiredString(element, "retention_policy", 300, out _)
            || !TryGetRequiredString(element, "revision_policy", 300, out _)
            || !TryGetRequiredBoolean(element, "enabled", out var enabled)
            || !TryGetOptionalString(element, "notes", 500))
        {
            return false;
        }

        source = new RegisteredResearchSource(
            sourceId,
            canonicalUri,
            termsUris,
            sourceClass,
            authorityTier,
            accessClass,
            ingestionMode,
            decisionRole,
            commercialUseStatus,
            attributionRequired,
            automatedScrapingAllowed,
            enabled);
        return true;
    }

    private static bool HasExactProperties(
        JsonElement element,
        HashSet<string> required,
        HashSet<string> allowed)
    {
        var observed = new HashSet<string>(StringComparer.Ordinal);
        foreach (var property in element.EnumerateObject())
        {
            if (!allowed.Contains(property.Name)
                || !observed.Add(property.Name))
            {
                return false;
            }
        }

        return required.All(observed.Contains);
    }

    private static bool TryGetRequiredString(
        JsonElement element,
        string propertyName,
        int maximumLength,
        out string value)
    {
        value = string.Empty;
        if (!element.TryGetProperty(propertyName, out var property)
            || property.ValueKind != JsonValueKind.String)
        {
            return false;
        }

        var resolved = property.GetString();
        if (!ResearchIdentityRules.IsValidText(resolved, maximumLength))
        {
            return false;
        }

        value = resolved!;
        return true;
    }

    private static bool TryGetOptionalString(
        JsonElement element,
        string propertyName,
        int maximumLength)
    {
        return !element.TryGetProperty(propertyName, out var property)
            || property.ValueKind == JsonValueKind.String
                && ResearchIdentityRules.IsValidText(
                    property.GetString(),
                    maximumLength);
    }

    private static bool TryGetRequiredBoolean(
        JsonElement element,
        string propertyName,
        out bool value)
    {
        value = false;
        if (!element.TryGetProperty(propertyName, out var property)
            || property.ValueKind is not JsonValueKind.True
                and not JsonValueKind.False)
        {
            return false;
        }

        value = property.GetBoolean();
        return true;
    }

    private static bool TryGetSecureUri(
        JsonElement element,
        string propertyName,
        out Uri uri)
    {
        uri = null!;
        if (!TryGetRequiredString(element, propertyName, 2048, out var text)
            || !Uri.TryCreate(text, UriKind.Absolute, out var resolvedUri)
            || resolvedUri is null
            || !ResearchIdentityRules.IsSecureHttpsUri(resolvedUri))
        {
            return false;
        }

        uri = resolvedUri;
        return true;
    }

    private static bool TryGetSecureUriArray(
        JsonElement element,
        string propertyName,
        out IReadOnlyList<Uri> uris)
    {
        uris = Array.Empty<Uri>();
        if (!element.TryGetProperty(propertyName, out var property)
            || property.ValueKind != JsonValueKind.Array)
        {
            return false;
        }

        var values = new List<Uri>();
        var unique = new HashSet<string>(StringComparer.Ordinal);
        foreach (var item in property.EnumerateArray())
        {
            if (item.ValueKind != JsonValueKind.String
                || !Uri.TryCreate(
                    item.GetString(),
                    UriKind.Absolute,
                    out var resolvedUri)
                || resolvedUri is null
                || !ResearchIdentityRules.IsSecureHttpsUri(resolvedUri)
                || !unique.Add(resolvedUri.AbsoluteUri))
            {
                return false;
            }

            values.Add(resolvedUri);
        }

        uris = Array.AsReadOnly(values.ToArray());
        return true;
    }

    private static bool TryGetNonEmptyStringArray(
        JsonElement element,
        string propertyName,
        int maximumItemLength)
    {
        if (!element.TryGetProperty(propertyName, out var property)
            || property.ValueKind != JsonValueKind.Array
            || property.GetArrayLength() == 0)
        {
            return false;
        }

        var unique = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var item in property.EnumerateArray())
        {
            if (item.ValueKind != JsonValueKind.String
                || !ResearchIdentityRules.IsValidText(
                    item.GetString(),
                    maximumItemLength)
                || !unique.Add(item.GetString()!))
            {
                return false;
            }
        }

        return true;
    }

    private static bool TryGetDate(
        JsonElement element,
        string propertyName,
        out DateTimeOffset value)
    {
        value = default;
        if (!TryGetRequiredString(element, propertyName, 10, out var text)
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

    private static bool TryParseSourceClass(
        string value,
        out ResearchSourceClass sourceClass)
    {
        sourceClass = value switch
        {
            "official_event_data" => ResearchSourceClass.OfficialEventData,
            "live_market_data" => ResearchSourceClass.LiveMarketData,
            "research_evidence" => ResearchSourceClass.ResearchEvidence,
            "educational_hypothesis" =>
                ResearchSourceClass.EducationalHypothesis,
            "compliance_policy" => ResearchSourceClass.CompliancePolicy,
            _ => default
        };
        return value is "official_event_data"
            or "live_market_data"
            or "research_evidence"
            or "educational_hypothesis"
            or "compliance_policy";
    }

    private static bool TryParseAuthorityTier(
        string value,
        out ResearchAuthorityTier authorityTier)
    {
        authorityTier = value switch
        {
            "official_primary" => ResearchAuthorityTier.OfficialPrimary,
            "professional_standard" =>
                ResearchAuthorityTier.ProfessionalStandard,
            "peer_reviewed_or_scholarly" =>
                ResearchAuthorityTier.PeerReviewedOrScholarly,
            "publisher_reference" => ResearchAuthorityTier.PublisherReference,
            "vendor_primary" => ResearchAuthorityTier.VendorPrimary,
            "creator_hypothesis" => ResearchAuthorityTier.CreatorHypothesis,
            "compliance_authority" =>
                ResearchAuthorityTier.ComplianceAuthority,
            _ => default
        };
        return value is "official_primary"
            or "professional_standard"
            or "peer_reviewed_or_scholarly"
            or "publisher_reference"
            or "vendor_primary"
            or "creator_hypothesis"
            or "compliance_authority";
    }

    private static bool TryParseAccessClass(
        string value,
        out ResearchAccessClass accessClass)
    {
        accessClass = value switch
        {
            "public_api_with_terms" => ResearchAccessClass.PublicApiWithTerms,
            "public_web_reference" => ResearchAccessClass.PublicWebReference,
            "community_noncommercial" =>
                ResearchAccessClass.CommunityNoncommercial,
            "copyrighted_reference" =>
                ResearchAccessClass.CopyrightedReference,
            "restricted_paid" => ResearchAccessClass.RestrictedPaid,
            "user_supplied_licensed" =>
                ResearchAccessClass.UserSuppliedLicensed,
            _ => default
        };
        return value is "public_api_with_terms"
            or "public_web_reference"
            or "community_noncommercial"
            or "copyrighted_reference"
            or "restricted_paid"
            or "user_supplied_licensed";
    }

    private static bool TryParseIngestionMode(
        string value,
        out ResearchIngestionMode ingestionMode)
    {
        ingestionMode = value switch
        {
            "api" => ResearchIngestionMode.Api,
            "youtube_api_metadata" =>
                ResearchIngestionMode.YoutubeApiMetadata,
            "manual_metadata" => ResearchIngestionMode.ManualMetadata,
            "citation_only" => ResearchIngestionMode.CitationOnly,
            "no_ingestion" => ResearchIngestionMode.NoIngestion,
            _ => default
        };
        return value is "api"
            or "youtube_api_metadata"
            or "manual_metadata"
            or "citation_only"
            or "no_ingestion";
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
