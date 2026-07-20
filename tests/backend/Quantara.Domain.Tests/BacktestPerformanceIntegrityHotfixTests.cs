using Quantara.Domain.Backtesting;
using Quantara.Domain.Trading;

namespace Quantara.Domain.Tests;

public sealed class BacktestPerformanceIntegrityHotfixTests
{
    private static readonly BacktestExecutionRules DefaultRules = new(
        10_000m,
        1m,
        0.1m,
        0.1m,
        100m,
        10m);

    private static readonly BacktestReportSpecification DefaultSpecification = new(
        "performance-report-v1",
        365d * 24d,
        0d,
        500,
        0.95d,
        2);

    [Fact]
    public void RejectsEquityTimelineShiftedOffCandleCloseCadence()
    {
        var fixture = CreateFixture();
        var original = Run(fixture, new ConstantTargetStrategy(1m));
        var shifted = original.EquityCurve
            .Select(point => point with
            {
                Timestamp = point.Timestamp - TimeSpan.FromMinutes(1)
            })
            .ToArray();
        var tampered = CloneRun(original, equityCurve: shifted);

        var result = Build(fixture, tampered, CreateBenchmark(tampered));

        Assert.False(result.IsCreated);
        Assert.Contains(BacktestReportCode.InvalidEquityCurve, result.RejectionReasons);
    }

    [Fact]
    public void RejectsEquityTimelineWithMissingIntermediateCandleClose()
    {
        var fixture = CreateFixture();
        var original = Run(fixture, new ConstantTargetStrategy(1m));
        Assert.True(original.EquityCurve.Count >= 3);
        var shortened = original.EquityCurve
            .Where((_, index) => index != 1)
            .ToArray();
        var tampered = CloneRun(original, equityCurve: shortened);

        var result = Build(fixture, tampered, CreateBenchmark(tampered));

        Assert.False(result.IsCreated);
        Assert.Contains(BacktestReportCode.InvalidEquityCurve, result.RejectionReasons);
    }

    [Fact]
    public void RejectsVolumeParticipationThatDoesNotImplyRecordedSlippage()
    {
        var fixture = CreateFixture();
        var original = Run(fixture, new ConstantTargetStrategy(1m));
        Assert.NotEmpty(original.Fills);
        var fills = original.Fills.ToArray();
        var first = fills[0];
        var changedParticipation = first.VolumeParticipation / 2m;
        Assert.NotEqual(first.VolumeParticipation, changedParticipation);
        fills[0] = first with
        {
            VolumeParticipation = changedParticipation
        };
        var tampered = CloneRun(original, fills: fills);

        var result = Build(fixture, tampered, CreateBenchmark(tampered));

        Assert.False(result.IsCreated);
        Assert.Contains(BacktestReportCode.InvalidFinalState, result.RejectionReasons);
    }

    [Fact]
    public void RejectsSlippageThatDoesNotMatchRecordedParticipation()
    {
        var fixture = CreateFixture();
        var original = Run(fixture, new ConstantTargetStrategy(1m));
        Assert.NotEmpty(original.Fills);
        var fills = original.Fills.ToArray();
        var first = fills[0];
        var changedSlippage = fixture.CostModel.BaseSlippageBps;
        Assert.NotEqual(first.SlippageBps, changedSlippage);
        var direction = first.Side == OrderSide.Buy ? 1m : -1m;
        var changedExecutionPrice = first.ReferencePrice
            * (1m + (direction
                * (first.SpreadBps + changedSlippage)
                / 10_000m));
        var changedFee = changedExecutionPrice
            * first.Quantity
            * DefaultRules.ContractMultiplier
            * fixture.CostModel.TakerFeeBps
            / 10_000m;
        fills[0] = first with
        {
            SlippageBps = changedSlippage,
            ExecutionPrice = changedExecutionPrice,
            Fee = changedFee
        };
        var tampered = CloneRun(original, fills: fills);

        var result = Build(fixture, tampered, CreateBenchmark(tampered));

        Assert.False(result.IsCreated);
        Assert.Contains(BacktestReportCode.InvalidFinalState, result.RejectionReasons);
    }

    private static ReportFixture CreateFixture()
    {
        var candles = ResearchTestData.CreateCandles();
        var funding = ResearchTestData.CreateFundingPoints();
        var dataset = ResearchTestData.CreateDataset(
            candles,
            funding,
            datasetId: "performance-integrity-hotfix-dataset");
        var split = ResearchTestData.CreateSplit(dataset);
        var manifest = ResearchTestData.CreateExperiment(
            dataset,
            split,
            ExperimentStage.Train,
            experimentId: "performance-integrity-hotfix-experiment");
        var costResult = BacktestCostModelFactory.Create(
            "cost-v1",
            2m,
            3m,
            5m,
            4m,
            0.10m,
            1);
        if (!costResult.IsCreated || costResult.Model is null)
        {
            throw new InvalidOperationException("Performance integrity cost model is invalid.");
        }

        return new ReportFixture(
            manifest,
            costResult.Model,
            candles,
            funding);
    }

    private static BacktestRunResult Run(
        ReportFixture fixture,
        IBacktestStrategy strategy)
    {
        return DeterministicBacktestRunner.Run(
            fixture.Manifest,
            fixture.CostModel,
            DefaultRules,
            fixture.Candles,
            fixture.Funding,
            strategy);
    }

    private static BacktestReportBuildResult Build(
        ReportFixture fixture,
        BacktestRunResult run,
        BenchmarkEquitySeries benchmark)
    {
        return BacktestPerformanceReportBuilder.Build(
            fixture.Manifest,
            fixture.CostModel,
            DefaultRules,
            run,
            benchmark,
            DefaultSpecification);
    }

    private static BenchmarkEquitySeries CreateBenchmark(BacktestRunResult run)
    {
        return new BenchmarkEquitySeries(
            "buy-and-hold-baseline",
            DefaultRules.StartingEquity,
            run.EquityCurve
                .Select((point, index) => new BenchmarkEquityPoint(
                    point.Timestamp,
                    DefaultRules.StartingEquity + (index * 10m)))
                .ToArray());
    }

    private static BacktestRunResult CloneRun(
        BacktestRunResult source,
        IReadOnlyList<BacktestFillRecord>? fills = null,
        IReadOnlyList<BacktestEquityPoint>? equityCurve = null)
    {
        return new BacktestRunResult(
            source.Code,
            source.Message,
            source.RunFingerprintSha256,
            source.Decisions,
            fills ?? source.Fills,
            source.Funding,
            equityCurve ?? source.EquityCurve,
            source.Warnings,
            source.FinalPosition,
            source.FinalEquity,
            source.EffectiveTargetSignedQuantity);
    }

    private sealed record ReportFixture(
        ExperimentManifest Manifest,
        BacktestCostModel CostModel,
        Candle[] Candles,
        FundingRatePoint[] Funding);

    private sealed class ConstantTargetStrategy(decimal target) : IBacktestStrategy
    {
        public string Name => "moving-average-cross";

        public string Version => "1.0.0";

        public BacktestTargetDecision Evaluate(BacktestStrategyContext context)
        {
            ArgumentNullException.ThrowIfNull(context);
            return new BacktestTargetDecision(target, "constant integrity target");
        }
    }
}
