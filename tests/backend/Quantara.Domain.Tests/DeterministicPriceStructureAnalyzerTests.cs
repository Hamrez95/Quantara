using Quantara.Domain.Analysis;
using Quantara.Domain.Trading;

namespace Quantara.Domain.Tests;

public sealed class DeterministicPriceStructureAnalyzerTests
{
    private static readonly DeterministicPriceStructureAnalyzer Analyzer = new();

    [Fact]
    public void ProducesIdenticalAnalysisForIdenticalCandles()
    {
        var candles = PriceStructureTestData.CreateWaveCandles();

        var first = Analyzer.Analyze(candles);
        var second = Analyzer.Analyze(candles.ToArray());

        Assert.True(first.IsCreated);
        Assert.True(second.IsCreated);
        Assert.NotNull(first.Analysis);
        Assert.NotNull(second.Analysis);
        Assert.Equal(first.Analysis.FingerprintSha256, second.Analysis.FingerprintSha256);
        Assert.Equal(first.Analysis.Zones, second.Analysis.Zones);
        Assert.NotEmpty(first.Analysis.Zones);
    }

    [Fact]
    public void RejectsMissingIntervalsBeforeAnalysis()
    {
        var candles = PriceStructureTestData.CreateWaveCandles().ToList();
        candles.RemoveAt(40);

        var result = Analyzer.Analyze(candles);

        Assert.False(result.IsCreated);
        Assert.Equal(PriceStructureBuildCode.MissingCandle, result.Code);
        Assert.Null(result.Analysis);
    }

    [Fact]
    public void MoreConfirmedTouchesIncreaseZoneStrengthBeforeSaturation()
    {
        var specification = PriceStructureSpecification.Conservative with
        {
            RecencyHalfLifeBars = 500
        };
        var shorter = Analyzer.Analyze(
            PriceStructureTestData.CreateWaveCandles(24),
            specification);
        var longer = Analyzer.Analyze(
            PriceStructureTestData.CreateWaveCandles(48),
            specification);

        Assert.NotNull(shorter.Analysis);
        Assert.NotNull(longer.Analysis);
        var shortResistance = Strongest(shorter.Analysis, PriceZoneRole.Resistance);
        var longResistance = Strongest(longer.Analysis, PriceZoneRole.Resistance);
        Assert.True(longResistance.TouchCount > shortResistance.TouchCount);
        Assert.True(longResistance.Strength > shortResistance.Strength);
    }

    [Fact]
    public void RecentEquivalentReactionsOutrankOldReactions()
    {
        var specification = PriceStructureSpecification.Conservative with
        {
            RecencyHalfLifeBars = 12
        };
        var oldResult = Analyzer.Analyze(
            PriceStructureTestData.CreateOldReactionCandles(),
            specification);
        var recentResult = Analyzer.Analyze(
            PriceStructureTestData.CreateRecentReactionCandles(),
            specification);

        Assert.NotNull(oldResult.Analysis);
        Assert.NotNull(recentResult.Analysis);
        var oldZone = oldResult.Analysis.Zones
            .OrderBy(zone => Math.Abs(zone.Center - 105.5m))
            .First();
        var recentZone = recentResult.Analysis.Zones
            .OrderBy(zone => Math.Abs(zone.Center - 105.5m))
            .First();
        Assert.True(recentZone.Strength > oldZone.Strength);
    }

    [Fact]
    public void ConfirmedResistanceBreakIsReportedAsFlippedSupport()
    {
        var result = Analyzer.Analyze(
            PriceStructureTestData.CreateBrokenResistanceCandles());

        Assert.NotNull(result.Analysis);
        var flipped = result.Analysis.Zones
            .Where(zone => zone.State == PriceZoneState.Flipped)
            .OrderBy(zone => Math.Abs(zone.Center - 106m))
            .First();
        Assert.Equal(PriceZoneRole.Support, flipped.Role);
        Assert.Contains("role changed", flipped.Explanation, StringComparison.Ordinal);
    }

    [Fact]
    public void UnconfirmedLastCandleCannotCreateAPivotZone()
    {
        var candles = PriceStructureTestData.CreateWaveCandles(120).ToArray();
        var last = candles[^1];
        candles[^1] = last with
        {
            High = 180m,
            Close = 110m
        };

        var result = Analyzer.Analyze(candles);

        Assert.NotNull(result.Analysis);
        Assert.DoesNotContain(
            result.Analysis.Zones,
            zone => zone.Center > 150m);
    }

    [Fact]
    public void TimeOffsetsNormalizeToSameFingerprint()
    {
        var candles = PriceStructureTestData.CreateWaveCandles();
        var offset = TimeSpan.FromHours(4);
        var shifted = candles.Select(candle => candle with
        {
            OpenTime = candle.OpenTime.ToOffset(offset)
        }).ToArray();

        var first = Analyzer.Analyze(candles);
        var second = Analyzer.Analyze(shifted);

        Assert.NotNull(first.Analysis);
        Assert.NotNull(second.Analysis);
        Assert.Equal(first.Analysis.FingerprintSha256, second.Analysis.FingerprintSha256);
    }

    private static PriceStructureZone Strongest(
        TimeframePriceStructureAnalysis analysis,
        PriceZoneRole role)
    {
        return analysis.Zones
            .Where(zone => zone.Role == role)
            .OrderByDescending(zone => zone.Strength)
            .First();
    }
}
