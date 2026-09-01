using Quantara.Domain.Research;
using Quantara.Domain.Trading;

namespace Quantara.Domain.Tests;

public sealed class ResearchFactAssessmentEvaluatorTests
{
    private static readonly DateTimeOffset RetrievedAt =
        new(2026, 8, 20, 12, 0, 0, TimeSpan.Zero);

    [Fact]
    public void SelectsFreshHighestConfidenceAgreementDeterministically()
    {
        var first = Observation("a", "21000000", 0.8d, RetrievedAt + TimeSpan.FromHours(2));
        var second = Observation("b", "21000000", 0.9d, RetrievedAt + TimeSpan.FromHours(2));

        var result = ResearchFactAssessmentEvaluator.Evaluate(
            "btc.max_supply",
            [first, second],
            RetrievedAt + TimeSpan.FromMinutes(5));

        Assert.True(result.IsUsable);
        Assert.Equal(ResearchFactAssessmentCode.Usable, result.Code);
        Assert.Same(second, result.Selected);
        Assert.Equal(ResearchExecutionAuthority.None, result.Selected!.ExecutionAuthority);
    }

    [Fact]
    public void RejectsExpiredFactsInsteadOfServingStaleValue()
    {
        var observation = Observation(
            "expired",
            "21000000",
            0.9d,
            RetrievedAt + TimeSpan.FromMinutes(10));

        var result = ResearchFactAssessmentEvaluator.Evaluate(
            "btc.max_supply",
            [observation],
            RetrievedAt + TimeSpan.FromMinutes(10));

        Assert.False(result.IsUsable);
        Assert.Equal(ResearchFactAssessmentCode.Expired, result.Code);
        Assert.Null(result.Selected);
    }

    [Fact]
    public void RejectsConflictingQualifiedValuesWithoutSilentWinner()
    {
        var first = Observation("a", "21000000", 0.95d, RetrievedAt + TimeSpan.FromHours(1));
        var second = Observation("b", "20999999", 0.99d, RetrievedAt + TimeSpan.FromHours(1));

        var result = ResearchFactAssessmentEvaluator.Evaluate(
            "btc.max_supply",
            [first, second],
            RetrievedAt + TimeSpan.FromMinutes(5));

        Assert.False(result.IsUsable);
        Assert.Equal(ResearchFactAssessmentCode.Contradicted, result.Code);
        Assert.Null(result.Selected);
        Assert.Equal(2, result.Candidates.Count);
    }

    [Fact]
    public void RejectsLowConfidenceFact()
    {
        var result = ResearchFactAssessmentEvaluator.Evaluate(
            "btc.max_supply",
            [Observation("low", "21000000", 0.4d, RetrievedAt + TimeSpan.FromHours(1))],
            RetrievedAt + TimeSpan.FromMinutes(5));

        Assert.False(result.IsUsable);
        Assert.Equal(ResearchFactAssessmentCode.LowConfidence, result.Code);
    }

    [Fact]
    public void RejectsMissingParserVersionFailClosed()
    {
        var observation = Observation(
            "bad-parser",
            "21000000",
            0.9d,
            RetrievedAt + TimeSpan.FromHours(1)) with
        {
            ParserVersion = ""
        };

        var result = ResearchFactAssessmentEvaluator.Evaluate(
            "btc.max_supply",
            [observation],
            RetrievedAt + TimeSpan.FromMinutes(5));

        Assert.False(result.IsUsable);
        Assert.Equal(ResearchFactAssessmentCode.InvalidObservation, result.Code);
    }

    private static ResearchFactObservation Observation(
        string id,
        string value,
        double confidence,
        DateTimeOffset expiresAt)
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
            new string('b', 64),
            "fact-v1",
            ResearchEvidenceKind.OfficialFact,
            [new Symbol("BTCUSDT")],
            expiresAt: expiresAt);
        Assert.True(envelope.IsCreated);

        return new ResearchFactObservation(
            envelope.Envelope!,
            "btc.max_supply",
            value,
            "fixture-parser-v1",
            confidence);
    }
}
