using System.Collections.Frozen;
using Quantara.Domain.Trading;

namespace Quantara.Domain.Execution;

public sealed class OrderFillAggregate
{
    private readonly Dictionary<string, ExecutionFill> _processedFills =
        new(StringComparer.Ordinal);
    private readonly string _orderId;
    private readonly Symbol _symbol;
    private readonly OrderSide _side;
    private readonly decimal _requestedQuantity;
    private decimal _filledQuantity;
    private decimal _weightedFillValue;
    private decimal _feesPaid;

    public OrderFillAggregate(
        string orderId,
        Symbol symbol,
        OrderSide side,
        decimal requestedQuantity)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(orderId);
        ArgumentNullException.ThrowIfNull(symbol);
        ArgumentException.ThrowIfNullOrWhiteSpace(symbol.Value);
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(requestedQuantity);

        _orderId = orderId;
        _symbol = symbol;
        _side = side;
        _requestedQuantity = requestedQuantity;
    }

    public OrderFillSnapshot Snapshot => CreateSnapshot();

    public IReadOnlyDictionary<string, ExecutionFill> ProcessedFills =>
        _processedFills.ToFrozenDictionary(StringComparer.Ordinal);

    public static OrderFillAggregate Rehydrate(
        OrderFillSnapshot expectedSnapshot,
        IEnumerable<ExecutionFill> processedFills)
    {
        ArgumentNullException.ThrowIfNull(expectedSnapshot);
        ArgumentNullException.ThrowIfNull(processedFills);

        var aggregate = new OrderFillAggregate(
            expectedSnapshot.OrderId,
            expectedSnapshot.Symbol,
            expectedSnapshot.Side,
            expectedSnapshot.RequestedQuantity);

        foreach (var fill in processedFills)
        {
            var result = aggregate.Apply(fill);
            if (result.Code != ExecutionApplicationCode.Applied)
            {
                throw new InvalidOperationException(
                    $"Cannot rehydrate order fill history because fill '{fill.FillId}' returned {result.Code}.");
            }
        }

        if (aggregate.Snapshot != expectedSnapshot)
        {
            throw new InvalidOperationException(
                "The persisted order fill snapshot does not reconcile with its fill history.");
        }

        return aggregate;
    }

    public OrderFillApplicationResult Apply(ExecutionFill fill)
    {
        ArgumentNullException.ThrowIfNull(fill);
        ArgumentException.ThrowIfNullOrWhiteSpace(fill.FillId);
        ArgumentNullException.ThrowIfNull(fill.Symbol);

        var normalizedFill = Normalize(fill);
        var previous = CreateSnapshot();

        if (_processedFills.TryGetValue(normalizedFill.FillId, out var existingFill))
        {
            var isIdentical = existingFill == normalizedFill;
            return new OrderFillApplicationResult(
                isIdentical
                    ? ExecutionApplicationCode.DuplicateIgnored
                    : ExecutionApplicationCode.ConflictingDuplicate,
                previous,
                previous,
                isIdentical
                    ? "The identical fill was already applied and was ignored idempotently."
                    : "The fill identifier is already bound to a different execution payload.");
        }

        if (!IsValidFill(normalizedFill))
        {
            return Unchanged(
                ExecutionApplicationCode.InvalidEvent,
                previous,
                "A fill requires a non-empty order identifier, positive price and quantity, and a non-negative fee.");
        }

        if (!string.Equals(normalizedFill.OrderId, _orderId, StringComparison.Ordinal))
        {
            return Unchanged(
                ExecutionApplicationCode.WrongOrder,
                previous,
                "The fill belongs to a different order.");
        }

        if (!SymbolsMatch(normalizedFill.Symbol, _symbol))
        {
            return Unchanged(
                ExecutionApplicationCode.WrongSymbol,
                previous,
                "The fill symbol does not match the order symbol.");
        }

        if (normalizedFill.Side != _side)
        {
            return Unchanged(
                ExecutionApplicationCode.WrongSide,
                previous,
                "The fill side does not match the order side.");
        }

        var nextFilledQuantity = _filledQuantity + normalizedFill.Quantity;
        if (nextFilledQuantity > _requestedQuantity)
        {
            return Unchanged(
                ExecutionApplicationCode.OverfillRejected,
                previous,
                "The fill would exceed the order's requested quantity.");
        }

        _filledQuantity = nextFilledQuantity;
        _weightedFillValue += normalizedFill.Price * normalizedFill.Quantity;
        _feesPaid += normalizedFill.Fee;
        _processedFills.Add(normalizedFill.FillId, normalizedFill);

        var current = CreateSnapshot();
        return new OrderFillApplicationResult(
            ExecutionApplicationCode.Applied,
            previous,
            current,
            current.Status == OrderFillStatus.Filled
                ? "The order is fully filled."
                : "The fill was applied and the order remains partially filled.");
    }

    private OrderFillSnapshot CreateSnapshot()
    {
        var remainingQuantity = _requestedQuantity - _filledQuantity;
        var averageFillPrice = _filledQuantity == 0m
            ? 0m
            : _weightedFillValue / _filledQuantity;
        var status = _filledQuantity switch
        {
            0m => OrderFillStatus.Unfilled,
            var quantity when quantity == _requestedQuantity => OrderFillStatus.Filled,
            _ => OrderFillStatus.PartiallyFilled
        };

        return new OrderFillSnapshot(
            _orderId,
            _symbol,
            _side,
            _requestedQuantity,
            _filledQuantity,
            remainingQuantity,
            averageFillPrice,
            _feesPaid,
            status);
    }

    private static OrderFillApplicationResult Unchanged(
        ExecutionApplicationCode code,
        OrderFillSnapshot snapshot,
        string message)
    {
        return new OrderFillApplicationResult(code, snapshot, snapshot, message);
    }

    private static bool IsValidFill(ExecutionFill fill)
    {
        return !string.IsNullOrWhiteSpace(fill.OrderId)
            && !string.IsNullOrWhiteSpace(fill.Symbol.Value)
            && fill.Price > 0m
            && fill.Quantity > 0m
            && fill.Fee >= 0m;
    }

    private static bool SymbolsMatch(Symbol left, Symbol right)
    {
        return string.Equals(left.Value, right.Value, StringComparison.Ordinal);
    }

    private static ExecutionFill Normalize(ExecutionFill fill)
    {
        return fill with { OccurredAt = fill.OccurredAt.ToUniversalTime() };
    }
}
