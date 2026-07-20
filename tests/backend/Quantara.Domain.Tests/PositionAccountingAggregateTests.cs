using Quantara.Domain.Execution;
using Quantara.Domain.Trading;

namespace Quantara.Domain.Tests;

public sealed class PositionAccountingAggregateTests
{
    private static readonly Symbol BtcUsdt = new("BTCUSDT");
    private static readonly DateTimeOffset Timestamp = new(
        2026,
        7,
        20,
        12,
        0,
        0,
        TimeSpan.Zero);

    [Fact]
    public void OpensAndIncreasesLongAtWeightedAveragePrice()
    {
        var aggregate = new PositionAccountingAggregate(BtcUsdt, 1m);

        var first = aggregate.ApplyFill(CreateFill("fill-1", OrderSide.Buy, 100m, 2m));
        var second = aggregate.ApplyFill(CreateFill("fill-2", OrderSide.Buy, 110m, 2m));

        Assert.Equal(ExecutionApplicationCode.Applied, first.Code);
        Assert.Equal(ExecutionApplicationCode.Applied, second.Code);
        Assert.Equal(TradeDirection.Long, aggregate.Snapshot.Direction);
        Assert.Equal(4m, aggregate.Snapshot.Quantity);
        Assert.Equal(105m, aggregate.Snapshot.AverageEntryPrice);
        Assert.Equal(0m, aggregate.Snapshot.GrossRealizedPnl);
    }

    [Fact]
    public void PartiallyReducesLongAndKeepsOriginalEntryPrice()
    {
        var aggregate = new PositionAccountingAggregate(BtcUsdt, 1m);
        Assert.Equal(
            ExecutionApplicationCode.Applied,
            aggregate.ApplyFill(CreateFill("open", OrderSide.Buy, 100m, 3m)).Code);

        var reduction = aggregate.ApplyFill(
            CreateFill("reduce", OrderSide.Sell, 115m, 1m, isReduceOnly: true));

        Assert.Equal(ExecutionApplicationCode.Applied, reduction.Code);
        Assert.Equal(15m, reduction.GrossRealizedPnlDelta);
        Assert.Equal(TradeDirection.Long, reduction.Current.Direction);
        Assert.Equal(2m, reduction.Current.Quantity);
        Assert.Equal(100m, reduction.Current.AverageEntryPrice);
        Assert.Equal(15m, reduction.Current.GrossRealizedPnl);
    }

    [Fact]
    public void ReversesLongToShortAndRealizesOnlyClosedQuantity()
    {
        var aggregate = new PositionAccountingAggregate(BtcUsdt, 1m);
        Assert.Equal(
            ExecutionApplicationCode.Applied,
            aggregate.ApplyFill(CreateFill("open", OrderSide.Buy, 100m, 2m)).Code);

        var reversal = aggregate.ApplyFill(
            CreateFill("reverse", OrderSide.Sell, 90m, 3m));

        Assert.Equal(ExecutionApplicationCode.Applied, reversal.Code);
        Assert.Equal(-20m, reversal.GrossRealizedPnlDelta);
        Assert.Equal(TradeDirection.Short, reversal.Current.Direction);
        Assert.Equal(1m, reversal.Current.Quantity);
        Assert.Equal(-1m, reversal.Current.SignedQuantity);
        Assert.Equal(90m, reversal.Current.AverageEntryPrice);
    }

    [Fact]
    public void CalculatesShortRealizedAndUnrealizedPnlWithContractMultiplier()
    {
        var aggregate = new PositionAccountingAggregate(BtcUsdt, 10m);
        Assert.Equal(
            ExecutionApplicationCode.Applied,
            aggregate.ApplyFill(CreateFill("open", OrderSide.Sell, 100m, 2m)).Code);

        var close = aggregate.ApplyFill(CreateFill("close", OrderSide.Buy, 90m, 1m));
        var valuation = aggregate.ValueAt(80m);

        Assert.Equal(100m, close.GrossRealizedPnlDelta);
        Assert.Equal(TradeDirection.Short, close.Current.Direction);
        Assert.Equal(1m, close.Current.Quantity);
        Assert.Equal(200m, valuation.UnrealizedPnl);
        Assert.Equal(300m, valuation.NetPnl);
    }

    [Fact]
    public void ReduceOnlyCannotOpenIncreaseOrReversePosition()
    {
        var flat = new PositionAccountingAggregate(BtcUsdt, 1m);
        var openRejected = flat.ApplyFill(
            CreateFill("open-reduce-only", OrderSide.Buy, 100m, 1m, isReduceOnly: true));

        var longPosition = new PositionAccountingAggregate(BtcUsdt, 1m);
        Assert.Equal(
            ExecutionApplicationCode.Applied,
            longPosition.ApplyFill(CreateFill("open", OrderSide.Buy, 100m, 2m)).Code);
        var increaseRejected = longPosition.ApplyFill(
            CreateFill("increase", OrderSide.Buy, 101m, 1m, isReduceOnly: true));
        var reversalRejected = longPosition.ApplyFill(
            CreateFill("reverse", OrderSide.Sell, 99m, 3m, isReduceOnly: true));

        Assert.Equal(ExecutionApplicationCode.ReduceOnlyViolation, openRejected.Code);
        Assert.Equal(ExecutionApplicationCode.ReduceOnlyViolation, increaseRejected.Code);
        Assert.Equal(ExecutionApplicationCode.ReduceOnlyViolation, reversalRejected.Code);
        Assert.Equal(2m, longPosition.Snapshot.Quantity);
        Assert.Equal(100m, longPosition.Snapshot.AverageEntryPrice);
        Assert.Single(longPosition.ProcessedFills);
    }

