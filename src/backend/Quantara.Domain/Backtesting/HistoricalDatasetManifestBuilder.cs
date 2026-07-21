using System.Text;
using Quantara.Domain.Trading;

namespace Quantara.Domain.Backtesting;

public static class HistoricalDatasetManifestBuilder
{
    public static DatasetBuildResult Build(
        string datasetId,
        DatasetProvenance provenance,
        IReadOnlyList<Candle> candles,
        IReadOnlyList<FundingRatePoint> fundingPoints,
        DateTimeOffset createdAt)
    {
        ArgumentNullException.ThrowIfNull(provenance);
        ArgumentNullException.ThrowIfNull(candles);
        ArgumentNullException.ThrowIfNull(fundingPoints);

        var rejections = new HashSet<DatasetBuildCode>();
        ValidateDatasetId(datasetId, rejections);
        ValidateProvenance(provenance, rejections);

        if (candles.Count == 0)
        {
            rejections.Add(DatasetBuildCode.EmptyCandles);
            return Rejected(rejections);
        }

        var normalizedCandles = candles
            .Select(Normalize)
            .ToArray();
        var normalizedFundingPoints = fundingPoints
            .Select(Normalize)
            .ToArray();
        var expectedSymbol = normalizedCandles[0].Symbol;
        var expectedTimeframe = normalizedCandles[0].Timeframe;

        ValidateCandles(
            normalizedCandles,
            expectedSymbol,
            expectedTimeframe,
            rejections);

        var startInclusive = normalizedCandles[0].OpenTime;
        var endExclusive = normalizedCandles[^1].OpenTime + expectedTimeframe;
        ValidateFundingPoints(
            normalizedFundingPoints,
            expectedSymbol,
            startInclusive,
            endExclusive,
            rejections);

        if (rejections.Count > 0)
        {
            return Rejected(rejections);
        }

        var contentSha256 = ComputeContentSha256(
            expectedSymbol,
            expectedTimeframe,
            normalizedCandles,
            normalizedFundingPoints);
        var normalizedProvenance = provenance with
        {
            RetrievedAt = provenance.RetrievedAt.ToUniversalTime()
        };
        var manifestSha256 = ComputeManifestSha256(
            expectedSymbol,
            expectedTimeframe,
            startInclusive,
            endExclusive,
            normalizedCandles.Length,
            normalizedFundingPoints.Length,
            contentSha256,
            normalizedProvenance);

        return new DatasetBuildResult(
            true,
            Array.Empty<DatasetBuildCode>(),
            new HistoricalDatasetManifest(
                datasetId,
                expectedSymbol,
                expectedTimeframe,
                startInclusive,
                endExclusive,
                normalizedCandles.Length,
                normalizedFundingPoints.Length,
                contentSha256,
                manifestSha256,
                normalizedProvenance,
                createdAt.ToUniversalTime()));
    }

    private static DatasetBuildResult Rejected(HashSet<DatasetBuildCode> rejections)
    {
        return new DatasetBuildResult(
            false,
            rejections.Order().ToArray(),
            null);
    }

    private static void ValidateDatasetId(
        string datasetId,
        HashSet<DatasetBuildCode> rejections)
    {
        if (string.IsNullOrWhiteSpace(datasetId) || datasetId.Length > 128)
        {
            rejections.Add(DatasetBuildCode.InvalidDatasetIdentifier);
        }
    }

    private static void ValidateProvenance(
        DatasetProvenance provenance,
        HashSet<DatasetBuildCode> rejections)
    {
        if (!IsValidText(provenance.Provider, 128)
            || !IsValidText(provenance.Market, 128)
            || !IsValidText(provenance.SourceIdentifier, 512)
            || !IsValidText(provenance.SchemaVersion, 128))
        {
            rejections.Add(DatasetBuildCode.InvalidProvenance);
        }
    }

    private static void ValidateCandles(
        IReadOnlyList<Candle> candles,
        Symbol expectedSymbol,
        TimeSpan expectedTimeframe,
        HashSet<DatasetBuildCode> rejections)
    {
        for (var index = 0; index < candles.Count; index++)
        {
            var candle = candles[index];
            if (!IsValidCandle(candle))
            {
                rejections.Add(DatasetBuildCode.InvalidCandle);
            }

            if (!SymbolsMatch(candle.Symbol, expectedSymbol))
            {
                rejections.Add(DatasetBuildCode.MixedSymbol);
            }

            if (candle.Timeframe != expectedTimeframe)
            {
                rejections.Add(DatasetBuildCode.MixedTimeframe);
            }

            if (index == 0)
            {
                continue;
            }

            var previous = candles[index - 1];
            if (candle.OpenTime == previous.OpenTime)
            {
                rejections.Add(DatasetBuildCode.DuplicateCandle);
                continue;
            }

            if (candle.OpenTime < previous.OpenTime)
            {
                rejections.Add(DatasetBuildCode.UnorderedCandle);
                continue;
            }

            if (expectedTimeframe > TimeSpan.Zero
                && candle.OpenTime != previous.OpenTime + expectedTimeframe)
            {
                rejections.Add(DatasetBuildCode.MissingCandle);
            }
        }
    }

