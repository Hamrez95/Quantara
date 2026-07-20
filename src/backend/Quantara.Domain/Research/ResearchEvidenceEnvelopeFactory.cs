using Quantara.Domain.Trading;

namespace Quantara.Domain.Research;

public static class ResearchEvidenceEnvelopeFactory
{
    public static ResearchEvidenceBuildResult Create(
        string evidenceId,
        ResearchSourceRegistrySnapshot? registry,
        string sourceId,
        string providerItemId,
        DateTimeOffset retrievedAt,
        DateTimeOffset? publishedAt,
        DateTimeOffset? eventAt,
        string rawSha256,
        string normalizedSha256,
        string schemaVersion,
        ResearchEvidenceKind kind,
        IReadOnlyList<Symbol> affectedSymbols,
        DateTimeOffset? expiresAt = null,
        string? extractionModelVersion = null,
        string? promptVersion = null)
    {
        var rejections = new HashSet<ResearchEvidenceCode>();

        if (!ResearchIdentityRules.IsValidText(evidenceId, 128)
            || !ResearchIdentityRules.IsValidText(providerItemId, 512))
        {
            rejections.Add(ResearchEvidenceCode.InvalidEvidenceIdentity);
        }

        RegisteredResearchSource? source = null;
        if (registry is null
            || !registry.TryGetSource(sourceId, out source))
        {
            rejections.Add(ResearchEvidenceCode.InvalidSourceIdentity);
        }

        var retrievedAtUtc = retrievedAt.ToUniversalTime();
        var publishedAtUtc = publishedAt?.ToUniversalTime();
        var eventAtUtc = eventAt?.ToUniversalTime();
        var expiresAtUtc = expiresAt?.ToUniversalTime();
        if (retrievedAtUtc == default
            || (publishedAtUtc.HasValue && publishedAtUtc.Value > retrievedAtUtc)
            || (expiresAtUtc.HasValue && expiresAtUtc.Value <= retrievedAtUtc)
            || !IsValidEventTimestamp(
                kind,
                eventAtUtc,
                expiresAtUtc,
                retrievedAtUtc))
        {
            rejections.Add(ResearchEvidenceCode.InvalidTimestamp);
        }

        if (registry is not null && registry.IsExpiredAt(retrievedAtUtc))
        {
            rejections.Add(ResearchEvidenceCode.RegistryExpired);
        }

        if (source is not null)
        {
            if (!source.IsEnabled)
            {
                rejections.Add(ResearchEvidenceCode.SourceDisabled);
            }

            if (source.CommercialUseStatus
                == ResearchCommercialUseStatus.BlockedPendingLicense)
            {
                rejections.Add(ResearchEvidenceCode.SourceLicenseBlocked);
            }
        }

        if (!ResearchIdentityRules.IsSha256(rawSha256)
            || !ResearchIdentityRules.IsSha256(normalizedSha256))
        {
            rejections.Add(ResearchEvidenceCode.InvalidHash);
        }

        if (!ResearchIdentityRules.IsValidText(schemaVersion, 128))
        {
            rejections.Add(ResearchEvidenceCode.InvalidSchemaVersion);
        }

        if (!IsValidSymbols(affectedSymbols, kind))
        {
            rejections.Add(ResearchEvidenceCode.InvalidSymbols);
        }

        if (!IsValidExtractionMetadata(extractionModelVersion, promptVersion))
        {
            rejections.Add(ResearchEvidenceCode.InvalidExtractionMetadata);
        }

        if (!Enum.IsDefined(typeof(ResearchEvidenceKind), kind)
            || source is null
            || !IsCompatible(source.DecisionRole, kind))
        {
            rejections.Add(ResearchEvidenceCode.IncompatibleDecisionRole);
        }

        if (rejections.Count > 0)
        {
            return new ResearchEvidenceBuildResult(
                false,
                Array.AsReadOnly(rejections.Order().ToArray()),
                null);
        }

        var validatedRegistry = registry!;
        var validatedSource = source!;
        return new ResearchEvidenceBuildResult(
            true,
            Array.Empty<ResearchEvidenceCode>(),
            new ResearchEvidenceEnvelope(
                evidenceId,
                validatedRegistry.RegistryVersion,
                validatedRegistry.RegistrySha256,
                validatedSource,
                providerItemId,
                retrievedAtUtc,
                publishedAtUtc,
                eventAtUtc,
                rawSha256,
                normalizedSha256,
                schemaVersion,
                kind,
                affectedSymbols,
                expiresAtUtc,
                extractionModelVersion,
                promptVersion));
    }

    private static bool IsValidEventTimestamp(
        ResearchEvidenceKind kind,
        DateTimeOffset? eventAt,
        DateTimeOffset? expiresAt,
        DateTimeOffset retrievedAt)
    {
        if (kind == ResearchEvidenceKind.ScheduledEvent)
        {
            return eventAt.HasValue
                && eventAt.Value > retrievedAt
                && expiresAt.HasValue
                && expiresAt.Value >= eventAt.Value;
        }

        return !eventAt.HasValue || eventAt.Value <= retrievedAt;
    }

    private static bool IsValidSymbols(
        IReadOnlyList<Symbol>? symbols,
        ResearchEvidenceKind kind)
    {
        if (symbols is null
            || symbols.Any(static symbol => ReferenceEquals(symbol, null)))
        {
            return false;
        }

        var requiresSymbol = kind is ResearchEvidenceKind.OfficialFact
            or ResearchEvidenceKind.ScheduledEvent
            or ResearchEvidenceKind.FeatureObservation
            or ResearchEvidenceKind.CandidateHypothesis;
        if (requiresSymbol && symbols.Count == 0)
        {
            return false;
        }

        return symbols.Distinct().Count() == symbols.Count;
    }

    private static bool IsValidExtractionMetadata(
        string? extractionModelVersion,
        string? promptVersion)
    {
        if (extractionModelVersion is null && promptVersion is null)
        {
            return true;
        }

        return ResearchIdentityRules.IsValidText(extractionModelVersion, 128)
            && ResearchIdentityRules.IsValidText(promptVersion, 128);
    }

    private static bool IsCompatible(
        ResearchDecisionRole decisionRole,
        ResearchEvidenceKind kind)
    {
        return decisionRole switch
        {
            ResearchDecisionRole.DirectFact =>
                kind is ResearchEvidenceKind.OfficialFact
                    or ResearchEvidenceKind.ScheduledEvent,
            ResearchDecisionRole.FeatureInput =>
                kind == ResearchEvidenceKind.FeatureObservation,
            ResearchDecisionRole.ValidationMethod =>
                kind == ResearchEvidenceKind.CandidateHypothesis,
            ResearchDecisionRole.HypothesisOnly =>
                kind == ResearchEvidenceKind.CandidateHypothesis,
            ResearchDecisionRole.ComplianceOnly =>
                kind == ResearchEvidenceKind.ComplianceDecision,
            _ => false
        };
    }
}
