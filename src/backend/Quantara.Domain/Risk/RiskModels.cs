using Quantara.Domain.Trading;

namespace Quantara.Domain.Risk;

public enum RiskDecisionCode
{
    Approved,
    ReduceOnlyApproved,
    InvalidPolicy,
    InvalidAccountEquity,
    InvalidAvailableBalance,
    InvalidRiskPercentage,
    RiskPerTradeExceeded,
    InvalidEntryPrice,
    InvalidStopLoss,
    InvalidStopDirection,
    InvalidTakeProfit,
    InvalidMarketCost,
    InvalidCorrelationContext,
    MinimumRiskRewardNotMet,
    DailyLossLimitReached,
    WeeklyLossLimitReached,
    DrawdownLimitReached,
    LeverageLimitExceeded,
    PortfolioExposureLimitExceeded,
    SymbolExposureLimitExceeded,
    CorrelatedExposureLimitExceeded,
    ConcurrentPositionLimitReached,
    SpreadLimitExceeded,
    SlippageLimitExceeded,
    StaleMarketData,
    ExchangeDisconnected,
    CircuitBreakerActive,
    CooldownActive,
    ConsecutiveLossLimitReached,
    KillSwitchActive,
    TradingAllocationExceeded,
    InsufficientAvailableBalance,
    InstrumentRuleViolation,
    QuantityBelowMinimum,
    QuantityAboveMaximum,
    MinimumNotionalNotMet
}

public sealed record RiskPolicy(
    string Version,
    decimal MaximumRiskPerTradePercent,
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
    int MaximumConsecutiveLosses,
    decimal MaximumTradingAllocationPercent,
    bool KillSwitchEnabled,
    decimal MaximumCorrelatedExposurePercent = 100m);

public sealed record InstrumentRiskRules(
    decimal TickSize,
    decimal QuantityStep,
    decimal MinimumQuantity,
    decimal MaximumQuantity,
    decimal MinimumNotional,
    decimal ContractSize,
    int PricePrecision,
    int QuantityPrecision,
    decimal MaximumLeverage);

public sealed record CorrelationRiskContext(
    string Group,
    decimal CurrentExposure,
    decimal ProposedExposureFactor);

public sealed record RiskEvaluationRequest(
    Symbol Symbol,
    TradeDirection Direction,
    decimal AccountEquity,
    decimal AvailableBalance,
    decimal EntryPrice,
    decimal StopLoss,
    decimal TakeProfit,
    decimal RequestedRiskPercent,
    decimal Leverage,
    decimal CurrentPortfolioExposure,
    decimal CurrentSymbolExposure,
    decimal CurrentAllocatedCapital,
    int OpenPositionCount,
    decimal CurrentDailyLossPercent,
    decimal CurrentWeeklyLossPercent,
    decimal CurrentDrawdownPercent,
    decimal SpreadPercent,
    decimal EstimatedSlippagePercent,
    decimal RoundTripFeePercent,
    bool MarketDataFresh,
    bool ExchangeConnected,
    bool CircuitBreakerActive,
    bool CooldownActive,
    int ConsecutiveLosses,
    bool IsReduceOnly,
    decimal? RequestedQuantity,
    DateTimeOffset EvaluatedAt);

public sealed record RiskEvaluationResult(
    bool IsApproved,
    RiskDecisionCode DecisionCode,
    IReadOnlyList<RiskDecisionCode> RejectionReasons,
    IReadOnlyList<string> Warnings,
    decimal NormalizedEntryPrice,
    decimal NormalizedStopLoss,
    decimal NormalizedTakeProfit,
    decimal RiskAmount,
    decimal RawQuantity,
    decimal NormalizedQuantity,
    decimal RequiredMargin,
    decimal EstimatedFees,
    decimal EstimatedSlippage,
    decimal PortfolioExposureBefore,
    decimal PortfolioExposureAfter,
    string CorrelationGroup,
    decimal CorrelatedExposureBefore,
    decimal CorrelatedExposureAfter,
    DateTimeOffset EvaluatedAt,
    string RiskPolicyVersion);

public static class PositionSizer
{
    public static Quantity Calculate(
        decimal accountEquity,
        decimal riskPercent,
        decimal entryPrice,
        decimal stopLoss,
        decimal feeReserve,
        decimal slippageReserve)
    {
        var stopDistance = Math.Abs(entryPrice - stopLoss);
        if (accountEquity <= 0m || riskPercent <= 0m || stopDistance <= 0m)
        {
            return new Quantity(0m);
        }

        var riskBudget = accountEquity * (riskPercent / 100m);
        var perUnitRisk = stopDistance + feeReserve + slippageReserve;
        return new Quantity(decimal.Round(riskBudget / perUnitRisk, 8, MidpointRounding.ToZero));
    }
}

