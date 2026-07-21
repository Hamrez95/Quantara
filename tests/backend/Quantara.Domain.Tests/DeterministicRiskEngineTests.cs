using Quantara.Domain.Risk;
using Quantara.Domain.Trading;

namespace Quantara.Domain.Tests;

public sealed class DeterministicRiskEngineTests
{
    [Fact]
    public void ApprovesValidLongTradeWithinPolicy()
    {
        var result = DeterministicRiskEngine.Evaluate(
            CreateRequest(),
            CreatePolicy(),
            CreateInstrumentRules());

        Assert.True(result.IsApproved);
        Assert.Equal(RiskDecisionCode.Approved, result.DecisionCode);
        Assert.Empty(result.RejectionReasons);
        Assert.Equal(100m, result.RiskAmount);
        Assert.Equal(19.230769230769230769230769231m, result.RawQuantity);
        Assert.Equal(19.230m, result.NormalizedQuantity);
        Assert.True(result.RequiredMargin > 0m);
        Assert.Equal("risk-v1", result.RiskPolicyVersion);
    }

    [Fact]
    public void RejectsInvalidLongStopAndTakeProfitDirections()
    {
        var request = CreateRequest() with
        {
            StopLoss = 105m,
            TakeProfit = 90m
        };

        var result = DeterministicRiskEngine.Evaluate(
            request,
            CreatePolicy(),
            CreateInstrumentRules());

        Assert.False(result.IsApproved);
        Assert.Contains(RiskDecisionCode.InvalidStopDirection, result.RejectionReasons);
        Assert.Contains(RiskDecisionCode.InvalidTakeProfit, result.RejectionReasons);
    }

    [Fact]
    public void ReportsAllIndependentOperationalRejections()
    {
        var request = CreateRequest() with
        {
            MarketDataFresh = false,
            ExchangeConnected = false,
            CircuitBreakerActive = true,
            CooldownActive = true,
            ConsecutiveLosses = 3
        };

        var result = DeterministicRiskEngine.Evaluate(
            request,
            CreatePolicy(killSwitchEnabled: true),
            CreateInstrumentRules());

        Assert.False(result.IsApproved);
        Assert.Contains(RiskDecisionCode.StaleMarketData, result.RejectionReasons);
        Assert.Contains(RiskDecisionCode.ExchangeDisconnected, result.RejectionReasons);
        Assert.Contains(RiskDecisionCode.CircuitBreakerActive, result.RejectionReasons);
        Assert.Contains(RiskDecisionCode.CooldownActive, result.RejectionReasons);
        Assert.Contains(RiskDecisionCode.ConsecutiveLossLimitReached, result.RejectionReasons);
        Assert.Contains(RiskDecisionCode.KillSwitchActive, result.RejectionReasons);
    }

    [Fact]
    public void QuantityNormalizationNeverExceedsApprovedRiskBudget()
    {
        var request = CreateRequest();
        var rules = CreateInstrumentRules();
        var result = DeterministicRiskEngine.Evaluate(request, CreatePolicy(), rules);

        var stopRisk = Math.Abs(request.EntryPrice - request.StopLoss) * rules.ContractSize;
        var feeRisk = request.EntryPrice * rules.ContractSize * request.RoundTripFeePercent / 100m;
        var slippageRisk = request.EntryPrice * rules.ContractSize * request.EstimatedSlippagePercent / 100m;
        var normalizedMonetaryRisk = result.NormalizedQuantity * (stopRisk + feeRisk + slippageRisk);

        Assert.True(result.IsApproved);
        Assert.True(normalizedMonetaryRisk <= result.RiskAmount);
        Assert.True(result.NormalizedQuantity <= result.RawQuantity);
    }

    [Fact]
    public void AllowsReduceOnlyExposureReductionDuringKillSwitch()
    {
        var request = CreateRequest() with
        {
            IsReduceOnly = true,
            RequestedQuantity = 1.2349m,
            MarketDataFresh = false,
            CurrentPortfolioExposure = 5_000m
        };

        var result = DeterministicRiskEngine.Evaluate(
            request,
            CreatePolicy(killSwitchEnabled: true),
            CreateInstrumentRules());

        Assert.True(result.IsApproved);
        Assert.Equal(RiskDecisionCode.ReduceOnlyApproved, result.DecisionCode);
        Assert.Equal(1.234m, result.NormalizedQuantity);
        Assert.Equal(result.PortfolioExposureBefore, result.PortfolioExposureAfter);
        Assert.NotEmpty(result.Warnings);
    }

    [Fact]
    public void RejectsOpeningTradeWhenKillSwitchIsActive()
    {
        var result = DeterministicRiskEngine.Evaluate(
            CreateRequest(),
            CreatePolicy(killSwitchEnabled: true),
            CreateInstrumentRules());

        Assert.False(result.IsApproved);
        Assert.Contains(RiskDecisionCode.KillSwitchActive, result.RejectionReasons);
    }

    [Fact]
    public void RejectsTradeThatCannotMeetMinimumNotional()
    {
        var rules = CreateInstrumentRules() with { MinimumNotional = 10_000m };

        var result = DeterministicRiskEngine.Evaluate(
            CreateRequest(),
            CreatePolicy(),
            rules);

        Assert.False(result.IsApproved);
        Assert.Contains(RiskDecisionCode.MinimumNotionalNotMet, result.RejectionReasons);
    }

    private static RiskPolicy CreatePolicy(bool killSwitchEnabled = false)
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
            killSwitchEnabled);
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

