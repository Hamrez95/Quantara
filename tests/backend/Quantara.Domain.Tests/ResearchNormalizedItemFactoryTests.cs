using Quantara.Domain.Research;
using Quantara.Domain.Trading;

namespace Quantara.Domain.Tests;

public sealed class ResearchNormalizedItemFactoryTests
{
    private static readonly DateTimeOffset RetrievedAt =
        new(2026, 9, 1, 10, 0, 0, TimeSpan.Zero);

    [Fact]
    public void CreatesProvenanceBoundItemWithConservativeConfidence()
    {
        var evidence = Evidence("a");
        var facts = new[]
        {
            Fact(evidence, "btc.max_supply", "21000000", 0.92d),
            Fact(evidence, "btc.status", "active", 0.74d)
        };

        var result = ResearchNormalizedItemFactory.Create(
            evidence,
            ResearchSeverity.Medium,
            ResearchHorizon.LongTerm,
            facts);

        Assert.True(result.IsCreated);
        Assert.Equal(ResearchNormalizedItemCode.Created, result.Code);
        var item = Assert.IsType<ResearchNormalizedItem>(result.Item);
        Assert.Same(evidence, item.Evidence);
        Assert.Equal(ResearchSeverity.Medium, item.Severity);
        Assert.Equal(ResearchHorizon.LongTerm, item.Horizon);
        Assert.Equal(0.74d, item.Confidence);
        Assert.Equal(evidence.Source.CanonicalUri, item.SourceUrl);
        Assert.Equal(evidence.RetrievedAt, item.RetrievedAt);
        Assert.Equal(evidence.PublishedAt, item.PublishedAt);
        Assert.Equal(evidence.NormalizedSha256, item.ContentSha256);
        Assert.Equal(evidence.ExpiresAt, item.ExpiresAt);
        Assert.Equal(ResearchExecutionAuthority.None, item.ExecutionAuthority);
        Assert.Equal(2, item.ExtractedFacts.Count);
    }

    [Fact]
    public void RejectsFactFromDifferentEvidence()
    {
        var evidence = Evidence("a");
        var other = Evidence("b");

        var result = ResearchNormalizedItemFactory.Create(
            evidence,
            ResearchSeverity.High,
            ResearchHorizon.ShortTerm,
            [Fact(other, "btc.status", "active", 0.8d)]);

        Assert.False(result.IsCreated);
        Assert.Equal(ResearchNormalizedItemCode.MismatchedEvidence, result.Code);
        Assert.Null(result.Item);
    }

    [Fact]
    public void RejectsDuplicateFactKeysInsteadOfInflatingSupport()
    {
        var evidence = Evidence("a");

        var result = ResearchNormalizedItemFactory.Create(
            evidence,
            ResearchSeverity.Low,
            ResearchHorizon.Intraday,
            [
                Fact(evidence, "btc.status", "active", 0.8d),
                Fact(evidence, "btc.status", "active", 0.7d)
            ]);

        Assert.False(result.IsCreated);
        Assert.Equal(ResearchNormalizedItemCode.DuplicateFact, result.Code);
    }

    [Fact]
    public void RejectsInvalidFactConfidence()
    {
        var evidence = Evidence("a");
        var invalid = new ResearchFactObservation(
            evidence,
            "btc.status",
            "active",
            "parser-v1",
            double.NaN);

        var result = ResearchNormalizedItemFactory.Create(
            evidence,
            ResearchSeverity.Low,
            ResearchHorizon.Intraday,
            [invalid]);

        Assert.False(result.IsCreated);
        Assert.Equal(ResearchNormalizedItemCode.InvalidInput, result.Code);
    }

    [Fact]
    public void RejectsUnboundedFactCollection()
    {
        var evidence = Evidence("a");
        var facts = Enumerable.Range(0, 65)
            .Select(index => Fact(
                evidence,
                $"fact.{index}",
                index.ToString(),
                0.8d))
            .ToArray();

        var result = ResearchNormalizedItemFactory.Create(
            evidence,
            ResearchSeverity.Informational,
            ResearchHorizon.Structural,
            facts);

        Assert.False(result.IsCreated);
        Assert.Equal(ResearchNormalizedItemCode.TooManyFacts, result.Code);
    }

    private static ResearchFactObservation Fact(
        ResearchEvidenceEnvelope evidence,
        string factKey,
        string normalizedValue,
        double confidence)
    {
        return new ResearchFactObservation(
            evidence,
            factKey,
            normalizedValue,
            "parser-v1",
            confidence);
    }

    private static ResearchEvidenceEnvelope Evidence(string id)
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

        var envelope = ResearchEvidenceEnvelopeFactory.Create(
            $"evidence-{id}",
            registry.Snapshot,
            "official-fixture",
            $"provider-{id}",
            RetrievedAt,
            RetrievedAt - TimeSpan.FromMinutes(1),
            null,
            new string('a', 64),
            new string(id[0], 64),
            "fact-v1",
            ResearchEvidenceKind.OfficialFact,
            [new Symbol("BTCUSDT")],
            expiresAt: RetrievedAt + TimeSpan.FromHours(6));
        Assert.True(envelope.IsCreated);
        return envelope.Envelope!;
    }
}
