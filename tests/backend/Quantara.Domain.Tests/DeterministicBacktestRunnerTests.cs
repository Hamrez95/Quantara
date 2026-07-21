using Quantara.Domain.Backtesting;
using Quantara.Domain.Trading;

namespace Quantara.Domain.Tests;

public sealed class DeterministicBacktestRunnerTests
{
    private static readonly int[] ExpectedVisibleCounts = [1, 2, 3, 4, 5, 6];
    private static readonly BacktestExecutionRules DefaultRules = new(
        10_000m,
        1m,
        0.1m,
        0.1m,
        100m,
        10m);

    [Fact]
    public void ExecutesCloseTimeDecisionOnlyOnNextBarOpenWithoutFutureVisibility()
    {
        var fixture = CreateFixture();
        var strategy = new RecordingTargetStrategy(1m);

        var result = Run(fixture, strategy);

        Assert.True(result.IsCompleted);
        Assert.Equal(6, strategy.VisibleCounts.Count);
        Assert.Equal(ExpectedVisibleCounts, strategy.VisibleCounts);
        Assert.All(strategy.ObservedCurrentOpenTimes, observed =>
            Assert.DoesNotContain(
                strategy.VisibleSnapshots[observed],
                candle => candle.OpenTime > observed));
        Assert.NotNull(strategy.RetainedFirstContext);
        Assert.Single(strategy.RetainedFirstContext.VisibleCandles);
        Assert.Equal(
            ResearchTestData.Start,
            strategy.RetainedFirstContext.CurrentCandle.OpenTime);
        var fill = Assert.Single(result.Fills);
        Assert.Equal(ResearchTestData.Start + ResearchTestData.Hour, fill.OccurredAt);
        Assert.Equal(101m, fill.ReferencePrice);
        Assert.Equal(OrderSide.Buy, fill.Side);
        Assert.Equal(
            result.Decisions[0].EarliestExecutionAt,
            fill.OccurredAt);
    }

    [Fact]
    public void AppliesSpreadSlippageImpactFeeAndFundingDeterministically()
    {
        var fixture = CreateFixture(
            halfSpreadBps: 10m,
            baseSlippageBps: 20m,
            impactBps: 0m,
            takerFeeBps: 10m);
        var strategy = new ConstantTargetStrategy(1m);

        var result = Run(fixture, strategy);

        var fill = Assert.Single(result.Fills);
        Assert.Equal(101.303m, fill.ExecutionPrice);
        Assert.Equal(30m, fill.SpreadBps + fill.SlippageBps);
        Assert.Equal(0.101303m, fill.Fee);
        var funding = Assert.Single(result.Funding);
        Assert.Equal(ResearchTestData.Start + TimeSpan.FromHours(4), funding.OccurredAt);
        Assert.Equal(104m, funding.ReferencePrice);
        Assert.Equal(-0.0104m, funding.NetAmount);
        Assert.Equal(
            1m,
            result.FinalPosition?.SignedQuantity);
        Assert.Equal(6, result.EquityCurve.Count);
    }

    [Fact]
    public void PartiallyFillsAcrossBarsAtMaximumVolumeParticipation()
    {
        var candles = ResearchTestData.CreateCandles()
            .Select(candle => candle with { Volume = 2m })
            .ToArray();
        var fixture = CreateFixture(
            candles: candles,
            maximumParticipation: 0.25m,
            impactBps: 8m);
        var strategy = new ConstantTargetStrategy(1.5m);

        var result = Run(fixture, strategy);

        Assert.True(result.IsCompleted);
        Assert.Equal(3, result.Fills.Count);
        Assert.All(result.Fills, fill =>
        {
            Assert.Equal(0.5m, fill.Quantity);
            Assert.Equal(0.25m, fill.VolumeParticipation);
            Assert.Equal(8m + fixture.CostModel.BaseSlippageBps, fill.SlippageBps);
        });
        Assert.Equal(1.5m, result.FinalPosition?.SignedQuantity);
        Assert.Equal(1.5m, result.EffectiveTargetSignedQuantity);
        Assert.DoesNotContain(
            result.Warnings,
            warning => string.Equals(
                warning.Code,
                "pending-target-at-end",
                StringComparison.Ordinal));
    }

    [Fact]
    public void LaterDecisionReplacesUnexecutedPendingTarget()
    {
        var fixture = CreateFixture(latencyBars: 2);
        var strategy = new SequenceTargetStrategy([1m, -1m, -1m, -1m, -1m, -1m]);

        var result = Run(fixture, strategy);

        Assert.True(result.IsCompleted);
        var fill = Assert.Single(result.Fills);
        Assert.Equal(OrderSide.Sell, fill.Side);
        Assert.Equal(ResearchTestData.Start + TimeSpan.FromHours(3), fill.OccurredAt);
        Assert.Contains(
            result.Decisions,
            decision => decision.Code == BacktestDecisionCode.ReplacedPendingTarget);
        Assert.Equal(-1m, result.FinalPosition?.SignedQuantity);
    }

