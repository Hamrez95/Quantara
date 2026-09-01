using Quantara.Domain.Research;
using Quantara.Domain.Trading;

namespace Quantara.Domain.Tests;

public sealed class ResearchFundamentalScoreEvaluatorTests
{
    private static readonly DateTimeOffset RetrievedAt =
        new(2026, 8, 20, 12, 0, 0, TimeSpan.Zero);

    [Fact]
    public void ProducesDeterministicTraceableScore()
    {
        var supply = Observation(
            "supply",
            "btc.supply_health",
            "strong",
            0.9d,
            ResearchAuthorityTier.OfficialPrimary);
        var security = Observation(
            "security",
            "btc.security_health",
            "mixed",
            0.8d,
            ResearchAuthorityTier.ProfessionalStandard);
        var supplyAssessment = ResearchFactAssessmentEvaluator.Evaluate(
            supply.FactKey,
            [supply],
            RetrievedAt + TimeSpan.FromMinutes(5));
        var securityAssessment = ResearchFactAssessmentEvaluator.Evaluate(
            security.FactKey,
            [security],
            RetrievedAt + TimeSpan.FromMinutes(5));
        var policy = Policy();

        var result = ResearchFundamentalScoreEvaluator.Evaluate(
            policy,
            [
                new ResearchFundamentalScoreInput(
                    supply.FactKey,
                    1m,
                    supplyAssessment),
                new ResearchFundamentalScoreInput(
                    security.FactKey,
                    -0.5m,
                    securityAssessment)
            ],
            RetrievedAt + TimeSpan.FromMinutes(10));

        Assert.True(result.IsCreated);
        Assert.Equal(ResearchFundamentalScoreCode.Created, result.Code);
        Assert.Equal("fundamental-v1", result.Score!.PolicyVersion);
        Assert.Equal(70m, result.Score.Score);
        Assert.Equal(0.14m, result.Score.Uncertainty);
        Assert.Equal(ResearchExecutionAuthority.None, result.Score.ExecutionAuthority);
        Assert.Equal(
            ["evidence-supply"],
            result.Score.Components[0].EvidenceIds);
        Assert.Equal(
            ["evidence-security"],
            result.Score.Components[1].EvidenceIds);
    }

    [Fact]
    public void RejectsAssessmentThatBecameStaleBeforeScoreGeneration()
    {
        var supply = Observation(
            "supply",
            "btc.supply_health",
            "strong",
            0.9d,
            ResearchAuthorityTier.OfficialPrimary,
            RetrievedAt + TimeSpan.FromHours(1));
        var security = Observation(
            "security",
            "btc.security_health",
            "strong",
            0.9d,
            ResearchAuthorityTier.ProfessionalStandard,
            RetrievedAt + TimeSpan.FromHours(1));
        var asOf = RetrievedAt + TimeSpan.FromMinutes(30);

        var result = ResearchFundamentalScoreEvaluator.Evaluate(
            Policy(),
            [
                new ResearchFundamentalScoreInput(
                    supply.FactKey,
                    1m,
                    ResearchFactAssessmentEvaluator.Evaluate(
                        supply.FactKey,
                        [supply],
                        asOf)),
                new ResearchFundamentalScoreInput(
                    security.FactKey,
                    1m,
                    ResearchFactAssessmentEvaluator.Evaluate(
                        security.FactKey,
                        [security],
                        asOf))
            ],
            RetrievedAt + TimeSpan.FromHours(2));

        Assert.False(result.IsCreated);
        Assert.Equal(ResearchFundamentalScoreCode.UnusableResearch, result.Code);
    }

    [Fact]
    public void RejectsAuthorityTierOutsidePolicy()
    {
        var supply = Observation(
            "supply",
            "btc.supply_health",
            "strong",
            0.9d,
            ResearchAuthorityTier.CreatorHypothesis);
        var security = Observation(
            "security",
            "btc.security_health",
            "strong",
            0.9d,
            ResearchAuthorityTier.ProfessionalStandard);
        var asOf = RetrievedAt + TimeSpan.FromMinutes(5);

        var result = ResearchFundamentalScoreEvaluator.Evaluate(
            Policy(),
            [
                new ResearchFundamentalScoreInput(
                    supply.FactKey,
                    1m,
                    ResearchFactAssessmentEvaluator.Evaluate(
                        supply.FactKey,
                        [supply],
                        asOf)),
                new ResearchFundamentalScoreInput(
                    security.FactKey,
                    1m,
                    ResearchFactAssessmentEvaluator.Evaluate(
                        security.FactKey,
                        [security],
                        asOf))
            ],
            RetrievedAt + TimeSpan.FromMinutes(10));

        Assert.False(result.IsCreated);
        Assert.Equal(ResearchFundamentalScoreCode.UnusableResearch, result.Code);
    }

