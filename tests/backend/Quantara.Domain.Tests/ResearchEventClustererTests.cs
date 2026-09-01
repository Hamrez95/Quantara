using Quantara.Domain.Research;
using Quantara.Domain.Trading;

namespace Quantara.Domain.Tests;

public sealed class ResearchEventClustererTests
{
    private static readonly DateTimeOffset RetrievedAt =
        new(2026, 8, 20, 12, 0, 0, TimeSpan.Zero);

    [Fact]
    public void ClustersRelatedEvidenceAndSeparatesDuplicateContent()
    {
        var first = Evidence("a", "provider-a", "BTCUSDT", RetrievedAt, 'a');
        var duplicate = Evidence(
            "b",
            "provider-b",
            "BTCUSDT",
            RetrievedAt + TimeSpan.FromMinutes(2),
            'a');
        var corroborating = Evidence(
            "c",
            "provider-c",
            "BTCUSDT",
            RetrievedAt + TimeSpan.FromMinutes(3),
            'c');

        var result = ResearchEventClusterer.Cluster(
            [corroborating, duplicate, first],
            TimeSpan.FromMinutes(10));

        Assert.True(result.IsCreated);
        Assert.Equal(ResearchEventClusteringCode.Created, result.Code);
        var cluster = Assert.Single(result.Clusters);
        Assert.Same(first, cluster.CanonicalEvidence);
        Assert.Equal(2, cluster.UniqueEvidence.Count);
        Assert.Single(cluster.DuplicateEvidence);
        Assert.Same(duplicate, cluster.DuplicateEvidence[0]);
        Assert.Equal(ResearchExecutionAuthority.None, cluster.CanonicalEvidence.ExecutionAuthority);
    }

    [Fact]
    public void SameProviderItemIsDuplicateEvenWhenNormalizedHashChanges()
    {
        var first = Evidence("a", "same-provider-id", "BTCUSDT", RetrievedAt, 'a');
        var replay = Evidence(
            "b",
            "same-provider-id",
            "BTCUSDT",
            RetrievedAt + TimeSpan.FromMinutes(1),
            'b');

        var result = ResearchEventClusterer.Cluster(
            [first, replay],
            TimeSpan.FromMinutes(10));

        var cluster = Assert.Single(result.Clusters);
        Assert.Single(cluster.UniqueEvidence);
        Assert.Single(cluster.DuplicateEvidence);
    }

    [Fact]
    public void DoesNotMergeDifferentSymbolsOrEventsOutsideWindow()
    {
        var btc = Evidence("btc", "btc", "BTCUSDT", RetrievedAt, 'a');
        var eth = Evidence("eth", "eth", "ETHUSDT", RetrievedAt, 'b');
        var laterBtc = Evidence(
            "btc-later",
            "btc-later",
            "BTCUSDT",
            RetrievedAt + TimeSpan.FromHours(2),
            'c');

        var result = ResearchEventClusterer.Cluster(
            [btc, eth, laterBtc],
            TimeSpan.FromMinutes(30));

        Assert.True(result.IsCreated);
        Assert.Equal(3, result.Clusters.Count);
    }

    [Fact]
    public void RejectsUnboundedEvidenceBatch()
    {
        var evidence = Evidence("a", "provider-a", "BTCUSDT", RetrievedAt, 'a');
        var oversized = Enumerable.Repeat(evidence, 257).ToArray();

        var result = ResearchEventClusterer.Cluster(
            oversized,
            TimeSpan.FromMinutes(10));

        Assert.False(result.IsCreated);
        Assert.Equal(ResearchEventClusteringCode.TooManyItems, result.Code);
        Assert.Empty(result.Clusters);
    }

    [Fact]
    public void RejectsInvalidClusteringWindow()
    {
        var evidence = Evidence("a", "provider-a", "BTCUSDT", RetrievedAt, 'a');

        var result = ResearchEventClusterer.Cluster([evidence], TimeSpan.Zero);

        Assert.False(result.IsCreated);
        Assert.Equal(ResearchEventClusteringCode.InvalidInput, result.Code);
    }

    private static ResearchEvidenceEnvelope Evidence(
        string id,
        string providerItemId,
        string symbol,
        DateTimeOffset eventAt,
        char normalizedHashCharacter)
    {
        var registry = ResearchSourceRegistrySnapshotFactory.Create(
            "1.0.0",
            new string('c', 64),
            RetrievedAt - TimeSpan.FromDays(1),
            RetrievedAt + TimeSpan.FromDays(30),
            [new RegisteredResearchSource(
                "official-fixture",
                new Uri("https://example.com/api"),
                [new Uri("https://example.com/terms")],
                ResearchSourceClass.OfficialEventData,
                ResearchAuthorityTier.OfficialPrimary,
                ResearchAccessClass.PublicApiWithTerms,
                ResearchIngestionMode.Api,
                ResearchDecisionRole.DirectFact,
                ResearchCommercialUseStatus.ApprovedSubjectToTerms,
                true,
                false,
                true)]);
        Assert.True(registry.IsCreated);

        var retrievalTime = eventAt - TimeSpan.FromHours(1);
        var envelope = ResearchEvidenceEnvelopeFactory.Create(
            $"evidence-{id}",
            registry.Snapshot,
            "official-fixture",
            providerItemId,
            retrievalTime,
            retrievalTime - TimeSpan.FromMinutes(1),
            eventAt,
            new string('d', 64),
            new string(normalizedHashCharacter, 64),
            "event-v1",
            ResearchEvidenceKind.ScheduledEvent,
            [new Symbol(symbol)],
            expiresAt: eventAt + TimeSpan.FromHours(6));
        Assert.True(envelope.IsCreated);
        return envelope.Envelope!;
    }
}
