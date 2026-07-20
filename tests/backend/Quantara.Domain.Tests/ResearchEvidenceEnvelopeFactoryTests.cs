using Quantara.Domain.Research;
using Quantara.Domain.Trading;

namespace Quantara.Domain.Tests;

public sealed class ResearchEvidenceEnvelopeFactoryTests
{
    private static readonly Symbol BtcUsdt = new("BTCUSDT");
    private static readonly string RawHash = new('a', 64);
    private static readonly string NormalizedHash = new('b', 64);
    private static readonly DateTimeOffset RetrievedAt = new(
        2026,
        7,
        20,
        12,
        0,
        0,
        TimeSpan.Zero);

    [Fact]
    public void CreatesValidFactEnvelopeAndCopiesSymbols()
    {
        var symbols = new List<Symbol> { BtcUsdt };

        var result = Create(
            OfficialSource(),
            ResearchEvidenceKind.OfficialFact,
            symbols,
            publishedAt: RetrievedAt - TimeSpan.FromMinutes(5),
            expiresAt: RetrievedAt + TimeSpan.FromHours(1));
        symbols.Add(new Symbol("ETHUSDT"));

        Assert.True(result.IsCreated);
        Assert.Empty(result.RejectionReasons);
        var envelope = Assert.IsType<ResearchEvidenceEnvelope>(result.Envelope);
        Assert.Equal(ResearchExecutionAuthority.None, envelope.ExecutionAuthority);
        Assert.Equal(TimeSpan.Zero, envelope.RetrievedAt.Offset);
        Assert.Single(envelope.AffectedSymbols);
        Assert.Equal(BtcUsdt, envelope.AffectedSymbols[0]);
    }

    [Fact]
    public void RejectsPublicationAfterRetrieval()
    {
        var result = Create(
            OfficialSource(),
            ResearchEvidenceKind.OfficialFact,
            [BtcUsdt],
            publishedAt: RetrievedAt + TimeSpan.FromMinutes(1));

        Assert.False(result.IsCreated);
        Assert.Contains(
            ResearchEvidenceCode.InvalidTimestamp,
            result.RejectionReasons);
        Assert.Null(result.Envelope);
    }

    [Fact]
    public void RejectsExpiredEnvelopeAtRetrieval()
    {
        var result = Create(
            OfficialSource(),
            ResearchEvidenceKind.OfficialFact,
            [BtcUsdt],
            expiresAt: RetrievedAt);

        Assert.False(result.IsCreated);
        Assert.Contains(
            ResearchEvidenceCode.InvalidTimestamp,
            result.RejectionReasons);
    }

    [Fact]
    public void RejectsHypothesisSourceUsedAsFact()
    {
        var source = new RegisteredResearchSource(
            "1.0.0",
            "tradecitypro-youtube-channel",
            new Uri("https://www.youtube.com/c/tradecitypro"),
            ResearchDecisionRole.HypothesisOnly);

        var result = Create(
            source,
            ResearchEvidenceKind.OfficialFact,
            [BtcUsdt]);

        Assert.False(result.IsCreated);
        Assert.Contains(
            ResearchEvidenceCode.IncompatibleDecisionRole,
            result.RejectionReasons);
    }

    [Fact]
    public void RejectsDuplicateAffectedSymbols()
    {
        var result = Create(
            OfficialSource(),
            ResearchEvidenceKind.OfficialFact,
            [BtcUsdt, BtcUsdt]);

        Assert.False(result.IsCreated);
        Assert.Contains(
            ResearchEvidenceCode.InvalidSymbols,
            result.RejectionReasons);
    }

    [Fact]
    public void RejectsIncompleteExtractionMetadata()
    {
        var result = ResearchEvidenceEnvelopeFactory.Create(
            "evidence-1",
            OfficialSource(),
            "provider-item-1",
            RetrievedAt,
            RetrievedAt - TimeSpan.FromMinutes(5),
            null,
            RawHash,
            NormalizedHash,
            "official-fact-v1",
            ResearchEvidenceKind.OfficialFact,
            [BtcUsdt],
            extractionModelVersion: "extractor-v1");

        Assert.False(result.IsCreated);
        Assert.Contains(
            ResearchEvidenceCode.InvalidExtractionMetadata,
            result.RejectionReasons);
    }

    [Fact]
    public void RejectsInsecureSourceUri()
    {
        var source = new RegisteredResearchSource(
            "1.0.0",
            "fred-alfred-api",
            new Uri("http://example.com/data"),
            ResearchDecisionRole.DirectFact);

        var result = Create(
            source,
            ResearchEvidenceKind.OfficialFact,
            [BtcUsdt]);

        Assert.False(result.IsCreated);
        Assert.Contains(
            ResearchEvidenceCode.InvalidSourceIdentity,
            result.RejectionReasons);
    }

    [Fact]
    public void RejectsMalformedHashes()
    {
        var result = ResearchEvidenceEnvelopeFactory.Create(
            "evidence-1",
            OfficialSource(),
            "provider-item-1",
            RetrievedAt,
            RetrievedAt - TimeSpan.FromMinutes(5),
            null,
            "ABC",
            NormalizedHash,
            "official-fact-v1",
            ResearchEvidenceKind.OfficialFact,
            [BtcUsdt]);

        Assert.False(result.IsCreated);
        Assert.Contains(
            ResearchEvidenceCode.InvalidHash,
            result.RejectionReasons);
    }

    [Fact]
    public void AllowsComplianceEvidenceWithoutSymbols()
    {
        var source = new RegisteredResearchSource(
            "1.0.0",
            "youtube-api-developer-policy",
            new Uri("https://developers.google.com/youtube/terms/developer-policies"),
            ResearchDecisionRole.ComplianceOnly);

        var result = Create(
            source,
            ResearchEvidenceKind.ComplianceDecision,
            []);

        Assert.True(result.IsCreated);
        var envelope = Assert.IsType<ResearchEvidenceEnvelope>(result.Envelope);
        Assert.Empty(envelope.AffectedSymbols);
        Assert.Equal(ResearchExecutionAuthority.None, envelope.ExecutionAuthority);
    }

    private static RegisteredResearchSource OfficialSource()
    {
        return new RegisteredResearchSource(
            "1.0.0",
            "fred-alfred-api",
            new Uri("https://fred.stlouisfed.org/docs/api/fred/overview.html"),
            ResearchDecisionRole.DirectFact);
    }

    private static ResearchEvidenceBuildResult Create(
        RegisteredResearchSource source,
        ResearchEvidenceKind kind,
        IReadOnlyList<Symbol> symbols,
        DateTimeOffset? publishedAt = null,
        DateTimeOffset? expiresAt = null)
    {
        return ResearchEvidenceEnvelopeFactory.Create(
            "evidence-1",
            source,
            "provider-item-1",
            RetrievedAt,
            publishedAt,
            null,
            RawHash,
            NormalizedHash,
            "official-fact-v1",
            kind,
            symbols,
            expiresAt,
            "extractor-v1",
            "prompt-v1");
    }
}