    [Fact]
    public void SameInputsAndSeedProduceIdenticalLedgerAndFingerprint()
    {
        var fixture = CreateFixture();

        var first = Run(fixture, new StableRandomTargetStrategy());
        var second = Run(fixture, new StableRandomTargetStrategy());

        Assert.True(first.IsCompleted);
        Assert.True(second.IsCompleted);
        Assert.Equal(first.RunFingerprintSha256, second.RunFingerprintSha256);
        Assert.Equal(first.Decisions, second.Decisions);
        Assert.Equal(first.Fills, second.Fills);
        Assert.Equal(first.Funding, second.Funding);
        Assert.Equal(first.EquityCurve, second.EquityCurve);
        Assert.Equal(first.FinalPosition, second.FinalPosition);
        Assert.Equal(first.FinalEquity, second.FinalEquity);
    }

    [Fact]
    public void RealisticCostsReduceEquityAndChangeRunFingerprint()
    {
        var noCost = CreateFixture(
            halfSpreadBps: 0m,
            baseSlippageBps: 0m,
            impactBps: 0m,
            takerFeeBps: 0m);
        var highCost = CreateFixture(
            halfSpreadBps: 30m,
            baseSlippageBps: 40m,
            impactBps: 50m,
            takerFeeBps: 25m);

        var noCostResult = Run(noCost, new ConstantTargetStrategy(1m));
        var highCostResult = Run(highCost, new ConstantTargetStrategy(1m));

        Assert.True(noCostResult.IsCompleted);
        Assert.True(highCostResult.IsCompleted);
        Assert.True(highCostResult.FinalEquity < noCostResult.FinalEquity);
        Assert.NotEqual(
            noCostResult.RunFingerprintSha256,
            highCostResult.RunFingerprintSha256);
    }

    [Fact]
    public void RejectsTamperedDatasetBeforeStrategyExecution()
    {
        var fixture = CreateFixture();
        var tampered = fixture.Candles.ToArray();
        tampered[2] = tampered[2] with { Close = tampered[2].Close + 0.25m };
        var strategy = new CountingStrategy();

        var result = DeterministicBacktestRunner.Run(
            fixture.Manifest,
            fixture.CostModel,
            DefaultRules,
            tampered,
            fixture.Funding,
            strategy);

        Assert.Equal(BacktestRunCode.DatasetDoesNotMatchManifest, result.Code);
        Assert.Equal(0, strategy.CallCount);
        Assert.Empty(result.Fills);
        Assert.Null(result.RunFingerprintSha256);
    }

    [Fact]
    public void GenericRunnerRejectsHoldoutAndStrategyIdentityMismatch()
    {
        var holdoutFixture = CreateFixture(stage: ExperimentStage.Holdout);
        var holdout = Run(holdoutFixture, new ConstantTargetStrategy(1m));
        var normalFixture = CreateFixture();
        var wrongIdentity = Run(normalFixture, new WrongIdentityStrategy());

        Assert.Equal(BacktestRunCode.InvalidExperimentStage, holdout.Code);
        Assert.Equal(BacktestRunCode.StrategyIdentityMismatch, wrongIdentity.Code);
        Assert.Empty(holdout.Decisions);
        Assert.Empty(wrongIdentity.Decisions);
    }

    [Fact]
    public void RejectsTargetAndLeverageViolationsWithoutFills()
    {
        var fixture = CreateFixture();
        var targetLimitRules = DefaultRules with
        {
            MaximumAbsoluteTargetQuantity = 0.5m
        };
        var leverageRules = DefaultRules with
        {
            StartingEquity = 100m,
            MaximumGrossLeverage = 1m
        };

        var targetLimit = Run(
            fixture,
            new ConstantTargetStrategy(1m),
            targetLimitRules);
        var leverage = Run(
            fixture,
            new ConstantTargetStrategy(2m),
            leverageRules);

        Assert.True(targetLimit.IsCompleted);
        Assert.True(leverage.IsCompleted);
        Assert.All(targetLimit.Decisions, decision =>
            Assert.Equal(BacktestDecisionCode.RejectedTargetLimit, decision.Code));
        Assert.All(leverage.Decisions, decision =>
            Assert.Equal(BacktestDecisionCode.RejectedLeverage, decision.Code));
        Assert.Empty(targetLimit.Fills);
        Assert.Empty(leverage.Fills);
        Assert.Contains(
            targetLimit.Warnings,
            warning => warning.Code == "no-fills");
    }

    [Fact]
    public void ReportsSubMinimumTargetAsNormalizedCloseForExistingPosition()
    {
        var fixture = CreateFixture();
        var strategy = new SequenceTargetStrategy([1m, 0.05m, 0.05m, 0.05m, 0.05m, 0.05m]);

        var result = Run(fixture, strategy);

        Assert.True(result.IsCompleted);
        Assert.Equal(2, result.Fills.Count);
        Assert.Equal(OrderSide.Buy, result.Fills[0].Side);
        Assert.Equal(OrderSide.Sell, result.Fills[1].Side);
        Assert.Contains(result.Decisions, decision =>
            decision.RequestedTargetSignedQuantity == 0.05m
            && decision.NormalizedTargetSignedQuantity == 0m
            && decision.Code == BacktestDecisionCode.NormalizedToFlat);
        Assert.Equal(0m, result.FinalPosition?.SignedQuantity);
    }

