using Quantara.Domain.Research;
using Quantara.Domain.Trading;

namespace Quantara.Domain.Tests;

public sealed class ResearchEvidenceEnvelopeFactoryTests
{
    private const string OfficialSourceId = "fred-alfred-api";
    private const string HypothesisSourceId = "tradecitypro-youtube-channel";
    private const string ComplianceSourceId = "youtube-api-developer-policy";
    private const string DisabledSourceId = "disabled-market-source";
    private const string BlockedSourceId = "coinmetrics-community-api";

    private static readonly Symbol BtcUsdt = new("BTCUSDT");
    private static readonly string RegistryHash = new('c', 64);
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
            CreateRegistry(),
            OfficialSourceId,
            ResearchEvidenceKind.OfficialFact,
            symbols,
            publishedAt: RetrievedAt - TimeSpan.FromMinutes(5),
            expiresAt: RetrievedAt + TimeSpan.FromHours(1));
        symbols.Add(new Symbol("ETHUSDT"));

        Assert.True(result.IsCreated);
        Assert.Empty(result.RejectionReasons);
        var envelope = Assert.IsType<ResearchEvidenceEnvelope>(result.Envelope);
        Assert.Equal(ResearchExecutionAuthority.None, envelope.ExecutionAuthority);
        Assert.Equal("1.0.0", envelope.RegistryVersion);
        Assert.Equal(RegistryHash, envelope.RegistrySha256);
        Assert.Equal(TimeSpan.Zero, envelope.RetrievedAt.Offset);
        Assert.Single(envelope.AffectedSymbols);
        Assert.Equal(BtcUsdt, envelope.AffectedSymbols[0]);
    }

    [Fact]
    public void RejectsPublicationAfterRetrieval()
    {
        var result = Create(
            CreateRegistry(),
            OfficialSourceId,
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
            CreateRegistry(),
            OfficialSourceId,
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
        var result = Create(
            CreateRegistry(),
            HypothesisSourceId,
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
            CreateRegistry(),
            OfficialSourceId,
            ResearchEvidenceKind.OfficialFact,
            [BtcUsdt, BtcUsdt]);

        Assert.False(result.IsCreated);
        Assert.Contains(
            ResearchEvidenceCode.InvalidSymbols,
            result.RejectionReasons);
    }

    [Fact]
    public void RejectsNullAffectedSymbol()
    {
        var symbols = new List<Symbol> { null! };

        var result = Create(
            CreateRegistry(),
            OfficialSourceId,
            ResearchEvidenceKind.OfficialFact,
            symbols);

        Assert.False(result.IsCreated);
        Assert.Contains(
            ResearchEvidenceCode.InvalidSymbols,
            result.RejectionReasons);
        Assert.Null(result.Envelope);
    }

    [Fact]
    public void RejectsIncompleteExtractionMetadata()
    {
        var result = ResearchEvidenceEnvelopeFactory.Create(
            "evidence-1",
            CreateRegistry(),
            OfficialSourceId,
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
    public void RejectsUnknownSourceId()
    {
        var result = Create(
            CreateRegistry(),
            "unregistered-source",
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
            CreateRegistry(),
            OfficialSourceId,
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
        var result = Create(
            CreateRegistry(),
            ComplianceSourceId,
            ResearchEvidenceKind.ComplianceDecision,
            []);

        Assert.True(result.IsCreated);
        var envelope = Assert.IsType<ResearchEvidenceEnvelope>(result.Envelope);
        Assert.Empty(envelope.AffectedSymbols);
        Assert.Equal(ResearchExecutionAuthority.None, envelope.ExecutionAuthority);
    }

    [Fact]
    public void RejectsRegistryExpiredAtRetrievalDate()
    {
        var result = ResearchEvidenceEnvelopeFactory.Create(
            "evidence-1",
            CreateRegistry(),
            OfficialSourceId,
            "provider-item-1",
            new DateTimeOffset(2026, 8, 21, 0, 0, 0, TimeSpan.Zero),
            null,
            null,
            RawHash,
            NormalizedHash,
            "official-fact-v1",
            ResearchEvidenceKind.OfficialFact,
            [BtcUsdt]);

        Assert.False(result.IsCreated);
        Assert.Contains(
            ResearchEvidenceCode.RegistryExpired,
            result.RejectionReasons);
    }

    [Fact]
    public void RejectsDisabledSource()
    {
        var result = Create(
            CreateRegistry(),
            DisabledSourceId,
            ResearchEvidenceKind.FeatureObservation,
            [BtcUsdt]);

        Assert.False(result.IsCreated);
        Assert.Contains(
            ResearchEvidenceCode.SourceDisabled,
            result.RejectionReasons);
    }

    [Fact]
    public void RejectsSourceBlockedPendingCommercialLicense()
    {
        var result = Create(
            CreateRegistry(),
            BlockedSourceId,
            ResearchEvidenceKind.FeatureObservation,
            [BtcUsdt]);

        Assert.False(result.IsCreated);
        Assert.Contains(
            ResearchEvidenceCode.SourceLicenseBlocked,
            result.RejectionReasons);
        Assert.Contains(
            ResearchEvidenceCode.SourceDisabled,
            result.RejectionReasons);
    }

    private static ResearchSourceRegistrySnapshot CreateRegistry()
    {
        var result = ResearchSourceRegistrySnapshotFactory.Create(
            "1.0.0",
            RegistryHash,
            new DateTimeOffset(2026, 7, 20, 0, 0, 0, TimeSpan.Zero),
            new DateTimeOffset(2026, 8, 20, 0, 0, 0, TimeSpan.Zero),
            [
                OfficialSource(),
                HypothesisSource(),
                ComplianceSource(),
                DisabledSource(),
                BlockedSource()
            ]);
        if (!result.IsCreated || result.Snapshot is null)
        {
            throw new InvalidOperationException(
                $"Research registry fixture was rejected: {string.Join(", ", result.RejectionReasons)}");
        }

        return result.Snapshot;
    }

    private static RegisteredResearchSource OfficialSource()
    {
        return new RegisteredResearchSource(
            OfficialSourceId,
            new Uri("https://fred.stlouisfed.org/docs/api/fred/overview.html"),
            [new Uri("https://fred.stlouisfed.org/docs/api/terms_of_use.html")],
            ResearchSourceClass.OfficialEventData,
            ResearchAuthorityTier.OfficialPrimary,
            ResearchAccessClass.PublicApiWithTerms,
            ResearchIngestionMode.Api,
            ResearchDecisionRole.DirectFact,
            ResearchCommercialUseStatus.ApprovedSubjectToTerms,
            true,
            false,
            true);
    }

    private static RegisteredResearchSource HypothesisSource()
    {
        return new RegisteredResearchSource(
            HypothesisSourceId,
            new Uri("https://www.youtube.com/c/tradecitypro"),
            [new Uri("https://developers.google.com/youtube/terms/developer-policies")],
            ResearchSourceClass.EducationalHypothesis,
            ResearchAuthorityTier.CreatorHypothesis,
            ResearchAccessClass.PublicWebReference,
            ResearchIngestionMode.YoutubeApiMetadata,
            ResearchDecisionRole.HypothesisOnly,
            ResearchCommercialUseStatus.CitationOnly,
            true,
            false,
            true);
    }

    private static RegisteredResearchSource ComplianceSource()
    {
        return new RegisteredResearchSource(
            ComplianceSourceId,
            new Uri("https://developers.google.com/youtube/terms/developer-policies"),
            [new Uri("https://developers.google.com/youtube/terms/api-services-terms-of-service")],
            ResearchSourceClass.CompliancePolicy,
            ResearchAuthorityTier.ComplianceAuthority,
            ResearchAccessClass.PublicWebReference,
            ResearchIngestionMode.NoIngestion,
            ResearchDecisionRole.ComplianceOnly,
            ResearchCommercialUseStatus.NotApplicable,
            true,
            false,
            true);
    }

    private static RegisteredResearchSource DisabledSource()
    {
        return new RegisteredResearchSource(
            DisabledSourceId,
            new Uri("https://example.com/disabled-market-source"),
            [new Uri("https://example.com/terms")],
            ResearchSourceClass.LiveMarketData,
            ResearchAuthorityTier.VendorPrimary,
            ResearchAccessClass.PublicApiWithTerms,
            ResearchIngestionMode.Api,
            ResearchDecisionRole.FeatureInput,
            ResearchCommercialUseStatus.ApprovedSubjectToTerms,
            true,
            false,
            false);
    }

    private static RegisteredResearchSource BlockedSource()
    {
        return new RegisteredResearchSource(
            BlockedSourceId,
            new Uri("https://docs.coinmetrics.io/api"),
            [new Uri("https://coinmetrics.io/terms-of-use/")],
            ResearchSourceClass.LiveMarketData,
            ResearchAuthorityTier.VendorPrimary,
            ResearchAccessClass.CommunityNoncommercial,
            ResearchIngestionMode.Api,
            ResearchDecisionRole.FeatureInput,
            ResearchCommercialUseStatus.BlockedPendingLicense,
            true,
            false,
            false);
    }

    private static ResearchEvidenceBuildResult Create(
        ResearchSourceRegistrySnapshot registry,
        string sourceId,
        ResearchEvidenceKind kind,
        IReadOnlyList<Symbol> symbols,
        DateTimeOffset? publishedAt = null,
        DateTimeOffset? expiresAt = null)
    {
        return ResearchEvidenceEnvelopeFactory.Create(
            "evidence-1",
            registry,
            sourceId,
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
