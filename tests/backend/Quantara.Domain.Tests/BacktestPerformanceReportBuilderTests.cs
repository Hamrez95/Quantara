using Quantara.Domain.Backtesting;
using Quantara.Domain.Trading;

namespace Quantara.Domain.Tests;

public sealed class BacktestPerformanceReportBuilderTests
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
    public void CreatesDeterministicReportWithCanonicalLedgerAndBenchmarkHashes()
    {
        var fixture = CreateFixture();
        var run = Run(fixture, new ConstantTargetStrategy(1m));
        var benchmark = CreateBenchmark(run);

        var first = Build(fixture, run, benchmark);
        var second = Build(fixture, run, benchmark);

        Assert.True(first.IsCreated);
        Assert.NotNull(first.Report);
        Assert.True(second.IsCreated);
        Assert.NotNull(second.Report);
        Assert.Equal(first.Report.LedgerSha256, second.Report.LedgerSha256);
        Assert.Equal(first.Report.BenchmarkSha256, second.Report.BenchmarkSha256);
        Assert.Equal(first.Report.ReportSha256, second.Report.ReportSha256);
        Assert.Equal(
            BacktestLedgerHasher.ComputeSha256(run),
            first.Report.LedgerSha256);
        Assert.Equal(
            BenchmarkEquityHasher.ComputeSha256(benchmark),
            first.Report.BenchmarkSha256);
        Assert.True(first.Report.TotalReturnBootstrap.Lower
            <= first.Report.TotalReturnBootstrap.Median);
        Assert.True(first.Report.TotalReturnBootstrap.Median
            <= first.Report.TotalReturnBootstrap.Upper);
        Assert.Equal(run.FinalEquity, first.Report.FinalEquity);
        Assert.Equal(run.FinalPosition, first.Report.FinalPosition);
    }

    [Fact]
    public void DifferentBenchmarkPathsProduceDifferentBenchmarkAndReportHashes()
    {
        var fixture = CreateFixture();
        var run = Run(fixture, new ConstantTargetStrategy(1m));
        var firstBenchmark = CreateBenchmark(run);
        var changedPoints = firstBenchmark.Points.ToArray();
        changedPoints[1] = changedPoints[1] with
        {
            Value = changedPoints[1].Value + 25m
        };
        var secondBenchmark = new BenchmarkEquitySeries(
            firstBenchmark.Name,
            firstBenchmark.StartingValue,
            changedPoints);

        var first = Build(fixture, run, firstBenchmark);
        var second = Build(fixture, run, secondBenchmark);

        Assert.True(first.IsCreated);
        Assert.True(second.IsCreated);
        Assert.NotNull(first.Report);
        Assert.NotNull(second.Report);
        Assert.NotEqual(first.Report.BenchmarkSha256, second.Report.BenchmarkSha256);
        Assert.NotEqual(first.Report.ReportSha256, second.Report.ReportSha256);
    }

    [Fact]
    public void ReportsZeroVolatilityAndTrackingErrorAsDefinedZero()
    {
        var fixture = CreateFixture();
        var run = Run(fixture, new ConstantTargetStrategy(0m));
        var benchmark = new BenchmarkEquitySeries(
            "flat-cash",
            DefaultRules.StartingEquity,
            run.EquityCurve
                .Select(point => new BenchmarkEquityPoint(
                    point.Timestamp,
                    DefaultRules.StartingEquity))
                .ToArray());

        var result = Build(fixture, run, benchmark);

        Assert.True(result.IsCreated);
        Assert.NotNull(result.Report);
        Assert.True(result.Report.Returns.AnnualizedVolatility.IsDefined);
        Assert.Equal(0d, result.Report.Returns.AnnualizedVolatility.Value);
        Assert.False(result.Report.Returns.SharpeRatio.IsDefined);
        Assert.True(result.Report.Benchmark.TrackingError.IsDefined);
        Assert.Equal(0d, result.Report.Benchmark.TrackingError.Value);
        Assert.False(result.Report.Benchmark.InformationRatio.IsDefined);
    }

    [Fact]
    public void MeasuresOpenDrawdownFromEvaluationWindowStart()
    {
        var fixture = CreateFixture();
        var original = Run(fixture, new ConstantTargetStrategy(0m));
        var equity = original.EquityCurve
            .Select((point, index) => point with
            {
                Equity = 9_000m - index,
                NetRealizedPnl = -1_000m - index,
                UnrealizedPnl = 0m,
                GrossExposure = 0m,
                GrossLeverage = 0m
            })
            .ToArray();
        var run = CloneRun(
            original,
            equityCurve: equity,
            finalEquity: equity[^1].Equity);
        var benchmark = CreateBenchmark(run);

        var result = Build(fixture, run, benchmark);

        Assert.True(result.IsCreated);
        Assert.NotNull(result.Report);
        Assert.Equal(
            equity[^1].Timestamp - fixture.Manifest.EvaluationWindow.StartInclusive,
            result.Report.Returns.MaximumDrawdownDuration);
    }

    [Fact]
    public void RejectsTamperedNonContiguousDecisionSequence()
    {
        var fixture = CreateFixture();
        var original = Run(
            fixture,
            new SequenceTargetStrategy([1m, -1m, 1m, -1m, 0m, 0m]));
        var decisions = original.Decisions.ToArray();
        Assert.True(decisions.Length >= 2);
        decisions[1] = decisions[1] with { Sequence = decisions[0].Sequence };
        var tampered = CloneRun(original, decisions: decisions);

        var result = Build(fixture, tampered, CreateBenchmark(tampered));

        Assert.False(result.IsCreated);
        Assert.Contains(BacktestReportCode.InvalidFinalState, result.RejectionReasons);
        Assert.Null(result.Report);
    }

    [Fact]
    public void RejectsBenchmarkTimestampMismatch()
    {
        var fixture = CreateFixture();
        var run = Run(fixture, new ConstantTargetStrategy(1m));
        var points = CreateBenchmark(run).Points.ToArray();
        points[1] = points[1] with
        {
            Timestamp = points[1].Timestamp + TimeSpan.FromMinutes(1)
        };
        var benchmark = new BenchmarkEquitySeries("misaligned", 10_000m, points);

        var result = Build(fixture, run, benchmark);

        Assert.False(result.IsCreated);
        Assert.Contains(
            BacktestReportCode.BenchmarkTimestampMismatch,
            result.RejectionReasons);
    }

    [Fact]
    public void LedgerHashChangesWhenWarningEvidenceChanges()
    {
        var fixture = CreateFixture();
        var original = Run(fixture, new ConstantTargetStrategy(1m));
        var warnings = original.Warnings
            .Append(new BacktestRunWarning("review", "manual review required"))
            .ToArray();
        var changed = CloneRun(original, warnings: warnings);

        Assert.NotEqual(
            BacktestLedgerHasher.ComputeSha256(original),
            BacktestLedgerHasher.ComputeSha256(changed));
    }

    [Fact]
    public void BenchmarkHashIsStableAcrossEquivalentUtcOffsets()
    {
        var fixture = CreateFixture();
        var run = Run(fixture, new ConstantTargetStrategy(1m));
        var utc = CreateBenchmark(run);
        var offset = new BenchmarkEquitySeries(
            utc.Name,
            utc.StartingValue,
            utc.Points
                .Select(point => point with
                {
                    Timestamp = point.Timestamp.ToOffset(TimeSpan.FromHours(3))
                })
                .ToArray());

        Assert.Equal(
            BenchmarkEquityHasher.ComputeSha256(utc),
            BenchmarkEquityHasher.ComputeSha256(offset));
    }

    private static ReportFixture CreateFixture()
    {
        var candles = ResearchTestData.CreateCandles();
        var funding = ResearchTestData.CreateFundingPoints();
        var dataset = ResearchTestData.CreateDataset(
            candles,
            funding,
            datasetId: "performance-report-dataset");
        var split = ResearchTestData.CreateSplit(dataset);
        var manifest = ResearchTestData.CreateExperiment(
            dataset,
            split,
            ExperimentStage.Train,
            experimentId: "performance-report-experiment");
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
            throw new InvalidOperationException("Performance fixture cost model is invalid.");
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
        IReadOnlyList<BacktestDecisionRecord>? decisions = null,
        IReadOnlyList<BacktestFillRecord>? fills = null,
        IReadOnlyList<BacktestFundingRecord>? funding = null,
        IReadOnlyList<BacktestEquityPoint>? equityCurve = null,
        IReadOnlyList<BacktestRunWarning>? warnings = null,
        decimal? finalEquity = null)
    {
        return new BacktestRunResult(
            source.Code,
            source.Message,
            source.RunFingerprintSha256,
            decisions ?? source.Decisions,
            fills ?? source.Fills,
            funding ?? source.Funding,
            equityCurve ?? source.EquityCurve,
            warnings ?? source.Warnings,
            source.FinalPosition,
            finalEquity ?? source.FinalEquity,
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
            return new BacktestTargetDecision(target, "constant report target");
        }
    }

    private sealed class SequenceTargetStrategy(
        IReadOnlyList<decimal> targets) : IBacktestStrategy
    {
        private int _index;

        public string Name => "moving-average-cross";

        public string Version => "1.0.0";

        public BacktestTargetDecision Evaluate(BacktestStrategyContext context)
        {
            ArgumentNullException.ThrowIfNull(context);
            var target = targets[Math.Min(_index, targets.Count - 1)];
            _index++;
            return new BacktestTargetDecision(target, "sequence report target");
        }
    }
}

