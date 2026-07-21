using Quantara.Domain.Trading;

namespace Quantara.Domain.Execution;

public enum ExecutionApplicationCode
{
    Applied,
    DuplicateIgnored,
    ConflictingDuplicate,
    InvalidEvent,
    WrongOrder,
    WrongSymbol,
    WrongSide,
    OverfillRejected,
    ReduceOnlyViolation
}

public enum OrderFillStatus
{
    Unfilled,
    PartiallyFilled,
    Filled
}

public sealed record ExecutionFill(
    string FillId,
    string OrderId,
    Symbol Symbol,
    OrderSide Side,
    decimal Price,
    decimal Quantity,
    decimal Fee,
    DateTimeOffset OccurredAt,
    bool IsReduceOnly);

public sealed record FundingSettlement(
    string SettlementId,
    Symbol Symbol,
    decimal NetAmount,
    DateTimeOffset OccurredAt);

public sealed record OrderFillSnapshot(
    string OrderId,
    Symbol Symbol,
    OrderSide Side,
    decimal RequestedQuantity,
    decimal FilledQuantity,
    decimal RemainingQuantity,
    decimal AverageFillPrice,
    decimal FeesPaid,
    OrderFillStatus Status);

public sealed record PositionSnapshot(
    Symbol Symbol,
    TradeDirection? Direction,
    decimal Quantity,
    decimal SignedQuantity,
    decimal AverageEntryPrice,
    decimal ContractMultiplier,
    decimal GrossRealizedPnl,
    decimal FeesPaid,
    decimal FundingNet,
    decimal NetRealizedPnl);

public sealed record OrderFillApplicationResult(
    ExecutionApplicationCode Code,
    OrderFillSnapshot Previous,
    OrderFillSnapshot Current,
    string Message);

public sealed record PositionFillApplicationResult(
    ExecutionApplicationCode Code,
    PositionSnapshot Previous,
    PositionSnapshot Current,
    decimal GrossRealizedPnlDelta,
    decimal FeeDelta,
    string Message);

public sealed record FundingApplicationResult(
    ExecutionApplicationCode Code,
    PositionSnapshot Previous,
    PositionSnapshot Current,
    decimal FundingDelta,
    string Message);

public sealed record PositionValuation(
    PositionSnapshot Position,
    decimal MarkPrice,
    decimal UnrealizedPnl,
    decimal NetPnl);
