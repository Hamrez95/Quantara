using System.Security.Cryptography;
using System.Text;
using Quantara.Domain.Research;
using Quantara.Domain.Trading;

namespace Quantara.Domain.Tests;

public sealed class ResearchSourceRegistryLoaderTests
{
    private const string PublisherProperty =
        "\"publisher\": \"Trade City Pro\",";

    private static readonly Symbol BtcUsdt = new("BTCUSDT");
    private static readonly DateTimeOffset LoadedAt = new(
        2026,
        7,
        20,
        12,
        0,
        0,
        TimeSpan.Zero);

    [Fact]
    public void LoaderIsNotPublicToUntrustedCallers()
    {
        Assert.False(typeof(ResearchSourceRegistryLoader).IsPublic);
    }

    [Fact]
    public void LoadsPinnedCompleteDocumentAndPreservesCreatorHypothesisRole()
    {
        var document = RegistryDocument(
            "none",
            "2026-08-20",
            "hypothesis_only");

        var result = ResearchSourceRegistryLoader.Load(
            document,
            ComputeSha256(document),
            LoadedAt);

        Assert.True(result.IsCreated);
        var snapshot = Assert.IsType<ResearchSourceRegistrySnapshot>(result.Snapshot);
        Assert.True(snapshot.TryGetSource(
            "tradecitypro-youtube-channel",
            out var source));
        Assert.Equal(ResearchDecisionRole.HypothesisOnly, source.DecisionRole);
        Assert.Equal(ResearchAuthorityTier.CreatorHypothesis, source.AuthorityTier);
        Assert.Equal(ResearchSourceClass.EducationalHypothesis, source.SourceClass);
        Assert.Equal(ResearchIngestionMode.YoutubeApiMetadata, source.IngestionMode);
        Assert.NotEmpty(source.TermsUris);

        var evidence = ResearchEvidenceEnvelopeFactory.Create(
            "creator-evidence-1",
            snapshot,
            "tradecitypro-youtube-channel",
            "video-1",
            LoadedAt,
            LoadedAt - TimeSpan.FromDays(1),
            null,
            new string('a', 64),
            new string('b', 64),
            "candidate-v1",
            ResearchEvidenceKind.OfficialFact,
            [BtcUsdt]);
        Assert.False(evidence.IsCreated);
        Assert.Contains(
            ResearchEvidenceCode.IncompatibleDecisionRole,
            evidence.RejectionReasons);
    }

    [Fact]
    public void RejectsDocumentThatDoesNotMatchTrustedHash()
    {
        var document = RegistryDocument(
            "none",
            "2026-08-20",
            "hypothesis_only");

        var result = ResearchSourceRegistryLoader.Load(
            document,
            new string('f', 64),
            LoadedAt);

        Assert.False(result.IsCreated);
        Assert.Contains(
            ResearchSourceRegistryCode.InvalidRegistryHash,
            result.RejectionReasons);
    }

    [Fact]
    public void RejectsDocumentThatGrantsExecutionAuthority()
    {
        var document = RegistryDocument(
            "model",
            "2026-08-20",
            "hypothesis_only");

        var result = ResearchSourceRegistryLoader.Load(
            document,
            ComputeSha256(document),
            LoadedAt);

        Assert.False(result.IsCreated);
        Assert.Contains(
            ResearchSourceRegistryCode.ExecutionAuthorityViolation,
            result.RejectionReasons);
    }

    [Fact]
    public void RejectsRegistryExpiredWhenLoaded()
    {
        var document = RegistryDocument(
            "none",
            "2026-07-19",
            "hypothesis_only",
            reviewedAt: "2026-07-01");

        var result = ResearchSourceRegistryLoader.Load(
            document,
            ComputeSha256(document),
            LoadedAt);

        Assert.False(result.IsCreated);
        Assert.Contains(
            ResearchSourceRegistryCode.RegistryExpired,
            result.RejectionReasons);
    }

