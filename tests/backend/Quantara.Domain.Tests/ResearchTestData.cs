using Quantara.Domain.Backtesting;
using Quantara.Domain.Trading;

namespace Quantara.Domain.Tests;

internal static class ResearchTestData
{
    public const string CommitSha = "0123456789abcdef0123456789abcdef01234567";

    public static readonly Symbol BtcUsdt = new("BTCUSDT");
    public static readonly TimeSpan Hour = TimeSpan.FromHours(1);
    public static readonly DateTimeOffset Start = new(
        2024,
        1,
        1,
        0,
        0,
        0,
        TimeSpan.Zero);

    public static Candle[] CreateCandles(int count = 16)
    {
        return Enumerable.Range(0, count)
            .Select(index =>
            {
                var open = 100m + index;
                return new Candle(
                    BtcUsdt,
                    Hour,
                    Start + TimeSpan.FromTicks(checked(Hour.Ticks * index)),
                    open,
                    open + 2m,
                    open - 2m,
                    open + 1m,
                    1_000m + index);
            })
            .ToArray();
    }

    public static FundingRatePoint[] CreateFundingPoints()
    {
        return
        [
            new FundingRatePoint(BtcUsdt, Start + TimeSpan.FromHours(4), 0.0001m),
            new FundingRatePoint(BtcUsdt, Start + TimeSpan.FromHours(12), -0.0002m)
        ];
    }

    public static DatasetProvenance CreateProvenance(
        string sourceIdentifier = "fixture://btc-usdt/1h/v1",
        string provider = "fixture-provider",
        string market = "linear-perpetual")
    {
        return new DatasetProvenance(
            provider,
            market,
            sourceIdentifier,
            "ohlcv-funding-v1",
            new DateTimeOffset(2026, 7, 20, 8, 0, 0, TimeSpan.Zero));
    }

    public static HistoricalDatasetManifest CreateDataset(
        IReadOnlyList<Candle>? candles = null,
        IReadOnlyList<FundingRatePoint>? fundingPoints = null,
        DatasetProvenance? provenance = null,
        string datasetId = "btc-usdt-1h-fixture")
    {
        var result = HistoricalDatasetManifestBuilder.Build(
            datasetId,
            provenance ?? CreateProvenance(),
            candles ?? CreateCandles(),
            fundingPoints ?? CreateFundingPoints(),
            new DateTimeOffset(2026, 7, 20, 8, 5, 0, TimeSpan.Zero));
        if (!result.IsCreated || result.Manifest is null)
        {
            throw new InvalidOperationException(
                $"Research fixture dataset was rejected: {string.Join(", ", result.RejectionReasons)}");
        }

        return result.Manifest;
    }

    public static TemporalSplitPlan CreateSplit(
        HistoricalDatasetManifest dataset,
        TimeSpan? minimumEmbargo = null)
    {
        var timeframe = dataset.Timeframe;
        var start = dataset.StartInclusive;
        var result = TemporalSplitPlanner.Create(
            dataset,
            new ResearchWindow(start, start + Multiply(timeframe, 6)),
            new ResearchWindow(
                start + Multiply(timeframe, 7),
                start + Multiply(timeframe, 9)),
            new ResearchWindow(
                start + Multiply(timeframe, 10),
                start + Multiply(timeframe, 12)),
            new ResearchWindow(
                start + Multiply(timeframe, 13),
                dataset.EndExclusive),
            minimumEmbargo ?? timeframe);
        if (!result.IsValid || result.Plan is null)
        {
            throw new InvalidOperationException(
                $"Research fixture split was rejected: {string.Join(", ", result.RejectionReasons)}");
        }

        return result.Plan;
    }

    public static ExperimentManifest CreateExperiment(
        HistoricalDatasetManifest? dataset = null,
        TemporalSplitPlan? splitPlan = null,
        ExperimentStage stage = ExperimentStage.Validation,
        IReadOnlyDictionary<string, string>? parameters = null,
        string experimentId = "experiment-1",
        string researchLineageId = "lineage-1",
        string strategyVersion = "1.0.0",
        DateTimeOffset? createdAt = null)
    {
        var resolvedDataset = dataset ?? CreateDataset();
        var resolvedSplitPlan = splitPlan ?? CreateSplit(resolvedDataset);
        var result = ExperimentManifestFactory.Create(
            experimentId,
            researchLineageId,
            "moving-average-cross",
            strategyVersion,
            CommitSha,
            resolvedDataset,
            resolvedSplitPlan,
            stage,
            42,
            "cost-v1",
            "execution-accounting-v1",
            parameters ?? new Dictionary<string, string>(StringComparer.Ordinal)
            {
                ["fast"] = "20",
                ["slow"] = "50"
            },
            createdAt ?? new DateTimeOffset(2026, 7, 20, 8, 10, 0, TimeSpan.Zero));
        if (!result.IsCreated || result.Manifest is null)
        {
            throw new InvalidOperationException(
                $"Research fixture experiment was rejected: {string.Join(", ", result.RejectionReasons)}");
        }

        return result.Manifest;
    }

    private static TimeSpan Multiply(TimeSpan value, int multiplier)
    {
        return TimeSpan.FromTicks(checked(value.Ticks * multiplier));
    }
}