    private static void ValidateFundingPoints(
        IReadOnlyList<FundingRatePoint> fundingPoints,
        Symbol expectedSymbol,
        DateTimeOffset startInclusive,
        DateTimeOffset endExclusive,
        HashSet<DatasetBuildCode> rejections)
    {
        for (var index = 0; index < fundingPoints.Count; index++)
        {
            var fundingPoint = fundingPoints[index];
            if (string.IsNullOrWhiteSpace(fundingPoint.Symbol.Value))
            {
                rejections.Add(DatasetBuildCode.InvalidFundingPoint);
            }

            if (!SymbolsMatch(fundingPoint.Symbol, expectedSymbol))
            {
                rejections.Add(DatasetBuildCode.MixedFundingSymbol);
            }

            if (fundingPoint.OccurredAt < startInclusive
                || fundingPoint.OccurredAt >= endExclusive)
            {
                rejections.Add(DatasetBuildCode.FundingOutsideCoverage);
            }

            if (index == 0)
            {
                continue;
            }

            var previous = fundingPoints[index - 1];
            if (fundingPoint.OccurredAt == previous.OccurredAt)
            {
                rejections.Add(DatasetBuildCode.DuplicateFundingPoint);
            }
            else if (fundingPoint.OccurredAt < previous.OccurredAt)
            {
                rejections.Add(DatasetBuildCode.UnorderedFundingPoint);
            }
        }
    }

    private static bool IsValidCandle(Candle candle)
    {
        return !string.IsNullOrWhiteSpace(candle.Symbol.Value)
            && candle.Timeframe > TimeSpan.Zero
            && candle.IsValid
            && candle.High >= Math.Max(candle.Open, candle.Close)
            && candle.Low <= Math.Min(candle.Open, candle.Close);
    }

    private static bool IsValidText(string value, int maximumLength)
    {
        return !string.IsNullOrWhiteSpace(value) && value.Length <= maximumLength;
    }

    private static bool SymbolsMatch(Symbol left, Symbol right)
    {
        return string.Equals(left.Value, right.Value, StringComparison.Ordinal);
    }

    private static Candle Normalize(Candle candle)
    {
        return candle with { OpenTime = candle.OpenTime.ToUniversalTime() };
    }

    private static FundingRatePoint Normalize(FundingRatePoint fundingPoint)
    {
        return fundingPoint with
        {
            OccurredAt = fundingPoint.OccurredAt.ToUniversalTime()
        };
    }

    private static string ComputeContentSha256(
        Symbol symbol,
        TimeSpan timeframe,
        IReadOnlyList<Candle> candles,
        IReadOnlyList<FundingRatePoint> fundingPoints)
    {
        return CanonicalResearchHash.Compute(builder =>
        {
            CanonicalResearchHash.Append(builder, "quantara-market-content-v1");
            CanonicalResearchHash.Append(builder, symbol.Value);
            CanonicalResearchHash.Append(builder, timeframe);
            CanonicalResearchHash.Append(builder, candles.Count);
            foreach (var candle in candles)
            {
                AppendCandle(builder, candle);
            }

            CanonicalResearchHash.Append(builder, fundingPoints.Count);
            foreach (var fundingPoint in fundingPoints)
            {
                AppendFundingPoint(builder, fundingPoint);
            }
        });
    }

    private static string ComputeManifestSha256(
        Symbol symbol,
        TimeSpan timeframe,
        DateTimeOffset startInclusive,
        DateTimeOffset endExclusive,
        int candleCount,
        int fundingPointCount,
        string contentSha256,
        DatasetProvenance provenance)
    {
        return CanonicalResearchHash.Compute(builder =>
        {
            CanonicalResearchHash.Append(builder, "quantara-dataset-manifest-v1");
            CanonicalResearchHash.Append(builder, symbol.Value);
            CanonicalResearchHash.Append(builder, timeframe);
            CanonicalResearchHash.Append(builder, startInclusive);
            CanonicalResearchHash.Append(builder, endExclusive);
            CanonicalResearchHash.Append(builder, candleCount);
            CanonicalResearchHash.Append(builder, fundingPointCount);
            CanonicalResearchHash.Append(builder, contentSha256);
            CanonicalResearchHash.Append(builder, provenance.Provider);
            CanonicalResearchHash.Append(builder, provenance.Market);
            CanonicalResearchHash.Append(builder, provenance.SourceIdentifier);
            CanonicalResearchHash.Append(builder, provenance.SchemaVersion);
            CanonicalResearchHash.Append(builder, provenance.RetrievedAt);
        });
    }

    private static void AppendCandle(StringBuilder builder, Candle candle)
    {
        CanonicalResearchHash.Append(builder, candle.OpenTime);
        CanonicalResearchHash.Append(builder, candle.Open);
        CanonicalResearchHash.Append(builder, candle.High);
        CanonicalResearchHash.Append(builder, candle.Low);
        CanonicalResearchHash.Append(builder, candle.Close);
        CanonicalResearchHash.Append(builder, candle.Volume);
    }

    private static void AppendFundingPoint(
        StringBuilder builder,
        FundingRatePoint fundingPoint)
    {
        CanonicalResearchHash.Append(builder, fundingPoint.OccurredAt);
        CanonicalResearchHash.Append(builder, fundingPoint.Rate);
    }
}

