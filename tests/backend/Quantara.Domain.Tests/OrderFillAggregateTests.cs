using Quantara.Domain.Execution;
using Quantara.Domain.Trading;

namespace Quantara.Domain.Tests;

public sealed class OrderFillAggregateTests
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
    public void AppliesPartialFillsAndCalculatesWeightedAverage()
    {
        var aggregate = new OrderFillAggregate(
            "order-1",
            BtcUsdt,
            OrderSide.Buy,
            4m);

        var first = aggregate.Apply(CreateFill("fill-1", 100m, 2m, 1m));
        var second = aggregate.Apply(CreateFill("fill-2", 110m, 2m, 1.5m));

        Assert.Equal(ExecutionApplicationCode.Applied, first.Code);
        Assert.Equal(OrderFillStatus.PartiallyFilled, first.Current.Status);
        Assert.Equal(2m, first.Current.RemainingQuantity);
        Assert.Equal(ExecutionApplicationCode.Applied, second.Code);
        Assert.Equal(OrderFillStatus.Filled, second.Current.Status);
        Assert.Equal(4m, second.Current.FilledQuantity);
        Assert.Equal(0m, second.Current.RemainingQuantity);
        Assert.Equal(105m, second.Current.AverageFillPrice);
        Assert.Equal(2.5m, second.Current.FeesPaid);
        Assert.Collection(
            aggregate.ProcessedFills,
            fill => Assert.Equal("fill-1", fill.FillId),
            fill => Assert.Equal("fill-2", fill.FillId));
    }

    [Fact]
    public void RejectsOverfillWithoutMutatingSnapshotOrHistory()
    {
        var aggregate = new OrderFillAggregate(
            "order-1",
            BtcUsdt,
            OrderSide.Buy,
            2m);
        Assert.Equal(
            ExecutionApplicationCode.Applied,
            aggregate.Apply(CreateFill("fill-1", 100m, 1.5m, 1m)).Code);
        var before = aggregate.Snapshot;

        var rejected = aggregate.Apply(CreateFill("fill-2", 101m, 1m, 1m));

        Assert.Equal(ExecutionApplicationCode.OverfillRejected, rejected.Code);
        Assert.Equal(before, rejected.Current);
        Assert.Equal(before, aggregate.Snapshot);
        Assert.DoesNotContain(
            aggregate.ProcessedFills,
            fill => string.Equals(fill.FillId, "fill-2", StringComparison.Ordinal));
    }

    [Fact]
    public void RejectsWrongOrderSymbolAndSideWithoutMutation()
    {
        var aggregate = new OrderFillAggregate(
            "order-1",
            BtcUsdt,
            OrderSide.Buy,
            3m);

        var wrongOrder = aggregate.Apply(
            CreateFill("fill-order", 100m, 1m, 0m) with { OrderId = "order-2" });
        var wrongSymbol = aggregate.Apply(
            CreateFill("fill-symbol", 100m, 1m, 0m) with
            {
                Symbol = new Symbol("ETHUSDT")
            });
        var wrongSide = aggregate.Apply(
            CreateFill("fill-side", 100m, 1m, 0m) with { Side = OrderSide.Sell });

        Assert.Equal(ExecutionApplicationCode.WrongOrder, wrongOrder.Code);
        Assert.Equal(ExecutionApplicationCode.WrongSymbol, wrongSymbol.Code);
        Assert.Equal(ExecutionApplicationCode.WrongSide, wrongSide.Code);
        Assert.Equal(OrderFillStatus.Unfilled, aggregate.Snapshot.Status);
        Assert.Empty(aggregate.ProcessedFills);
    }

    [Fact]
    public void TreatsSameInstantWithDifferentOffsetAsIdenticalReplay()
    {
        var aggregate = new OrderFillAggregate(
            "order-1",
            BtcUsdt,
            OrderSide.Buy,
            2m);
        var original = CreateFill("fill-1", 100m, 1m, 0.5m);
        Assert.Equal(ExecutionApplicationCode.Applied, aggregate.Apply(original).Code);
        var replay = original with
        {
            OccurredAt = original.OccurredAt.ToOffset(TimeSpan.FromHours(3))
        };

        var result = aggregate.Apply(replay);

        Assert.Equal(ExecutionApplicationCode.DuplicateIgnored, result.Code);
        Assert.Equal(1m, aggregate.Snapshot.FilledQuantity);
        Assert.Single(aggregate.ProcessedFills);
    }

    [Fact]
    public void RejectsConflictingDuplicateFillIdentifier()
    {
        var aggregate = new OrderFillAggregate(
            "order-1",
            BtcUsdt,
            OrderSide.Buy,
            2m);
        Assert.Equal(
            ExecutionApplicationCode.Applied,
            aggregate.Apply(CreateFill("fill-1", 100m, 1m, 0.5m)).Code);
        var before = aggregate.Snapshot;

        var conflict = aggregate.Apply(CreateFill("fill-1", 101m, 1m, 0.5m));

        Assert.Equal(ExecutionApplicationCode.ConflictingDuplicate, conflict.Code);
        Assert.Equal(before, aggregate.Snapshot);
        Assert.Single(aggregate.ProcessedFills);
    }

    [Fact]
    public void RehydratesOnlyWhenSnapshotReconcilesWithFillHistory()
    {
        var source = new OrderFillAggregate(
            "order-1",
            BtcUsdt,
            OrderSide.Buy,
            2m);
        var fill = CreateFill("fill-1", 100m, 1m, 0.5m);
        Assert.Equal(ExecutionApplicationCode.Applied, source.Apply(fill).Code);

        var rehydrated = OrderFillAggregate.Rehydrate(
            source.Snapshot,
            source.ProcessedFills);
        var replay = rehydrated.Apply(fill);

        Assert.Equal(source.Snapshot, rehydrated.Snapshot);
        Assert.Equal(ExecutionApplicationCode.DuplicateIgnored, replay.Code);
        Assert.Throws<InvalidOperationException>(
            () => OrderFillAggregate.Rehydrate(
                source.Snapshot with { FilledQuantity = 2m, RemainingQuantity = 0m },
                source.ProcessedFills));
    }

    private static ExecutionFill CreateFill(
        string fillId,
        decimal price,
        decimal quantity,
        decimal fee)
    {
        return new ExecutionFill(
            fillId,
            "order-1",
            BtcUsdt,
            OrderSide.Buy,
            price,
            quantity,
            fee,
            Timestamp,
            false);
    }
}
