using Quantara.Domain.Analysis;
using Quantara.Domain.Trading;

namespace Quantara.Domain.Tests;

public sealed class DeterministicDowStructureAnalyzerTests
{
    private static readonly DeterministicDowStructureAnalyzer Analyzer = new();

    [Fact]
    public void ProducesDeterministicVersionedSnapshots()
    {
        var candles = PriceStructureTestData.CreateWaveCandles(120, cycleDrift: 0.75m);

        var first = Analyzer.Analyze(candles);
        var second = Analyzer.Analyze(candles.ToArray());

        Assert.True(first.IsCreated);
        Assert.True(second.IsCreated);
        Assert.NotNull(first.Snapshot);
        Assert.NotNull(second.Snapshot);
        Assert.Equal("dow-structure-v1", first.Snapshot.ConfigVersion);
        Assert.False(first.Snapshot.EnabledForDecisionAuthority);
        Assert.Equal(first.Snapshot.FingerprintSha256, second.Snapshot.FingerprintSha256);
        Assert.Equal(first.Snapshot.Internal.Swings, second.Snapshot.Internal.Swings);
        Assert.Equal(first.Snapshot.Internal.Events, second.Snapshot.Internal.Events);
    }

    [Fact]
    public void ClassifiesConfirmedHigherHighsAndHigherLows()
    {
        var result = Analyzer.Analyze(
            PriceStructureTestData.CreateWaveCandles(120, cycleDrift: 1m));

        Assert.NotNull(result.Snapshot);
        Assert.Contains(
            result.Snapshot.Internal.Swings,
            swing => swing.Classification == DowSwingClassification.HigherHigh);
        Assert.Contains(
            result.Snapshot.Internal.Swings,
            swing => swing.Classification == DowSwingClassification.HigherLow);
        Assert.All(
            result.Snapshot.Internal.Swings,
            swing => Assert.True(swing.ConfirmedAt >= swing.OccurredAt));
    }

    [Fact]
    public void FutureCandlesCannotRepaintAlreadyConfirmedSwings()
    {
        var candles = PriceStructureTestData.CreateWaveCandles(140, cycleDrift: 0.5m);
        var prefix = candles.Take(100).ToArray();

        var earlier = Analyzer.Analyze(prefix);
        var later = Analyzer.Analyze(candles);

        Assert.NotNull(earlier.Snapshot);
        Assert.NotNull(later.Snapshot);
        var earlierAsOf = earlier.Snapshot.AsOf;
        var laterKnownAtEarlierTime = later.Snapshot.Internal.Swings
            .Where(swing => swing.ConfirmedAt <= earlierAsOf)
            .ToArray();
        Assert.Equal(earlier.Snapshot.Internal.Swings, laterKnownAtEarlierTime);
    }

    [Fact]
    public void WickOnlyExcursionDoesNotCreateBreakEvent()
    {
        var candles = PriceStructureTestData.CreateWaveCandles(120).ToList();
        var last = candles[^1];
        candles[^1] = last with
        {
            High = 160m,
            Close = 100m
        };

        var result = Analyzer.Analyze(candles);

        Assert.NotNull(result.Snapshot);
        Assert.DoesNotContain(
            result.Snapshot.Internal.Events,
            item => item.CandleIndex == candles.Count - 1
                && item.Type is DowStructureEventType.BosUp or DowStructureEventType.ChochUp);
        Assert.DoesNotContain(
            result.Snapshot.External.Events,
            item => item.CandleIndex == candles.Count - 1
                && item.Type is DowStructureEventType.BosUp or DowStructureEventType.ChochUp);
    }

    [Fact]
    public void AcceptedCloseBreakProducesTimestampedEvidenceOnly()
    {
        var specification = DowStructureSpecification.Conservative with
        {
            MinimumDisplacementAtr = 0m,
            BreakAcceptanceAtr = 0m,
            AcceptanceBars = 2
        };
        var result = Analyzer.Analyze(
            PriceStructureTestData.CreateBrokenResistanceCandles(),
            specification);

        Assert.NotNull(result.Snapshot);
        var breakEvent = result.Snapshot.Internal.Events
            .FirstOrDefault(item => item.Type is DowStructureEventType.BosUp or DowStructureEventType.ChochUp);
        Assert.NotNull(breakEvent);
        Assert.True(breakEvent.OccurredAt <= result.Snapshot.AsOf);
        Assert.Contains("CONFIRMED", breakEvent.ReasonCode, StringComparison.Ordinal);
    }

    [Fact]
    public void MissingCandleFailsClosedBeforeStructureCanBeUsed()
    {
        var candles = PriceStructureTestData.CreateWaveCandles(120).ToList();
        candles.RemoveAt(60);

        var result = Analyzer.Analyze(candles);

        Assert.False(result.IsCreated);
        Assert.Equal(PriceStructureBuildCode.MissingCandle, result.Code);
        Assert.Null(result.Snapshot);
    }

    [Fact]
    public void SharedPriceStructureCarriesSameDowEvidence()
    {
        var candles = PriceStructureTestData.CreateWaveCandles(120, cycleDrift: 0.5m);
        var direct = Analyzer.Analyze(candles);
        var shared = new DeterministicPriceStructureAnalyzer().Analyze(candles);

        Assert.NotNull(direct.Snapshot);
        Assert.NotNull(shared.Analysis);
        Assert.Equal(
            direct.Snapshot.FingerprintSha256,
            shared.Analysis.DowStructure.FingerprintSha256);
    }
}
