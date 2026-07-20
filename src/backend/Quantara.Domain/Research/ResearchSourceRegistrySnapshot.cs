using System.Diagnostics.CodeAnalysis;

namespace Quantara.Domain.Research;

public enum ResearchSourceRegistryCode
{
    Created,
    InvalidDocument,
    UnsupportedSchema,
    ExecutionAuthorityViolation,
    InvalidRegistryIdentity,
    InvalidRegistryHash,
    InvalidReviewWindow,
    RegistryExpired,
    InvalidSources,
    DuplicateSourceId,
    InvalidSourcePolicy
}

public sealed record ResearchSourceRegistryBuildResult(
    bool IsCreated,
    IReadOnlyList<ResearchSourceRegistryCode> RejectionReasons,
    ResearchSourceRegistrySnapshot? Snapshot);

public sealed class ResearchSourceRegistrySnapshot
{
    private readonly Dictionary<string, RegisteredResearchSource> _sources;

    internal ResearchSourceRegistrySnapshot(
        string registryVersion,
        string registrySha256,
        DateTimeOffset reviewedAt,
        DateTimeOffset reviewDueAt,
        IReadOnlyDictionary<string, RegisteredResearchSource> sources)
    {
        RegistryVersion = registryVersion;
        RegistrySha256 = registrySha256;
        ReviewedAt = reviewedAt.ToUniversalTime();
        ReviewDueAt = reviewDueAt.ToUniversalTime();
        _sources = new Dictionary<string, RegisteredResearchSource>(
            sources,
            StringComparer.Ordinal);
    }

    public string RegistryVersion { get; }

    public string RegistrySha256 { get; }

    public DateTimeOffset ReviewedAt { get; }

    public DateTimeOffset ReviewDueAt { get; }

    public IReadOnlyCollection<RegisteredResearchSource> Sources =>
        Array.AsReadOnly(_sources.Values.ToArray());

    public bool IsExpiredAt(DateTimeOffset timestamp)
    {
        return timestamp.ToUniversalTime().Date > ReviewDueAt.Date;
    }

    public bool TryGetSource(
        string sourceId,
        [NotNullWhen(true)] out RegisteredResearchSource? source)
    {
        if (!ResearchIdentityRules.IsKebabIdentifier(sourceId))
        {
            source = null;
            return false;
        }

        return _sources.TryGetValue(sourceId, out source);
    }
}

internal static class ResearchSourceRegistrySnapshotFactory
{
    public static ResearchSourceRegistryBuildResult Create(
        string registryVersion,
        string registrySha256,
        DateTimeOffset reviewedAt,
        DateTimeOffset reviewDueAt,
        IReadOnlyList<RegisteredResearchSource>? sources)
    {
        var rejections = new HashSet<ResearchSourceRegistryCode>();

        if (!ResearchIdentityRules.IsSemanticVersion(registryVersion))
        {
            rejections.Add(ResearchSourceRegistryCode.InvalidRegistryIdentity);
        }

        if (!ResearchIdentityRules.IsSha256(registrySha256))
        {
            rejections.Add(ResearchSourceRegistryCode.InvalidRegistryHash);
        }

        var reviewedAtUtc = reviewedAt.ToUniversalTime();
        var reviewDueAtUtc = reviewDueAt.ToUniversalTime();
        if (reviewDueAtUtc.Date < reviewedAtUtc.Date
            || reviewDueAtUtc.Date > reviewedAtUtc.Date.AddDays(180))
        {
            rejections.Add(ResearchSourceRegistryCode.InvalidReviewWindow);
        }

        var sourceMap = new Dictionary<string, RegisteredResearchSource>(
            StringComparer.Ordinal);
        if (sources is null || sources.Count == 0)
        {
            rejections.Add(ResearchSourceRegistryCode.InvalidSources);
        }
        else
        {
            foreach (var source in sources)
            {
                if (!IsValidSource(source))
                {
                    rejections.Add(ResearchSourceRegistryCode.InvalidSources);
                    continue;
                }

                if (source.IsEnabled
                    && source.CommercialUseStatus
                        == ResearchCommercialUseStatus.BlockedPendingLicense)
                {
                    rejections.Add(ResearchSourceRegistryCode.InvalidSourcePolicy);
                }

                if (!sourceMap.TryAdd(source.SourceId, source))
                {
                    rejections.Add(ResearchSourceRegistryCode.DuplicateSourceId);
                }
            }
        }

        if (rejections.Count > 0)
        {
            return new ResearchSourceRegistryBuildResult(
                false,
                Array.AsReadOnly(rejections.Order().ToArray()),
                null);
        }

        return new ResearchSourceRegistryBuildResult(
            true,
            Array.Empty<ResearchSourceRegistryCode>(),
            new ResearchSourceRegistrySnapshot(
                registryVersion,
                registrySha256,
                reviewedAtUtc,
                reviewDueAtUtc,
                sourceMap));
    }

    private static bool IsValidSource(RegisteredResearchSource? source)
    {
        return source is not null
            && ResearchIdentityRules.IsKebabIdentifier(source.SourceId)
            && ResearchIdentityRules.IsSecureHttpsUri(source.CanonicalUri)
            && Enum.IsDefined(typeof(ResearchDecisionRole), source.DecisionRole)
            && Enum.IsDefined(
                typeof(ResearchCommercialUseStatus),
                source.CommercialUseStatus);
    }
}
