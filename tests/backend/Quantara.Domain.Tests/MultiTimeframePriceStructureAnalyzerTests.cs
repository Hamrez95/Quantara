using Quantara.Domain.Analysis;

namespace Quantara.Domain.Tests;

public sealed class MultiTimeframePriceStructureAnalyzerTests
{
    private static readonly DeterministicPriceStructureAnalyzer TimeframeAnalyzer = new();
    private static readonly MultiTimeframePriceStructureAnalyzer MultiTimeframeAnalyzer = new();

    [Fact]
    public void RanksZonesSharedAcrossTimeframes()
    {
        var analyses = new[]
        {
            Analyze(TimeSpan.FromMinutes(15)),
            Analyze(TimeSpan.FromHours(1)),
            Analyze(TimeSpan.FromHours(4)),
            Analyze(TimeSpan.FromDays(1))
        };

        var result = MultiTimeframeAnalyzer.Analyze(analyses, mergeToleranceBps: 60m);

        Assert.True(result.IsCreated);
        Assert.NotNull(result.Analysis);
        Assert.NotEmpty(result.Analysis.Zones);
        Assert.Equal(4, result.Analysis.Zones[0].TimeframeCount);
        Assert.Equal(4, result.Analysis.Zones[0].Timeframes.Count);
    }

    [Fact]
    public void ProducesStableFingerprintRegardlessOfInputOrder()
    {
        var analyses = new[]
        {
            Analyze(TimeSpan.FromMinutes(15)),
            Analyze(TimeSpan.FromHours(1)),
            Analyze(TimeSpan.FromHours(4))
        };

        var first = MultiTimeframeAnalyzer.Analyze(analyses);
        var second = MultiTimeframeAnalyzer.Analyze(analyses.Reverse().ToArray());

        Assert.NotNull(first.Analysis);
        Assert.NotNull(second.Analysis);
        Assert.Equal(first.Analysis.FingerprintSha256, second.Analysis.FingerprintSha256);
        Assert.Equal(first.Analysis.Zones, second.Analysis.Zones);
    }

    [Fact]
    public void RejectsDuplicateTimeframes()
    {
        var analysis = Analyze(TimeSpan.FromHours(1));

        var result = MultiTimeframeAnalyzer.Analyze([analysis, analysis]);

        Assert.False(result.IsCreated);
        Assert.Equal(MultiTimeframeBuildCode.DuplicateTimeframe, result.Code);
    }

    private static TimeframePriceStructureAnalysis Analyze(TimeSpan timeframe)
    {
        var result = TimeframeAnalyzer.Analyze(
            PriceStructureTestData.CreateWaveCandles(
                count: 120,
                timeframe: timeframe));
        return Assert.IsType<TimeframePriceStructureAnalysis>(result.Analysis);
    }
}