    [Fact]
    public void ReconcilesGrossPnlFeesFundingAndUnrealizedPnlExactly()
    {
        var aggregate = new PositionAccountingAggregate(BtcUsdt, 1m);
        Assert.Equal(
            ExecutionApplicationCode.Applied,
            aggregate.ApplyFill(CreateFill("open", OrderSide.Buy, 100m, 2m, fee: 2m)).Code);
        Assert.Equal(
            ExecutionApplicationCode.Applied,
            aggregate.ApplyFill(CreateFill("reduce", OrderSide.Sell, 110m, 1m, fee: 1m)).Code);
        var funding = aggregate.ApplyFunding(
            new FundingSettlement("funding-1", BtcUsdt, -0.5m, Timestamp));
        var valuation = aggregate.ValueAt(120m);

        Assert.Equal(ExecutionApplicationCode.Applied, funding.Code);
        Assert.Equal(10m, aggregate.Snapshot.GrossRealizedPnl);
        Assert.Equal(3m, aggregate.Snapshot.FeesPaid);
        Assert.Equal(-0.5m, aggregate.Snapshot.FundingNet);
        Assert.Equal(6.5m, aggregate.Snapshot.NetRealizedPnl);
        Assert.Equal(20m, valuation.UnrealizedPnl);
        Assert.Equal(26.5m, valuation.NetPnl);
    }

    [Fact]
    public void HandlesIdenticalAndConflictingFillReplaysWithoutMutation()
    {
        var aggregate = new PositionAccountingAggregate(BtcUsdt, 1m);
        var fill = CreateFill("fill-1", OrderSide.Buy, 100m, 1m, fee: 0.5m);
        Assert.Equal(ExecutionApplicationCode.Applied, aggregate.ApplyFill(fill).Code);
        var before = aggregate.Snapshot;
        var replay = fill with
        {
            OccurredAt = fill.OccurredAt.ToOffset(TimeSpan.FromHours(3))
        };

        var duplicate = aggregate.ApplyFill(replay);
        var conflict = aggregate.ApplyFill(fill with { Price = 101m });

        Assert.Equal(ExecutionApplicationCode.DuplicateIgnored, duplicate.Code);
        Assert.Equal(ExecutionApplicationCode.ConflictingDuplicate, conflict.Code);
        Assert.Equal(before, aggregate.Snapshot);
        Assert.Single(aggregate.ProcessedFills);
    }

    [Fact]
    public void HandlesIdenticalAndConflictingFundingReplaysWithoutMutation()
    {
        var aggregate = new PositionAccountingAggregate(BtcUsdt, 1m);
        var settlement = new FundingSettlement(
            "funding-1",
            BtcUsdt,
            -2m,
            Timestamp);
        Assert.Equal(
            ExecutionApplicationCode.Applied,
            aggregate.ApplyFunding(settlement).Code);
        var before = aggregate.Snapshot;

        var duplicate = aggregate.ApplyFunding(settlement);
        var conflict = aggregate.ApplyFunding(settlement with { NetAmount = 2m });

        Assert.Equal(ExecutionApplicationCode.DuplicateIgnored, duplicate.Code);
        Assert.Equal(ExecutionApplicationCode.ConflictingDuplicate, conflict.Code);
        Assert.Equal(before, aggregate.Snapshot);
        Assert.Single(aggregate.ProcessedFundingSettlements);
    }

    [Fact]
    public void RehydratesOnlyWhenSnapshotReconcilesWithExecutionHistory()
    {
        var source = new PositionAccountingAggregate(BtcUsdt, 1m);
        var fill = CreateFill("fill-1", OrderSide.Buy, 100m, 1m, fee: 0.5m);
        var settlement = new FundingSettlement("funding-1", BtcUsdt, -1m, Timestamp);
        Assert.Equal(ExecutionApplicationCode.Applied, source.ApplyFill(fill).Code);
        Assert.Equal(ExecutionApplicationCode.Applied, source.ApplyFunding(settlement).Code);

        var rehydrated = PositionAccountingAggregate.Rehydrate(
            source.Snapshot,
            source.ProcessedFills.Values,
            source.ProcessedFundingSettlements.Values);

        Assert.Equal(source.Snapshot, rehydrated.Snapshot);
        Assert.Equal(
            ExecutionApplicationCode.DuplicateIgnored,
            rehydrated.ApplyFill(fill).Code);
        Assert.Throws<InvalidOperationException>(
            () => PositionAccountingAggregate.Rehydrate(
                source.Snapshot with { FeesPaid = 2m },
                source.ProcessedFills.Values,
                source.ProcessedFundingSettlements.Values));
    }

    private static ExecutionFill CreateFill(
        string fillId,
        OrderSide side,
        decimal price,
        decimal quantity,
        decimal fee = 0m,
        bool isReduceOnly = false)
    {
        return new ExecutionFill(
            fillId,
            "order-1",
            BtcUsdt,
            side,
            price,
            quantity,
            fee,
            Timestamp,
            isReduceOnly);
    }
}