    [Fact]
    public void RejectsContradictedAssessment()
    {
        var positive = Observation(
            "supply-a",
            "btc.supply_health",
            "strong",
            0.9d,
            ResearchAuthorityTier.OfficialPrimary);
        var negative = Observation(
            "supply-b",
            "btc.supply_health",
            "weak",
            0.9d,
            ResearchAuthorityTier.OfficialPrimary);
        var security = Observation(
            "security",
            "btc.security_health",
            "strong",
            0.9d,
            ResearchAuthorityTier.ProfessionalStandard);
        var asOf = RetrievedAt + TimeSpan.FromMinutes(5);

        var result = ResearchFundamentalScoreEvaluator.Evaluate(
            Policy(),
            [
                new ResearchFundamentalScoreInput(
                    positive.FactKey,
                    1m,
                    ResearchFactAssessmentEvaluator.Evaluate(
                        positive.FactKey,
                        [positive, negative],
                        asOf)),
                new ResearchFundamentalScoreInput(
                    security.FactKey,
                    1m,
                    ResearchFactAssessmentEvaluator.Evaluate(
                        security.FactKey,
                        [security],
                        asOf))
            ],
            RetrievedAt + TimeSpan.FromMinutes(10));

        Assert.False(result.IsCreated);
        Assert.Equal(ResearchFundamentalScoreCode.UnusableResearch, result.Code);
    }

    [Fact]
    public void RejectsPolicyWhoseWeightsDoNotCoverWholeScore()
    {
        var invalidPolicy = Policy() with
        {
            Rules =
            [
                new ResearchFundamentalScoreRule(
                    "supply",
                    "btc.supply_health",
                    0.5m),
                new ResearchFundamentalScoreRule(
                    "security",
                    "btc.security_health",
                    0.4m)
            ]
        };

        var result = ResearchFundamentalScoreEvaluator.Evaluate(
            invalidPolicy,
            [],
            RetrievedAt);

        Assert.False(result.IsCreated);
        Assert.Equal(ResearchFundamentalScoreCode.InvalidPolicy, result.Code);
    }

    private static ResearchFundamentalScorePolicy Policy()
    {
        return new ResearchFundamentalScorePolicy(
            "fundamental-v1",
            0.6d,
            [
                ResearchAuthorityTier.OfficialPrimary,
                ResearchAuthorityTier.ProfessionalStandard
            ],
            [
                new ResearchFundamentalScoreRule(
                    "supply",
                    "btc.supply_health",
                    0.6m),
                new ResearchFundamentalScoreRule(
                    "security",
                    "btc.security_health",
                    0.4m)
            ]);
    }

    private static ResearchFactObservation Observation(
        string id,
        string factKey,
        string value,
        double confidence,
        ResearchAuthorityTier authorityTier,
        DateTimeOffset? expiresAt = null)
    {
        var sourceClass = authorityTier == ResearchAuthorityTier.CreatorHypothesis
            ? ResearchSourceClass.EducationalHypothesis
            : ResearchSourceClass.ResearchEvidence;
        var decisionRole = authorityTier switch
        {
            ResearchAuthorityTier.OfficialPrimary => ResearchDecisionRole.DirectFact,
            ResearchAuthorityTier.CreatorHypothesis => ResearchDecisionRole.HypothesisOnly,
            _ => ResearchDecisionRole.FeatureInput
        };
        var evidenceKind = decisionRole switch
        {
            ResearchDecisionRole.DirectFact => ResearchEvidenceKind.OfficialFact,
            ResearchDecisionRole.HypothesisOnly => ResearchEvidenceKind.CandidateHypothesis,
            _ => ResearchEvidenceKind.FeatureObservation
        };

        var registry = ResearchSourceRegistrySnapshotFactory.Create(
            "1.0.0",
            new string('c', 64),
            RetrievedAt - TimeSpan.FromDays(1),
            RetrievedAt + TimeSpan.FromDays(30),
            [new RegisteredResearchSource(
                $"source-{id}",
                new Uri($"https://example.com/{id}"),
                [new Uri("https://example.com/terms")],
                sourceClass,
                authorityTier,
                ResearchAccessClass.PublicApiWithTerms,
                ResearchIngestionMode.Api,
                decisionRole,
                ResearchCommercialUseStatus.ApprovedSubjectToTerms,
                true,
                false,
                true)]);
        Assert.True(registry.IsCreated);

        var envelope = ResearchEvidenceEnvelopeFactory.Create(
            $"evidence-{id}",
            registry.Snapshot,
            $"source-{id}",
            $"provider-{id}",
            RetrievedAt,
            RetrievedAt - TimeSpan.FromMinutes(1),
            null,
            new string('a', 64),
            new string('b', 64),
            "fact-v1",
            evidenceKind,
            [new Symbol("BTCUSDT")],
            expiresAt: expiresAt ?? RetrievedAt + TimeSpan.FromHours(6));
        Assert.True(envelope.IsCreated);

        return new ResearchFactObservation(
            envelope.Envelope!,
            factKey,
            value,
            "parser-v1",
            confidence);
    }
}
