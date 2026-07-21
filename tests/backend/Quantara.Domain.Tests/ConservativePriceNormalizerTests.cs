using Quantara.Domain.Risk;
using Quantara.Domain.Trading;

namespace Quantara.Domain.Tests;

public sealed class ConservativePriceNormalizerTests
{
    [Fact]
    public void NormalizesLongPricesConservatively()
    {
        var result = ConservativePriceNormalizer.Normalize(
            TradeDirection.Long,
            100.04m,
            95.06m,
            110.09m,
            0.1m,
            1);

        Assert.Equal(100.1m, result.EntryPrice);
        Assert.Equal(95.0m, result.StopLoss);
        Assert.Equal(110.0m, result.TakeProfit);
        Assert.True(result.WasAdjusted);
    }

    [Fact]
    public void NormalizesShortPricesConservatively()
    {
        var result = ConservativePriceNormalizer.Normalize(
            TradeDirection.Short,
            100.06m,
            104.94m,
            90.04m,
            0.1m,
            1);

        Assert.Equal(100.0m, result.EntryPrice);
        Assert.Equal(105.0m, result.StopLoss);
        Assert.Equal(90.1m, result.TakeProfit);
        Assert.True(result.WasAdjusted);
    }

    [Fact]
    public void KeepsAlreadyAlignedPricesUnchanged()
    {
        var result = ConservativePriceNormalizer.Normalize(
            TradeDirection.Long,
            100.1m,
            95.0m,
            110.0m,
            0.1m,
            1);

        Assert.False(result.WasAdjusted);
        Assert.Equal(100.1m, result.EntryPrice);
        Assert.Equal(95.0m, result.StopLoss);
        Assert.Equal(110.0m, result.TakeProfit);
    }

    [Theory]
    [InlineData("0.1", 1, true)]
    [InlineData("0.001", 3, true)]
    [InlineData("0.001", 2, false)]
    [InlineData("10", 0, true)]
    public void ValidatesIncrementPrecisionCompatibility(
        string incrementText,
        int precision,
        bool expected)
    {
        var increment = decimal.Parse(
            incrementText,
            System.Globalization.CultureInfo.InvariantCulture);

        var result = ConservativePriceNormalizer.IsIncrementCompatibleWithPrecision(
            increment,
            precision);

        Assert.Equal(expected, result);
    }

    [Fact]
    public void RiskEngineRejectsIncompatibleTickPrecision()
    {
        var result = DeterministicRiskEngine.Evaluate(
            CreateRequest(),
            CreatePolicy(),
            CreateInstrumentRules() with
            {
                TickSize = 0.001m,
                PricePrecision = 2
            });

        Assert.False(result.IsApproved);
        Assert.Equal(RiskDecisionCode.InstrumentRuleViolation, result.DecisionCode);
    }

    [Fact]
    public void NormalizedLongTradeDoesNotExceedRiskBudget()
    {
        var request = CreateRequest() with
        {
            EntryPrice = 100.04m,
            StopLoss = 95.06m,
            TakeProfit = 110.09m
        };
        var rules = CreateInstrumentRules();

        var result = DeterministicRiskEngine.Evaluate(
            request,
            CreatePolicy(),
            rules);

        var stopRiskPerUnit = Math.Abs(
            result.NormalizedEntryPrice - result.NormalizedStopLoss)
            * rules.ContractSize;
        var feeRiskPerUnit = result.NormalizedEntryPrice
            * rules.ContractSize
            * request.RoundTripFeePercent
            / 100m;
        var slippageRiskPerUnit = result.NormalizedEntryPrice
            * rules.ContractSize
            * request.EstimatedSlippagePercent
            / 100m;
        var normalizedMonetaryRisk = result.NormalizedQuantity
            * (stopRiskPerUnit + feeRiskPerUnit + slippageRiskPerUnit);

        Assert.True(result.IsApproved);
        Assert.Equal(100.1m, result.NormalizedEntryPrice);
        Assert.Equal(95.0m, result.NormalizedStopLoss);
        Assert.Equal(110.0m, result.NormalizedTakeProfit);
        Assert.True(normalizedMonetaryRisk <= result.RiskAmount);
        Assert.NotEmpty(result.Warnings);
    }

    [Fact]
    public void RejectsLongTargetThatCrossesEntryAfterNormalization()
    {
        var request = CreateRequest() with
        {
            EntryPrice = 100.04m,
            StopLoss = 99.86m,
            TakeProfit = 100.06m
        };

        var result = DeterministicRiskEngine.Evaluate(
            request,
            CreatePolicy(),
            CreateInstrumentRules());

        Assert.False(result.IsApproved);
        Assert.Equal(100.1m, result.NormalizedEntryPrice);
        Assert.Equal(100.0m, result.NormalizedTakeProfit);
        Assert.Contains(RiskDecisionCode.InvalidTakeProfit, result.RejectionReasons);
    }

    [Fact]
    public void RejectsShortTargetThatCrossesEntryAfterNormalization()
    {
        var request = CreateRequest() with
        {
            Direction = TradeDirection.Short,
            EntryPrice = 100.06m,
            StopLoss = 100.24m,
            TakeProfit = 100.04m
        };

        var result = DeterministicRiskEngine.Evaluate(
            request,
            CreatePolicy(),
            CreateInstrumentRules());

        Assert.False(result.IsApproved);
        Assert.Equal(100.0m, result.NormalizedEntryPrice);
        Assert.Equal(100.1m, result.NormalizedTakeProfit);
        Assert.Contains(RiskDecisionCode.InvalidTakeProfit, result.RejectionReasons);
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
            1.8m,
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
