using Quantara.Domain.Backtesting;
using Quantara.Domain.Trading;

namespace Quantara.Domain.Tests;

public sealed class BacktestPerformanceEvidenceValidationTests
{
    private static readonly BacktestExecutionRules Rules = new(
        10_000m,
        1m,
        0.1m,
        0.1m,
        100m,
        10m);

    private static readonly BacktestReportSpecification Specification = new(
        "performance-report-v1",
        365d * 24d,
        0d,
        500,
        0.95d,
        2);

    [Fact]
    public void RejectsTamperedFillFeeEvidence()
    {
        var fixture = CreateFixture();
        var original = Run(fixture);
        var fills = original.Fills.ToArray();
        Assert.NotEmpty(fills);
        fills[0] = fills[0] with { Fee = fills[0].Fee + 0.01m };
        var tampered = CloneRun(original, fills: fills);

        var result = Build(fixture, tampered, Specification);

        Assert.False(result.IsCreated);
        Assert.Contains(BacktestReportCode.InvalidFinalState, result.RejectionReasons);
    }

    [Fact]
    public void RejectsTamperedFundingEvidence()
    {
        var fixture = CreateFixture();
        var original = Run(fixture);
        var funding = original.Funding.ToArray();
        Assert.NotEmpty(funding);
        funding[0] = funding[0] with
        {
            NetAmount = funding[0].NetAmount + 0.01m
        };
        var tampered = CloneRun(original, funding: funding);

        var result = Build(fixture, tampered, Specification);

        Assert.False(result.IsCreated);
        Assert.Contains(BacktestReportCode.InvalidFinalState, result.RejectionReasons);
    }

    [Fact]
    public void RejectsExcessiveBootstrapWorkload()
    {
        var fixture = CreateFixture();
        var run = Run(fixture);
        var excessive = Specification with { BootstrapSamples = 100_001 };

        var result = Build(fixture, run, excessive);

        Assert.False(result.IsCreated);
        Assert.Contains(BacktestReportCode.InvalidSpecification, result.RejectionReasons);
    }

    private static EvidenceFixture CreateFixture()
    {
        var candles = ResearchTestData.CreateCandles();
        var funding = ResearchTestData.CreateFundingPoints();
        var dataset = ResearchTestData.CreateDataset(
            candles,
            funding,
            datasetId: "performance-evidence-dataset");
        var split = ResearchTestData.CreateSplit(dataset);
        var manifest = ResearchTestData.CreateExperiment(
            dataset,
            split,
            ExperimentStage.Train,
            experimentId: "performance-evidence-experiment");
        var cost = BacktestCostModelFactory.Create(
            "cost-v1",
            2m,
            3m,
            5m,
            4m,
            0.10m,
            1);
        if (!cost.IsCreated || cost.Model is null)
        {
            throw new InvalidOperationException("Evidence fixture cost model is invalid.");
        }

        return new EvidenceFixture(manifest, cost.Model, candles, funding);
    }

    private static BacktestRunResult Run(EvidenceFixture fixture)
    {
        return DeterministicBacktestRunner.Run(
            fixture.Manifest,
            fixture.CostModel,
            Rules,
            fixture.Candles,
            fixture.Funding,
            new ConstantTargetStrategy());
    }

    private static BacktestReportBuildResult Build(
        EvidenceFixture fixture,
        BacktestRunResult run,
        BacktestReportSpecification specification)
    {
        var benchmark = new BenchmarkEquitySeries(
            "evidence-baseline",
            Rules.StartingEquity,
            run.EquityCurve
                .Select((point, index) => new BenchmarkEquityPoint(
                    point.Timestamp,
                    Rules.StartingEquity + index))
                .ToArray());
        return BacktestPerformanceReportBuilder.Build(
            fixture.Manifest,
            fixture.CostModel,
            Rules,
            run,
            benchmark,
            specification);
    }

    private static BacktestRunResult CloneRun(
        BacktestRunResult source,
        IReadOnlyList<BacktestFillRecord>? fills = null,
        IReadOnlyList<BacktestFundingRecord>? funding = null)
    {
        return new BacktestRunResult(
            source.Code,
            source.Message,
            source.RunFingerprintSha256,
            source.Decisions,
            fills ?? source.Fills,
            funding ?? source.Funding,
            source.EquityCurve,
            source.Warnings,
            source.FinalPosition,
            source.FinalEquity,
            source.EffectiveTargetSignedQuantity);
    }

    private sealed record EvidenceFixture(
        ExperimentManifest Manifest,
        BacktestCostModel CostModel,
        Candle[] Candles,
        FundingRatePoint[] Funding);

    private sealed class ConstantTargetStrategy : IBacktestStrategy
    {
        public string Name => "moving-average-cross";

        public string Version => "1.0.0";

        public BacktestTargetDecision Evaluate(BacktestStrategyContext context)
        {
            ArgumentNullException.ThrowIfNull(context);
            return new BacktestTargetDecision(1m, "constant evidence target");
        }
    }
}

