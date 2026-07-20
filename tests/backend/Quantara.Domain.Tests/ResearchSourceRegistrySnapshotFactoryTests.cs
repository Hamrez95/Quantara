using Quantara.Domain.Research;

namespace Quantara.Domain.Tests;

public sealed class ResearchSourceRegistrySnapshotFactoryTests
{
    private static readonly string RegistryHash = new('d', 64);
    private static readonly DateTimeOffset ReviewedAt = new(
        2026,
        7,
        20,
        0,
        0,
        0,
        TimeSpan.Zero);
    private static readonly DateTimeOffset ReviewDueAt = new(
        2026,
        8,
        20,
        0,
        0,
        0,
        TimeSpan.Zero);

    [Fact]
    public void CreatesImmutableSnapshotAndResolvesRegisteredSource()
    {
        var sources = new List<RegisteredResearchSource>
        {
            OfficialSource()
        };

        var result = Create(sources);
        sources.Add(HypothesisSource());

        Assert.True(result.IsCreated);
        Assert.Empty(result.RejectionReasons);
        var snapshot = Assert.IsType<ResearchSourceRegistrySnapshot>(result.Snapshot);
        Assert.Single(snapshot.Sources);
        Assert.True(snapshot.TryGetSource("fred-alfred-api", out var source));
        Assert.Equal(ResearchDecisionRole.DirectFact, source.DecisionRole);
        Assert.False(snapshot.TryGetSource("tradecitypro-youtube-channel", out _));
        Assert.False(snapshot.IsExpiredAt(ReviewDueAt));
        Assert.True(snapshot.IsExpiredAt(ReviewDueAt.AddDays(1)));
    }

    [Fact]
    public void RejectsDuplicateSourceIdentifiers()
    {
        var result = Create([
            OfficialSource(),
            OfficialSource()
        ]);

        Assert.False(result.IsCreated);
        Assert.Contains(
            ResearchSourceRegistryCode.DuplicateSourceId,
            result.RejectionReasons);
    }

    [Fact]
    public void RejectsEnabledSourceBlockedPendingLicense()
    {
        var result = Create([
            new RegisteredResearchSource(
                "coinmetrics-community-api",
                new Uri("https://docs.coinmetrics.io/api"),
                ResearchDecisionRole.FeatureInput,
                ResearchCommercialUseStatus.BlockedPendingLicense,
                true)
        ]);

        Assert.False(result.IsCreated);
        Assert.Contains(
            ResearchSourceRegistryCode.InvalidSourcePolicy,
            result.RejectionReasons);
    }

    [Fact]
    public void AllowsBlockedSourceOnlyWhenDisabled()
    {
        var result = Create([
            new RegisteredResearchSource(
                "coinmetrics-community-api",
                new Uri("https://docs.coinmetrics.io/api"),
                ResearchDecisionRole.FeatureInput,
                ResearchCommercialUseStatus.BlockedPendingLicense,
                false)
        ]);

        Assert.True(result.IsCreated);
    }

    [Fact]
    public void RejectsInsecureSourceUri()
    {
        var result = Create([
            new RegisteredResearchSource(
                "fred-alfred-api",
                new Uri("http://example.com/data"),
                ResearchDecisionRole.DirectFact,
                ResearchCommercialUseStatus.ApprovedSubjectToTerms,
                true)
        ]);

        Assert.False(result.IsCreated);
        Assert.Contains(
            ResearchSourceRegistryCode.InvalidSources,
            result.RejectionReasons);
    }

    [Fact]
    public void RejectsReviewWindowLongerThanPolicyMaximum()
    {
        var result = ResearchSourceRegistrySnapshotFactory.Create(
            "1.0.0",
            RegistryHash,
            ReviewedAt,
            ReviewedAt.AddDays(181),
            [OfficialSource()]);

        Assert.False(result.IsCreated);
        Assert.Contains(
            ResearchSourceRegistryCode.InvalidReviewWindow,
            result.RejectionReasons);
    }

    [Fact]
    public void RejectsNonCanonicalRegistryIdentityAndHash()
    {
        var result = ResearchSourceRegistrySnapshotFactory.Create(
            "01.0.0",
            new string('A', 64),
            ReviewedAt,
            ReviewDueAt,
            [OfficialSource()]);

        Assert.False(result.IsCreated);
        Assert.Contains(
            ResearchSourceRegistryCode.InvalidRegistryIdentity,
            result.RejectionReasons);
        Assert.Contains(
            ResearchSourceRegistryCode.InvalidRegistryHash,
            result.RejectionReasons);
    }

    private static ResearchSourceRegistryBuildResult Create(
        IReadOnlyList<RegisteredResearchSource> sources)
    {
        return ResearchSourceRegistrySnapshotFactory.Create(
            "1.0.0",
            RegistryHash,
            ReviewedAt,
            ReviewDueAt,
            sources);
    }

    private static RegisteredResearchSource OfficialSource()
    {
        return new RegisteredResearchSource(
            "fred-alfred-api",
            new Uri("https://fred.stlouisfed.org/docs/api/fred/overview.html"),
            ResearchDecisionRole.DirectFact,
            ResearchCommercialUseStatus.ApprovedSubjectToTerms,
            true);
    }

    private static RegisteredResearchSource HypothesisSource()
    {
        return new RegisteredResearchSource(
            "tradecitypro-youtube-channel",
            new Uri("https://www.youtube.com/c/tradecitypro"),
            ResearchDecisionRole.HypothesisOnly,
            ResearchCommercialUseStatus.CitationOnly,
            true);
    }
}