    [Fact]
    public void RejectsUnsupportedRegistrySchema()
    {
        var document = RegistryDocument(
            "none",
            "2026-08-20",
            "hypothesis_only",
            schemaVersion: "source-registry-v2");

        var result = ResearchSourceRegistryLoader.Load(
            document,
            ComputeSha256(document),
            LoadedAt);

        Assert.False(result.IsCreated);
        Assert.Contains(
            ResearchSourceRegistryCode.UnsupportedSchema,
            result.RejectionReasons);
    }

    [Fact]
    public void RejectsSchemaIncompleteSource()
    {
        var document = RegistryDocument(
                "none",
                "2026-08-20",
                "hypothesis_only")
            .Replace(PublisherProperty, string.Empty, StringComparison.Ordinal);

        var result = ResearchSourceRegistryLoader.Load(
            document,
            ComputeSha256(document),
            LoadedAt);

        Assert.False(result.IsCreated);
        Assert.Contains(
            ResearchSourceRegistryCode.InvalidSources,
            result.RejectionReasons);
    }

    [Fact]
    public void RejectsCreatorPromotedToDirectFactInsidePinnedDocument()
    {
        var document = RegistryDocument(
            "none",
            "2026-08-20",
            "direct_fact");

        var result = ResearchSourceRegistryLoader.Load(
            document,
            ComputeSha256(document),
            LoadedAt);

        Assert.False(result.IsCreated);
        Assert.Contains(
            ResearchSourceRegistryCode.InvalidSourcePolicy,
            result.RejectionReasons);
    }

    [Fact]
    public void RejectsUnknownSourceProperty()
    {
        var document = RegistryDocument(
                "none",
                "2026-08-20",
                "hypothesis_only")
            .Replace(
                PublisherProperty,
                PublisherProperty + "\n      \"unreviewed_override\": true,",
                StringComparison.Ordinal);

        var result = ResearchSourceRegistryLoader.Load(
            document,
            ComputeSha256(document),
            LoadedAt);

        Assert.False(result.IsCreated);
        Assert.Contains(
            ResearchSourceRegistryCode.InvalidSources,
            result.RejectionReasons);
    }

    private static string RegistryDocument(
        string executionAuthority,
        string reviewDueAt,
        string decisionRole,
        string reviewedAt = "2026-07-20",
        string schemaVersion = "source-registry-v1")
    {
        return $$"""
        {
          "schema_version": "{{schemaVersion}}",
          "registry_version": "1.0.0",
          "reviewed_at": "{{reviewedAt}}",
          "review_due_at": "{{reviewDueAt}}",
          "execution_authority": "{{executionAuthority}}",
          "sources": [
            {
              "id": "tradecitypro-youtube-channel",
              "title": "Trade City Pro official YouTube channel",
              "publisher": "Trade City Pro",
              "canonical_url": "https://www.youtube.com/c/tradecitypro",
              "terms_urls": [
                "https://developers.google.com/youtube/terms/developer-policies"
              ],
              "source_class": "educational_hypothesis",
              "authority_tier": "creator_hypothesis",
              "access_class": "public_web_reference",
              "ingestion_mode": "youtube_api_metadata",
              "decision_role": "{{decisionRole}}",
              "commercial_use_status": "citation_only",
              "update_cadence": "human-selected videos",
              "domains": ["technical analysis"],
              "permitted_uses": ["store approved metadata"],
              "prohibited_uses": ["store full transcripts"],
              "validation_requirements": ["human approval"],
              "attribution_required": true,
              "automated_scraping_allowed": false,
              "retention_policy": "Metadata and original Quantara notes only.",
              "revision_policy": "Review monthly.",
              "enabled": true,
              "notes": "Hypothesis only."
            }
          ]
        }
        """;
    }

    private static string ComputeSha256(string value)
    {
        return Convert.ToHexString(
                SHA256.HashData(Encoding.UTF8.GetBytes(value)))
            .ToLowerInvariant();
    }
}