    [Fact]
    public void LeavesLateSignalAsEffectiveTargetAndReportsWarning()
    {
        var fixture = CreateFixture(latencyBars: 2);
        var strategy = new SequenceTargetStrategy([0m, 0m, 0m, 0m, 0m, 1m]);

        var result = Run(fixture, strategy);

        Assert.True(result.IsCompleted);
        Assert.Empty(result.Fills);
        Assert.Equal(1m, result.EffectiveTargetSignedQuantity);
        Assert.Contains(
            result.Warnings,
            warning => warning.Code == "pending-target-at-end");
    }

    private static RunnerFixture CreateFixture(
        IReadOnlyList<Candle>? candles = null,
        ExperimentStage stage = ExperimentStage.Train,
        decimal halfSpreadBps = 2m,
        decimal baseSlippageBps = 3m,
        decimal impactBps = 5m,
        decimal takerFeeBps = 4m,
        decimal maximumParticipation = 0.10m,
        int latencyBars = 1)
    {
        var resolvedCandles = candles?.ToArray() ?? ResearchTestData.CreateCandles();
        var funding = ResearchTestData.CreateFundingPoints();
        var dataset = ResearchTestData.CreateDataset(
            resolvedCandles,
            funding,
            datasetId: "runner-dataset");
        var split = ResearchTestData.CreateSplit(dataset);
        var manifest = ResearchTestData.CreateExperiment(
            dataset,
            split,
            stage,
            experimentId: $"runner-{stage}");
        var costResult = BacktestCostModelFactory.Create(
            "cost-v1",
            halfSpreadBps,
            baseSlippageBps,
            impactBps,
            takerFeeBps,
            maximumParticipation,
            latencyBars);
        if (!costResult.IsCreated || costResult.Model is null)
        {
            throw new InvalidOperationException("Runner fixture cost model is invalid.");
        }

        return new RunnerFixture(
            manifest,
            costResult.Model,
            resolvedCandles,
            funding);
    }

    private static BacktestRunResult Run(
        RunnerFixture fixture,
        IBacktestStrategy strategy,
        BacktestExecutionRules? rules = null)
    {
        return DeterministicBacktestRunner.Run(
            fixture.Manifest,
            fixture.CostModel,
            rules ?? DefaultRules,
            fixture.Candles,
            fixture.Funding,
            strategy);
    }

    private sealed record RunnerFixture(
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
            return new BacktestTargetDecision(target, "constant target");
        }
    }

    private sealed class RecordingTargetStrategy(decimal target) : IBacktestStrategy
    {
        public List<int> VisibleCounts { get; } = [];

        public List<DateTimeOffset> ObservedCurrentOpenTimes { get; } = [];

        public Dictionary<DateTimeOffset, Candle[]> VisibleSnapshots { get; } = [];

        public BacktestStrategyContext? RetainedFirstContext { get; private set; }

        public string Name => "moving-average-cross";

        public string Version => "1.0.0";

        public BacktestTargetDecision Evaluate(BacktestStrategyContext context)
        {
            RetainedFirstContext ??= context;
            VisibleCounts.Add(context.VisibleCandles.Count);
            ObservedCurrentOpenTimes.Add(context.CurrentCandle.OpenTime);
            VisibleSnapshots.Add(
                context.CurrentCandle.OpenTime,
                context.VisibleCandles.ToArray());
            return new BacktestTargetDecision(target, "record visibility");
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
            return new BacktestTargetDecision(target, "scripted target");
        }
    }

    private sealed class StableRandomTargetStrategy : IBacktestStrategy
    {
        public string Name => "moving-average-cross";

        public string Version => "1.0.0";

        public BacktestTargetDecision Evaluate(BacktestStrategyContext context)
        {
            var target = context.Random.NextUnitDecimal() >= 0.5m ? 1m : -1m;
            return new BacktestTargetDecision(target, "stable random target");
        }
    }

    private sealed class CountingStrategy : IBacktestStrategy
    {
        public int CallCount { get; private set; }

        public string Name => "moving-average-cross";

        public string Version => "1.0.0";

        public BacktestTargetDecision Evaluate(BacktestStrategyContext context)
        {
            ArgumentNullException.ThrowIfNull(context);
            CallCount++;
            return new BacktestTargetDecision(0m, "count calls");
        }
    }

    private sealed class WrongIdentityStrategy : IBacktestStrategy
    {
        public string Name => "different-strategy";

        public string Version => "9.9.9";

        public BacktestTargetDecision Evaluate(BacktestStrategyContext context)
        {
            throw new InvalidOperationException(
                "Identity validation must run before strategy evaluation.");
        }
    }
}

