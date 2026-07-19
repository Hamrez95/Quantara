using Quantara.Domain.Trading;

namespace Quantara.Domain.Risk;

public sealed record RiskLimits(
    decimal RiskPerTradePercent,
    decimal MaximumDailyLossPercent,
    decimal MaximumWeeklyLossPercent,
    decimal MaximumDrawdownPercent,
    decimal MaximumLeverage,
    decimal MaximumPortfolioExposurePercent,
    decimal MaximumSymbolExposurePercent,
    int MaximumConcurrentPositions,
    decimal MinimumRiskReward,
    decimal MaximumAllowedSpreadPercent,
    decimal MaximumAllowedSlippagePercent,
    bool KillSwitchEnabled);

public sealed record RiskContext(
    Money AccountEquity,
    decimal CurrentDailyLossPercent,
    decimal CurrentWeeklyLossPercent,
    decimal CurrentDrawdownPercent,
    int OpenPositionCount,
    bool MarketDataFresh,
    bool ExchangeConnected,
    bool CircuitBreakerActive);

public sealed record RiskAssessment(bool Approved, Quantity SuggestedQuantity, IReadOnlyList<string> Reasons);

public static class PositionSizer
{
    public static Quantity Calculate(decimal accountEquity, decimal riskPercent, decimal entryPrice, decimal stopLoss, decimal feeReserve, decimal slippageReserve)
    {
        var stopDistance = Math.Abs(entryPrice - stopLoss);
        if (accountEquity <= 0m || riskPercent <= 0m || stopDistance <= 0m) return new Quantity(0m);
        var riskBudget = accountEquity * (riskPercent / 100m);
        var perUnitRisk = stopDistance + feeReserve + slippageReserve;
        return new Quantity(decimal.Round(riskBudget / perUnitRisk, 8, MidpointRounding.ToZero));
    }
}
