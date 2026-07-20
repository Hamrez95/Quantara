using Quantara.Domain.Trading;

namespace Quantara.Domain.Research;

public static class ResearchEvidenceEnvelopeFactory
{
    public static ResearchEvidenceBuildResult Create(
        string evidenceId,
        RegisteredResearchSource source,
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

        if (!IsValidText(evidenceId, 128)
            || !IsValidText(providerItemId, 512))
        {
            rejections.Add(ResearchEvidenceCode.InvalidEvidenceIdentity);
        }

        if (!IsValidSource(source))
        {
            rejections.Add(ResearchEvidenceCode.InvalidSourceIdentity);
        }

        var retrievedAtUtc = retrievedAt.ToUniversalTime();
        var publishedAtUtc = publishedAt?.ToUniversalTime();
        var expiresAtUtc = expiresAt?.ToUniversalTime();
        if ((publishedAtUtc.HasValue && publishedAtUtc.Value > retrievedAtUtc)
            || (expiresAtUtc.HasValue && expiresAtUtc.Value <= retrievedAtUtc))
        {
            rejections.Add(ResearchEvidenceCode.InvalidTimestamp);
        }

        if (!IsSha256(rawSha256) || !IsSha256(normalizedSha256))
        {
            rejections.Add(ResearchEvidenceCode.InvalidHash);
        }

        if (!IsValidText(schemaVersion, 128))
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

        return new ResearchEvidenceBuildResult(
            true,
            Array.Empty<ResearchEvidenceCode>(),
            new ResearchEvidenceEnvelope(
                evidenceId,
                source,
                providerItemId,
                retrievedAtUtc,
                publishedAtUtc,
                eventAt?.ToUniversalTime(),
                rawSha256,
                normalizedSha256,
                schemaVersion,
                kind,
                affectedSymbols,
                expiresAtUtc,
                extractionModelVersion,
                promptVersion));
    }

    private static bool IsValidSource(RegisteredResearchSource? source)
    {
        return source is not null
            && IsSemanticVersion(source.RegistryVersion)
            && IsKebabIdentifier(source.SourceId)
            && source.CanonicalUri is not null
            && source.CanonicalUri.IsAbsoluteUri
            && string.Equals(
                source.CanonicalUri.Scheme,
                Uri.UriSchemeHttps,
                StringComparison.OrdinalIgnoreCase)
            && string.IsNullOrEmpty(source.CanonicalUri.UserInfo)
            && Enum.IsDefined(typeof(ResearchDecisionRole), source.DecisionRole);
    }

    private static bool IsSemanticVersion(string? value)
    {
        if (value is null || !IsValidText(value, 64))
        {
            return false;
        }

        var components = value.Split('.', StringSplitOptions.None);
        return components.Length == 3
            && components.All(component =>
                component.Length > 0
                && component.All(char.IsAsciiDigit)
                && (component.Length == 1 || component[0] != '0'));
    }

    private static bool IsKebabIdentifier(string? value)
    {
        if (value is null
            || !IsValidText(value, 128)
            || value[0] == '-'
            || value[^1] == '-')
        {
            return false;
        }

        var previousWasSeparator = false;
        foreach (var character in value)
        {
            if (character == '-')
            {
                if (previousWasSeparator)
                {
                    return false;
                }

                previousWasSeparator = true;
                continue;
            }

            if (!char.IsAsciiLetterLower(character)
                && !char.IsAsciiDigit(character))
            {
                return false;
            }

            previousWasSeparator = false;
        }

        return true;
    }

    private static bool IsSha256(string? value)
    {
        return value is not null
            && value.Length == 64
            && value.All(character =>
                char.IsAsciiDigit(character)
                || character is >= 'a' and <= 'f');
    }

    private static bool IsValidText(string? value, int maximumLength)
    {
        return !string.IsNullOrWhiteSpace(value)
            && value.Length <= maximumLength
            && string.Equals(value, value.Trim(), StringComparison.Ordinal);
    }

    private static bool IsValidSymbols(
        IReadOnlyList<Symbol>? symbols,
        ResearchEvidenceKind kind)
    {
        if (symbols is null)
        {
            return false;
        }

        var requiresSymbol = kind is ResearchEvidenceKind.OfficialFact
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

        return IsValidText(extractionModelVersion, 128)
            && IsValidText(promptVersion, 128);
    }

    private static bool IsCompatible(
        ResearchDecisionRole decisionRole,
        ResearchEvidenceKind kind)
    {
        return decisionRole switch
        {
            ResearchDecisionRole.DirectFact =>
                kind == ResearchEvidenceKind.OfficialFact,
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
