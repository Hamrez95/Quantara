using Quantara.Domain.Risk;
using Quantara.Domain.Trading;

namespace Quantara.Domain.Tests;

public sealed class RiskEngineRegressionTests
{
    [Fact]
    public void RejectsEntryEqualToStopWithoutThrowing()
    {
        var request = CreateRequest() with { StopLoss = 100m };

        var result = DeterministicRiskEngine.Evaluate(
            request,
            CreatePolicy(),
            CreateInstrumentRules());

        Assert.False(result.IsApproved);
        Assert.Contains(RiskDecisionCode.InvalidStopLoss, result.RejectionReasons);
        Assert.Equal(0m, result.RawQuantity);
    }

    [Fact]
    public void AllowsReduceOnlyExitWhenOpeningPolicyIsMalformed()
    {
        var request = CreateRequest() with
        {
            IsReduceOnly = true,
            RequestedQuantity = 0.5019m
        };
        var malformedOpeningPolicy = CreatePolicy() with
        {
            MaximumRiskPerTradePercent = 0m,
            KillSwitchEnabled = true
        };

        var result = DeterministicRiskEngine.Evaluate(
            request,
            malformedOpeningPolicy,
            CreateInstrumentRules());

        Assert.True(result.IsApproved);
        Assert.Equal(RiskDecisionCode.ReduceOnlyApproved, result.DecisionCode);
        Assert.Equal(0.501m, result.NormalizedQuantity);
    }

    private static RiskPolicy CreatePolicy()
    {
        return new RiskPolicy(
            "risk-v1",
            1m,
            3m,
            6m,
            10m,
            10m,
            500m,
            200m,
            5,
            2m,
            0.20m,
            0.30m,
            3,
            50m,
            false);
    }

    private static InstrumentRiskRules CreateInstrumentRules()
    {
        return new InstrumentRiskRules(
            0.1m,
            0.001m,
            0.001m,
            100m,
            5m,
            1m,
            1,
            3,
            20m);
    }

    private static RiskEvaluationRequest CreateRequest()
    {
        return new RiskEvaluationRequest(
            new Symbol("BTCUSDT"),
            TradeDirection.Long,
            10_000m,
            5_000m,
            100m,
            95m,
            110m,
            1m,
            2m,
            0m,
            0m,
            0m,
            0,
            0m,
            0m,
            0m,
            0.05m,
            0.10m,
            0.10m,
            true,
            true,
            false,
            false,
            0,
            false,
            null,
            new DateTimeOffset(2026, 7, 20, 8, 0, 0, TimeSpan.Zero));
    }
}
