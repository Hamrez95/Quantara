using Quantara.Domain.Orders;

namespace Quantara.Domain.Tests;

public sealed class OrderStateMachineTests
{
    [Fact]
    public void AppliesValidLifecycleFromCreationToFill()
    {
        var order = new OrderAggregate("order-1");

        AssertApplied(order, "event-1", OrderState.RiskApproved);
        AssertApplied(order, "event-2", OrderState.SubmissionPending);
        AssertApplied(order, "event-3", OrderState.Submitted);
        AssertApplied(order, "event-4", OrderState.Acknowledged);
        AssertApplied(order, "event-5", OrderState.PartiallyFilled);
        AssertApplied(order, "event-6", OrderState.Filled);

        Assert.Equal(OrderState.Filled, order.State);
        Assert.True(order.IsTerminal);
    }

    [Fact]
    public void RejectsInvalidTransitionWithoutChangingState()
    {
        var order = new OrderAggregate("order-2");
        var result = order.Apply(CreateEvent("event-1", OrderState.Filled));

        Assert.Equal(OrderEventApplicationCode.InvalidTransition, result.Code);
        Assert.Equal(OrderState.Created, result.PreviousState);
        Assert.Equal(OrderState.Created, result.CurrentState);
        Assert.Equal(OrderState.Created, order.State);
    }

    [Fact]
    public void IgnoresDuplicateEventIdentifierIdempotently()
    {
        var order = new OrderAggregate("order-3");
        var orderEvent = CreateEvent("event-1", OrderState.RiskApproved);

        var first = order.Apply(orderEvent);
        var duplicate = order.Apply(orderEvent);

        Assert.Equal(OrderEventApplicationCode.Applied, first.Code);
        Assert.Equal(OrderEventApplicationCode.DuplicateIgnored, duplicate.Code);
        Assert.Equal(OrderState.RiskApproved, order.State);
    }

    [Fact]
    public void AllowsCancellationAfterExchangeAcknowledgement()
    {
        var order = new OrderAggregate("order-4");

        AssertApplied(order, "event-1", OrderState.RiskApproved);
        AssertApplied(order, "event-2", OrderState.SubmissionPending);
        AssertApplied(order, "event-3", OrderState.Submitted);
        AssertApplied(order, "event-4", OrderState.Acknowledged);
        AssertApplied(order, "event-5", OrderState.CancellationPending);
        AssertApplied(order, "event-6", OrderState.Cancelled);

        Assert.True(order.IsTerminal);
    }

    [Fact]
    public void PreventsTransitionOutOfTerminalState()
    {
        var order = new OrderAggregate("order-5");

        AssertApplied(order, "event-1", OrderState.RiskRejected);
        var result = order.Apply(CreateEvent("event-2", OrderState.RiskApproved));

        Assert.Equal(OrderEventApplicationCode.InvalidTransition, result.Code);
        Assert.Equal(OrderState.RiskRejected, order.State);
        Assert.True(order.IsTerminal);
    }

    [Fact]
    public void SupportsRecoveryFromFailureThroughReconciliation()
    {
        var order = new OrderAggregate("order-6");

        AssertApplied(order, "event-1", OrderState.RiskApproved);
        AssertApplied(order, "event-2", OrderState.SubmissionPending);
        AssertApplied(order, "event-3", OrderState.Failed);
        AssertApplied(order, "event-4", OrderState.ReconciliationRequired);
        AssertApplied(order, "event-5", OrderState.Rejected);

        Assert.Equal(OrderState.Rejected, order.State);
        Assert.True(order.IsTerminal);
    }

    private static void AssertApplied(OrderAggregate order, string eventId, OrderState targetState)
    {
        var result = order.Apply(CreateEvent(eventId, targetState));
        Assert.Equal(OrderEventApplicationCode.Applied, result.Code);
        Assert.Equal(targetState, result.CurrentState);
    }

    private static OrderLifecycleEvent CreateEvent(string eventId, OrderState targetState)
    {
        return new OrderLifecycleEvent(
            eventId,
            targetState,
            new DateTimeOffset(2026, 7, 20, 8, 0, 0, TimeSpan.Zero),
            $"Move to {targetState}.");
    }
}
