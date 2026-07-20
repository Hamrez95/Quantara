using Quantara.Domain.Risk;
using Quantara.Domain.Trading;

namespace Quantara.Domain.Tests;

public sealed class CorrelationRiskTests
{
    [Fact]
    public void ApprovesTradeWhenCorrelatedExposureRemainsWithinLimit()
    {
        var context = new CorrelationRiskContext(
            "large-cap-crypto",
            1_000m,
            30m,
            0.50m);

        var result = DeterministicRiskEngine.Evaluate(
            CreateRequest(),
            CreatePolicy(),
            CreateInstrumentRules(),
            context);

        Assert.True(result.IsApproved);
        Assert.Equal("large-cap-crypto", result.CorrelationGroup);
        Assert.Equal(1_000m, result.CorrelatedExposureBefore);
        Assert.True(result.CorrelatedExposureAfter > result.CorrelatedExposureBefore);
        Assert.True(result.CorrelatedExposureAfter <= 3_000m);
    }

    [Fact]
    public void RejectsTradeWhenCorrelatedExposureExceedsLimit()
    {
        var context = new CorrelationRiskContext(
            "large-cap-crypto",
            2_900m,
            30m,
            1m);

        var result = DeterministicRiskEngine.Evaluate(
            CreateRequest(),
            CreatePolicy(),
            CreateInstrumentRules(),
            context);

        Assert.False(result.IsApproved);
        Assert.Contains(
            RiskDecisionCode.CorrelatedExposureLimitExceeded,
            result.RejectionReasons);
        Assert.True(result.CorrelatedExposureAfter > 3_000m);
    }

    [Fact]
    public void RejectsMalformedCorrelationContextForOpeningTrade()
    {
        var context = new CorrelationRiskContext(
            string.Empty,
            -1m,
            0m,
            1.1m);

        var result = DeterministicRiskEngine.Evaluate(
            CreateRequest(),
            CreatePolicy(),
            CreateInstrumentRules(),
            context);

        Assert.False(result.IsApproved);
        Assert.Contains(
            RiskDecisionCode.InvalidCorrelationContext,
            result.RejectionReasons);
        Assert.Equal(string.Empty, result.CorrelationGroup);
        Assert.Equal(0m, result.CorrelatedExposureBefore);
        Assert.Equal(0m, result.CorrelatedExposureAfter);
    }

    [Fact]
    public void PreservesPreviousBehaviorWhenCorrelationContextIsAbsent()
    {
        var result = DeterministicRiskEngine.Evaluate(
            CreateRequest(),
            CreatePolicy(),
            CreateInstrumentRules());

        Assert.True(result.IsApproved);
        Assert.Equal(string.Empty, result.CorrelationGroup);
        Assert.Equal(0m, result.CorrelatedExposureBefore);
        Assert.Equal(0m, result.CorrelatedExposureAfter);
    }

    [Fact]
    public void AllowsReduceOnlyExitWithMalformedCorrelationContext()
    {
        var request = CreateRequest() with
        {
            IsReduceOnly = true,
            RequestedQuantity = 0.5019m
        };
        var context = new CorrelationRiskContext(
            string.Empty,
            -1m,
            0m,
            2m);

        var result = DeterministicRiskEngine.Evaluate(
            request,
            CreatePolicy() with { KillSwitchEnabled = true },
            CreateInstrumentRules(),
            context);

        Assert.True(result.IsApproved);
        Assert.Equal(RiskDecisionCode.ReduceOnlyApproved, result.DecisionCode);
        Assert.Equal(0.501m, result.NormalizedQuantity);
        Assert.NotEmpty(result.Warnings);
    }

    private static RiskPolicy CreatePolicy()
    {
        return new RiskPolicy(
            "risk-v2",
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
            new DateTimeOffset(2026, 7, 20, 9, 0, 0, TimeSpan.Zero));
    }
}
