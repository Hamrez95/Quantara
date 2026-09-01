namespace Quantara.Domain.Research;

public enum ResearchEventClusteringCode
{
    Created,
    InvalidInput,
    TooManyItems
}

public sealed record ResearchEventCluster(
    string ClusterId,
    ResearchEvidenceEnvelope CanonicalEvidence,
    IReadOnlyList<ResearchEvidenceEnvelope> UniqueEvidence,
    IReadOnlyList<ResearchEvidenceEnvelope> DuplicateEvidence);

public sealed record ResearchEventClusteringResult(
    bool IsCreated,
    ResearchEventClusteringCode Code,
    IReadOnlyList<ResearchEventCluster> Clusters);

public static class ResearchEventClusterer
{
    private const int MaxEvidenceItems = 256;
    private static readonly TimeSpan MaxAllowedWindow = TimeSpan.FromHours(24);

    public static ResearchEventClusteringResult Cluster(
        IReadOnlyList<ResearchEvidenceEnvelope>? evidence,
        TimeSpan eventWindow)
    {
        if (evidence is null
            || evidence.Count == 0
            || eventWindow <= TimeSpan.Zero
            || eventWindow > MaxAllowedWindow
            || evidence.Any(static item => item is null)
            || evidence.Any(static item => item.ExecutionAuthority != ResearchExecutionAuthority.None))
        {
            return Rejected(ResearchEventClusteringCode.InvalidInput);
        }

        if (evidence.Count > MaxEvidenceItems)
        {
            return Rejected(ResearchEventClusteringCode.TooManyItems);
        }

        var ordered = evidence
            .OrderBy(ReferenceTime)
            .ThenBy(static item => item.EvidenceId, StringComparer.Ordinal)
            .ToArray();
        var mutableClusters = new List<MutableCluster>();

        foreach (var item in ordered)
        {
            var matchingCluster = mutableClusters.FirstOrDefault(cluster =>
                IsSameEvent(cluster.CanonicalEvidence, item, eventWindow));
            if (matchingCluster is null)
            {
                mutableClusters.Add(new MutableCluster(item));
                continue;
            }

            if (matchingCluster.UniqueEvidence.Any(existing => IsDuplicate(existing, item)))
            {
                matchingCluster.DuplicateEvidence.Add(item);
            }
            else
            {
                matchingCluster.UniqueEvidence.Add(item);
            }
        }

        var clusters = mutableClusters
            .Select(static cluster => new ResearchEventCluster(
                BuildClusterId(cluster.CanonicalEvidence),
                cluster.CanonicalEvidence,
                Array.AsReadOnly(cluster.UniqueEvidence.ToArray()),
                Array.AsReadOnly(cluster.DuplicateEvidence.ToArray())))
            .ToArray();

        return new ResearchEventClusteringResult(
            true,
            ResearchEventClusteringCode.Created,
            Array.AsReadOnly(clusters));
    }

    private static bool IsSameEvent(
        ResearchEvidenceEnvelope canonical,
        ResearchEvidenceEnvelope candidate,
        TimeSpan eventWindow)
    {
        if (canonical.Kind != candidate.Kind)
        {
            return false;
        }

        if (!canonical.AffectedSymbols.Any(candidate.AffectedSymbols.Contains))
        {
            return false;
        }

        var delta = ReferenceTime(candidate) - ReferenceTime(canonical);
        return delta.Duration() <= eventWindow;
    }

    private static bool IsDuplicate(
        ResearchEvidenceEnvelope existing,
        ResearchEvidenceEnvelope candidate)
    {
        if (string.Equals(
            existing.NormalizedSha256,
            candidate.NormalizedSha256,
            StringComparison.OrdinalIgnoreCase))
        {
            return true;
        }

        return string.Equals(existing.Source.SourceId, candidate.Source.SourceId, StringComparison.Ordinal)
            && string.Equals(existing.ProviderItemId, candidate.ProviderItemId, StringComparison.Ordinal);
    }

    private static DateTimeOffset ReferenceTime(ResearchEvidenceEnvelope evidence)
    {
        return evidence.EventAt ?? evidence.PublishedAt ?? evidence.RetrievedAt;
    }

    private static string BuildClusterId(ResearchEvidenceEnvelope canonical)
    {
        return $"research-event:{canonical.Kind}:{canonical.EvidenceId}";
    }

    private static ResearchEventClusteringResult Rejected(ResearchEventClusteringCode code)
    {
        return new ResearchEventClusteringResult(
            false,
            code,
            Array.Empty<ResearchEventCluster>());
    }

    private sealed class MutableCluster
    {
        public MutableCluster(ResearchEvidenceEnvelope canonicalEvidence)
        {
            CanonicalEvidence = canonicalEvidence;
            UniqueEvidence = [canonicalEvidence];
            DuplicateEvidence = [];
        }

        public ResearchEvidenceEnvelope CanonicalEvidence { get; }

        public List<ResearchEvidenceEnvelope> UniqueEvidence { get; }

        public List<ResearchEvidenceEnvelope> DuplicateEvidence { get; }
    }
}
