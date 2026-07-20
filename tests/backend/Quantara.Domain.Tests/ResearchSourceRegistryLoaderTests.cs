using System.Security.Cryptography;
using System.Text;
using Quantara.Domain.Research;
using Quantara.Domain.Trading;

namespace Quantara.Domain.Tests;

public sealed class ResearchSourceRegistryLoaderTests
{
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
    public void LoadsPinnedDocumentAndPreservesCreatorHypothesisRole()
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
    public void RejectsDocumentThatDoesNotMatchPinnedHash()
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
              "canonical_url": "https://www.youtube.com/c/tradecitypro",
              "decision_role": "{{decisionRole}}",
              "commercial_use_status": "citation_only",
              "enabled": true
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
