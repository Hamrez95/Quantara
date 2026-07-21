using Quantara.Domain.Backtesting;
using Quantara.Domain.Trading;

namespace Quantara.Domain.Tests;

public sealed class HistoricalDatasetManifestBuilderTests
{
    [Fact]
    public void ProducesStableHashesForSameInstantsAndContent()
    {
        var candles = ResearchTestData.CreateCandles();
        var fundingPoints = ResearchTestData.CreateFundingPoints();
        var first = HistoricalDatasetManifestBuilder.Build(
            "dataset-a",
            ResearchTestData.CreateProvenance(),
            candles,
            fundingPoints,
            new DateTimeOffset(2026, 7, 20, 8, 5, 0, TimeSpan.Zero));
        var offset = TimeSpan.FromHours(3);
        var second = HistoricalDatasetManifestBuilder.Build(
            "dataset-b",
            ResearchTestData.CreateProvenance() with
            {
                RetrievedAt = ResearchTestData.CreateProvenance().RetrievedAt.ToOffset(offset)
            },
            candles.Select(candle => candle with
            {
                OpenTime = candle.OpenTime.ToOffset(offset)
            }).ToArray(),
            fundingPoints.Select(point => point with
            {
                OccurredAt = point.OccurredAt.ToOffset(offset)
            }).ToArray(),
            new DateTimeOffset(2026, 7, 21, 8, 5, 0, TimeSpan.Zero));

        Assert.True(first.IsCreated);
        Assert.True(second.IsCreated);
        Assert.NotNull(first.Manifest);
        Assert.NotNull(second.Manifest);
        Assert.Equal(first.Manifest.ContentSha256, second.Manifest.ContentSha256);
        Assert.Equal(first.Manifest.ManifestSha256, second.Manifest.ManifestSha256);
        Assert.NotEqual(first.Manifest.DatasetId, second.Manifest.DatasetId);
        Assert.NotEqual(first.Manifest.CreatedAt, second.Manifest.CreatedAt);
    }

    [Fact]
    public void SeparatesContentIdentityFromProvenanceIdentity()
    {
        var candles = ResearchTestData.CreateCandles();
        var fundingPoints = ResearchTestData.CreateFundingPoints();
        var first = ResearchTestData.CreateDataset(
            candles,
            fundingPoints,
            ResearchTestData.CreateProvenance("fixture://source-a"),
            "dataset-a");
        var second = ResearchTestData.CreateDataset(
            candles,
            fundingPoints,
            ResearchTestData.CreateProvenance("fixture://source-b"),
            "dataset-b");

        Assert.Equal(first.ContentSha256, second.ContentSha256);
        Assert.NotEqual(first.ManifestSha256, second.ManifestSha256);
    }

    [Fact]
    public void ChangesContentHashWhenOneMarketValueChanges()
    {
        var originalCandles = ResearchTestData.CreateCandles();
        var changedCandles = originalCandles.ToArray();
        changedCandles[7] = changedCandles[7] with
        {
            Close = changedCandles[7].Close + 0.00000001m
        };
        var original = ResearchTestData.CreateDataset(candles: originalCandles);
        var changed = ResearchTestData.CreateDataset(
            candles: changedCandles,
            datasetId: "changed-dataset");

        Assert.NotEqual(original.ContentSha256, changed.ContentSha256);
        Assert.NotEqual(original.ManifestSha256, changed.ManifestSha256);
    }

    [Fact]
    public void RejectsMissingMixedAndInvalidCandlesTogether()
    {
        var candles = ResearchTestData.CreateCandles().ToList();
        candles.RemoveAt(3);
        candles[4] = candles[4] with
        {
            Symbol = new Symbol("ETHUSDT"),
            High = candles[4].Open - 1m
        };

        var result = HistoricalDatasetManifestBuilder.Build(
            "invalid-candles",
            ResearchTestData.CreateProvenance(),
            candles,
            Array.Empty<FundingRatePoint>(),
            DateTimeOffset.UtcNow);

        Assert.False(result.IsCreated);
        Assert.Null(result.Manifest);
        Assert.Contains(DatasetBuildCode.MissingCandle, result.RejectionReasons);
        Assert.Contains(DatasetBuildCode.MixedSymbol, result.RejectionReasons);
        Assert.Contains(DatasetBuildCode.InvalidCandle, result.RejectionReasons);
    }

    [Fact]
    public void RejectsDuplicateAndOutOfCoverageFundingPoints()
    {
        var duplicateTimestamp = ResearchTestData.Start + TimeSpan.FromHours(4);
        FundingRatePoint[] fundingPoints =
        [
            new FundingRatePoint(ResearchTestData.BtcUsdt, duplicateTimestamp, 0.0001m),
            new FundingRatePoint(ResearchTestData.BtcUsdt, duplicateTimestamp, 0.0002m),
            new FundingRatePoint(
                ResearchTestData.BtcUsdt,
                ResearchTestData.Start + TimeSpan.FromHours(16),
                0.0003m)
        ];

        var result = HistoricalDatasetManifestBuilder.Build(
            "invalid-funding",
            ResearchTestData.CreateProvenance(),
            ResearchTestData.CreateCandles(),
            fundingPoints,
            DateTimeOffset.UtcNow);

        Assert.False(result.IsCreated);
        Assert.Contains(DatasetBuildCode.DuplicateFundingPoint, result.RejectionReasons);
        Assert.Contains(DatasetBuildCode.FundingOutsideCoverage, result.RejectionReasons);
    }
}

