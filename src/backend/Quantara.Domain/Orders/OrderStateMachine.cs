namespace Quantara.Domain.Orders;

public enum OrderState
{
    Created,
    RiskRejected,
    RiskApproved,
    SubmissionPending,
    Submitted,
    Acknowledged,
    PartiallyFilled,
    Filled,
    CancellationPending,
    Cancelled,
    Rejected,
    Expired,
    ReconciliationRequired,
    Failed
}

public enum OrderEventApplicationCode
{
    Applied,
    DuplicateIgnored,
    InvalidTransition
}

public sealed record OrderLifecycleEvent(
    string EventId,
    OrderState TargetState,
    DateTimeOffset OccurredAt,
    string Reason);

public sealed record OrderEventApplicationResult(
    OrderEventApplicationCode Code,
    OrderState PreviousState,
    OrderState CurrentState,
    string Message);

public sealed class OrderAggregate
{
    private readonly HashSet<string> _processedEventIds = new(StringComparer.Ordinal);

    public OrderAggregate(string orderId)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(orderId);
        OrderId = orderId;
    }

    public string OrderId { get; }

    public OrderState State { get; private set; } = OrderState.Created;

    public bool IsTerminal => OrderStateMachine.IsTerminal(State);

    public OrderEventApplicationResult Apply(OrderLifecycleEvent orderEvent)
    {
        ArgumentNullException.ThrowIfNull(orderEvent);

        if (string.IsNullOrWhiteSpace(orderEvent.EventId))
        {
            return new OrderEventApplicationResult(
                OrderEventApplicationCode.InvalidTransition,
                State,
                State,
                "An order lifecycle event requires a non-empty event identifier.");
        }

        if (_processedEventIds.Contains(orderEvent.EventId))
        {
            return new OrderEventApplicationResult(
                OrderEventApplicationCode.DuplicateIgnored,
                State,
                State,
                "The event was already applied and was ignored idempotently.");
        }

        var previousState = State;
        if (!OrderStateMachine.CanTransition(previousState, orderEvent.TargetState))
        {
            return new OrderEventApplicationResult(
                OrderEventApplicationCode.InvalidTransition,
                previousState,
                previousState,
                $"Transition from {previousState} to {orderEvent.TargetState} is not allowed.");
        }

        State = orderEvent.TargetState;
        _processedEventIds.Add(orderEvent.EventId);

        return new OrderEventApplicationResult(
            OrderEventApplicationCode.Applied,
            previousState,
            State,
            orderEvent.Reason);
    }
}

public static class OrderStateMachine
{
    private static readonly IReadOnlyDictionary<OrderState, IReadOnlySet<OrderState>> AllowedTransitions =
        new Dictionary<OrderState, IReadOnlySet<OrderState>>
        {
            [OrderState.Created] = CreateSet(
                OrderState.RiskRejected,
                OrderState.RiskApproved,
                OrderState.Expired,
                OrderState.Failed),
            [OrderState.RiskRejected] = CreateSet(),
            [OrderState.RiskApproved] = CreateSet(
                OrderState.SubmissionPending,
                OrderState.Expired,
                OrderState.Failed),
            [OrderState.SubmissionPending] = CreateSet(
                OrderState.Submitted,
                OrderState.Rejected,
                OrderState.ReconciliationRequired,
                OrderState.Failed),
            [OrderState.Submitted] = CreateSet(
                OrderState.Acknowledged,
                OrderState.PartiallyFilled,
                OrderState.Filled,
                OrderState.CancellationPending,
                OrderState.Rejected,
                OrderState.ReconciliationRequired,
                OrderState.Failed),
            [OrderState.Acknowledged] = CreateSet(
                OrderState.PartiallyFilled,
                OrderState.Filled,
                OrderState.CancellationPending,
                OrderState.Cancelled,
                OrderState.Rejected,
                OrderState.Expired,
                OrderState.ReconciliationRequired,
                OrderState.Failed),
            [OrderState.PartiallyFilled] = CreateSet(
                OrderState.Filled,
                OrderState.CancellationPending,
                OrderState.Cancelled,
                OrderState.ReconciliationRequired,
                OrderState.Failed),
            [OrderState.Filled] = CreateSet(),
            [OrderState.CancellationPending] = CreateSet(
                OrderState.Cancelled,
                OrderState.PartiallyFilled,
                OrderState.Filled,
                OrderState.ReconciliationRequired,
                OrderState.Failed),
            [OrderState.Cancelled] = CreateSet(),
            [OrderState.Rejected] = CreateSet(),
            [OrderState.Expired] = CreateSet(),
            [OrderState.ReconciliationRequired] = CreateSet(
                OrderState.Acknowledged,
                OrderState.PartiallyFilled,
                OrderState.Filled,
                OrderState.Cancelled,
                OrderState.Rejected,
                OrderState.Failed),
            [OrderState.Failed] = CreateSet(OrderState.ReconciliationRequired)
        };

    public static bool CanTransition(OrderState currentState, OrderState targetState)
    {
        return AllowedTransitions.TryGetValue(currentState, out var targets)
            && targets.Contains(targetState);
    }

    public static bool IsTerminal(OrderState state)
    {
        return state is OrderState.RiskRejected
            or OrderState.Filled
            or OrderState.Cancelled
            or OrderState.Rejected
            or OrderState.Expired;
    }

    private static IReadOnlySet<OrderState> CreateSet(params OrderState[] states)
    {
        return new HashSet<OrderState>(states);
    }
}
