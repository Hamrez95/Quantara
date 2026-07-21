namespace Quantara.Domain.Trading;

#pragma warning disable CA1720 // Long and Short are canonical derivatives position directions, not primitive type references.
public enum TradeDirection { Long, Short }
#pragma warning restore CA1720

public enum DecisionStatus { Rejected, AnalysisOnly, Proposed, Approved, Executed }
public enum OrderSide { Buy, Sell }
public enum OrderType { Market, Limit }

public sealed record Symbol(string Value)
{
    public override string ToString() => Value;
}

public sealed record Money(decimal Amount, string Currency);
public sealed record Price(decimal Value);
public sealed record Quantity(decimal Value);

public sealed record Candle(
    Symbol Symbol,
    DateTimeOffset OpenTime,
    TimeSpan Timeframe,
    decimal Open,
    decimal High,
    decimal Low,
    decimal Close,
    decimal Volume)
{
    public bool IsValid => High >= Low && Open > 0m && High > 0m && Low > 0m && Close > 0m && Volume >= 0m;
}

public sealed record EntryZone(decimal Lower, decimal Upper)
{
    public bool Contains(decimal price) => price >= Lower && price <= Upper;
}

public sealed record TakeProfitTarget(decimal Price, decimal QuantityFraction);

public sealed record TradeDecision(
    Symbol Symbol,
    string StrategyName,
    string StrategyVersion,
    TradeDirection Direction,
    EntryZone EntryZone,
    decimal StopLoss,
    IReadOnlyList<TakeProfitTarget> TakeProfitTargets,
    string InvalidationCondition,
    decimal Confidence,
    IReadOnlyList<string> Reasons,
    decimal RiskReward,
    Quantity SuggestedQuantity,
    Money RequiredMargin,
    Money EstimatedFees,
    decimal EstimatedSlippage,
    DateTimeOffset ExpiresAt,
    DecisionStatus Status);

