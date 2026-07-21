using Quantara.Domain.Backtesting;

namespace Quantara.Domain.Tests;

public sealed class BacktestCostModelFactoryTests
{
    [Fact]
    public void CreatesStableFingerprintForSameCosts()
    {
        var first = CreateModel();
        var second = CreateModel();

        Assert.True(first.IsCreated);
        Assert.True(second.IsCreated);
        Assert.NotNull(first.Model);
        Assert.NotNull(second.Model);
        Assert.Equal(first.Model.FingerprintSha256, second.Model.FingerprintSha256);
        Assert.Equal(64, first.Model.FingerprintSha256.Length);
    }

    [Fact]
    public void FingerprintChangesWhenOneEconomicInputChanges()
    {
        var baseline = CreateModel();
        var changed = BacktestCostModelFactory.Create(
            "cost-v1",
            2m,
            3m,
            5.01m,
            4m,
            0.10m,
            1);

        Assert.NotNull(baseline.Model);
        Assert.NotNull(changed.Model);
        Assert.NotEqual(
            baseline.Model.FingerprintSha256,
            changed.Model.FingerprintSha256);
    }

    [Fact]
    public void RejectsEveryInvalidCostDimensionTogether()
    {
        var result = BacktestCostModelFactory.Create(
            " invalid ",
            -1m,
            -2m,
            -3m,
            -4m,
            0m,
            0);

        Assert.False(result.IsCreated);
        Assert.Null(result.Model);
        Assert.Contains(BacktestCostModelCode.InvalidVersion, result.RejectionReasons);
        Assert.Contains(BacktestCostModelCode.InvalidSpread, result.RejectionReasons);
        Assert.Contains(BacktestCostModelCode.InvalidSlippage, result.RejectionReasons);
        Assert.Contains(BacktestCostModelCode.InvalidImpact, result.RejectionReasons);
        Assert.Contains(BacktestCostModelCode.InvalidFee, result.RejectionReasons);
        Assert.Contains(
            BacktestCostModelCode.InvalidParticipation,
            result.RejectionReasons);
        Assert.Contains(BacktestCostModelCode.InvalidLatency, result.RejectionReasons);
    }

    internal static BacktestCostModelResult CreateModel(
        decimal halfSpreadBps = 2m,
        decimal baseSlippageBps = 3m,
        decimal impactBps = 5m,
        decimal takerFeeBps = 4m,
        decimal maximumParticipation = 0.10m,
        int latencyBars = 1)
    {
        return BacktestCostModelFactory.Create(
            "cost-v1",
            halfSpreadBps,
            baseSlippageBps,
            impactBps,
            takerFeeBps,
            maximumParticipation,
            latencyBars);
    }
}
