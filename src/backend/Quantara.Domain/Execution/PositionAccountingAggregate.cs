using Quantara.Domain.Trading;

namespace Quantara.Domain.Execution;

public sealed class PositionAccountingAggregate
{
    private readonly Dictionary<string, ExecutionFill> _processedFills =
        new(StringComparer.Ordinal);
    private readonly Dictionary<string, FundingSettlement> _processedFundingSettlements =
        new(StringComparer.Ordinal);
    private readonly List<ExecutionFill> _appliedFills = [];
    private readonly List<FundingSettlement> _appliedFundingSettlements = [];
    private readonly Symbol _symbol;
    private readonly decimal _contractMultiplier;
    private decimal _signedQuantity;
    private decimal _averageEntryPrice;
    private decimal _grossRealizedPnl;
    private decimal _feesPaid;
    private decimal _fundingNet;

    public PositionAccountingAggregate(Symbol symbol, decimal contractMultiplier)
    {
        ArgumentNullException.ThrowIfNull(symbol);
        ArgumentException.ThrowIfNullOrWhiteSpace(symbol.Value);
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(contractMultiplier);

        _symbol = symbol;
        _contractMultiplier = contractMultiplier;
    }

    public PositionSnapshot Snapshot => CreateSnapshot();

    public IReadOnlyList<ExecutionFill> ProcessedFills => _appliedFills.ToArray();

    public IReadOnlyList<FundingSettlement> ProcessedFundingSettlements =>
        _appliedFundingSettlements.ToArray();

    public static PositionAccountingAggregate Rehydrate(
        PositionSnapshot expectedSnapshot,
        IEnumerable<ExecutionFill> processedFills,
        IEnumerable<FundingSettlement> processedFundingSettlements)
    {
        ArgumentNullException.ThrowIfNull(expectedSnapshot);
        ArgumentNullException.ThrowIfNull(processedFills);
        ArgumentNullException.ThrowIfNull(processedFundingSettlements);

        var aggregate = new PositionAccountingAggregate(
            expectedSnapshot.Symbol,
            expectedSnapshot.ContractMultiplier);

        foreach (var fill in processedFills)
        {
            var result = aggregate.ApplyFill(fill);
            if (result.Code != ExecutionApplicationCode.Applied)
            {
                throw new InvalidOperationException(
                    $"Cannot rehydrate position history because fill '{fill.FillId}' returned {result.Code}.");
            }
        }

        foreach (var settlement in processedFundingSettlements)
        {
            var result = aggregate.ApplyFunding(settlement);
            if (result.Code != ExecutionApplicationCode.Applied)
            {
                throw new InvalidOperationException(
                    $"Cannot rehydrate funding history because settlement '{settlement.SettlementId}' returned {result.Code}.");
            }
        }

        if (aggregate.Snapshot != expectedSnapshot)
        {
            throw new InvalidOperationException(
                "The persisted position snapshot does not reconcile with its execution history.");
        }

        return aggregate;
    }

    public PositionFillApplicationResult ApplyFill(ExecutionFill fill)
    {
        ArgumentNullException.ThrowIfNull(fill);
        ArgumentException.ThrowIfNullOrWhiteSpace(fill.FillId);
        ArgumentNullException.ThrowIfNull(fill.Symbol);

        var normalizedFill = Normalize(fill);
        var previous = CreateSnapshot();

        if (_processedFills.TryGetValue(normalizedFill.FillId, out var existingFill))
        {
            var isIdentical = existingFill == normalizedFill;
            return new PositionFillApplicationResult(
                isIdentical
                    ? ExecutionApplicationCode.DuplicateIgnored
                    : ExecutionApplicationCode.ConflictingDuplicate,
                previous,
                previous,
                0m,
                0m,
                isIdentical
                    ? "The identical fill was already applied and was ignored idempotently."
                    : "The fill identifier is already bound to a different execution payload.");
        }

        if (!IsValidFill(normalizedFill))
        {
            return UnchangedFill(
                ExecutionApplicationCode.InvalidEvent,
                previous,
                "A fill requires a non-empty order identifier, positive price and quantity, and a non-negative fee.");
        }

        if (!SymbolsMatch(normalizedFill.Symbol, _symbol))
        {
            return UnchangedFill(
                ExecutionApplicationCode.WrongSymbol,
                previous,
                "The fill symbol does not match the position symbol.");
        }

        var signedFillQuantity = normalizedFill.Side == OrderSide.Buy
            ? normalizedFill.Quantity
            : -normalizedFill.Quantity;

        if (normalizedFill.IsReduceOnly && !CanApplyReduceOnly(signedFillQuantity))
        {
            return UnchangedFill(
                ExecutionApplicationCode.ReduceOnlyViolation,
                previous,
                "A reduce-only fill cannot open, increase, or reverse a position.");
        }

        var grossRealizedPnlDelta = ApplyQuantityAndPrice(
            signedFillQuantity,
            normalizedFill.Price);
        _grossRealizedPnl += grossRealizedPnlDelta;
        _feesPaid += normalizedFill.Fee;
        _processedFills.Add(normalizedFill.FillId, normalizedFill);
        _appliedFills.Add(normalizedFill);

        return new PositionFillApplicationResult(
            ExecutionApplicationCode.Applied,
            previous,
            CreateSnapshot(),
            grossRealizedPnlDelta,
            normalizedFill.Fee,
            "The fill was applied to the position accounting ledger.");
    }

    public FundingApplicationResult ApplyFunding(FundingSettlement settlement)
    {
        ArgumentNullException.ThrowIfNull(settlement);
        ArgumentException.ThrowIfNullOrWhiteSpace(settlement.SettlementId);
        ArgumentNullException.ThrowIfNull(settlement.Symbol);

        var normalizedSettlement = Normalize(settlement);
        var previous = CreateSnapshot();

        if (_processedFundingSettlements.TryGetValue(
            normalizedSettlement.SettlementId,
            out var existingSettlement))
        {
            var isIdentical = existingSettlement == normalizedSettlement;
            return new FundingApplicationResult(
                isIdentical
                    ? ExecutionApplicationCode.DuplicateIgnored
                    : ExecutionApplicationCode.ConflictingDuplicate,
                previous,
                previous,
                0m,
                isIdentical
                    ? "The identical funding settlement was already applied and was ignored idempotently."
                    : "The settlement identifier is already bound to a different funding payload.");
        }

        if (!SymbolsMatch(normalizedSettlement.Symbol, _symbol))
        {
            return new FundingApplicationResult(
                ExecutionApplicationCode.WrongSymbol,
                previous,
                previous,
                0m,
                "The funding settlement symbol does not match the position symbol.");
        }

        _fundingNet += normalizedSettlement.NetAmount;
        _processedFundingSettlements.Add(
            normalizedSettlement.SettlementId,
            normalizedSettlement);
        _appliedFundingSettlements.Add(normalizedSettlement);

        return new FundingApplicationResult(
            ExecutionApplicationCode.Applied,
            previous,
            CreateSnapshot(),
            normalizedSettlement.NetAmount,
            "The funding settlement was applied to the position accounting ledger.");
    }

    public PositionValuation ValueAt(decimal markPrice)
    {
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(markPrice);

        var snapshot = CreateSnapshot();
        var unrealizedPnl = _signedQuantity == 0m
            ? 0m
            : (markPrice - _averageEntryPrice)
                * _signedQuantity
                * _contractMultiplier;

        return new PositionValuation(
            snapshot,
            markPrice,
            unrealizedPnl,
            snapshot.NetRealizedPnl + unrealizedPnl);
    }

    private decimal ApplyQuantityAndPrice(decimal signedFillQuantity, decimal fillPrice)
    {
        if (_signedQuantity == 0m || Math.Sign(_signedQuantity) == Math.Sign(signedFillQuantity))
        {
            var currentAbsoluteQuantity = Math.Abs(_signedQuantity);
            var fillAbsoluteQuantity = Math.Abs(signedFillQuantity);
            var nextAbsoluteQuantity = currentAbsoluteQuantity + fillAbsoluteQuantity;

            _averageEntryPrice = nextAbsoluteQuantity == 0m
                ? 0m
                : ((_averageEntryPrice * currentAbsoluteQuantity)
                    + (fillPrice * fillAbsoluteQuantity))
                    / nextAbsoluteQuantity;
            _signedQuantity += signedFillQuantity;
            return 0m;
        }

        var currentDirection = Math.Sign(_signedQuantity);
        var closingQuantity = Math.Min(
            Math.Abs(_signedQuantity),
            Math.Abs(signedFillQuantity));
        var grossRealizedPnl = (fillPrice - _averageEntryPrice)
            * closingQuantity
            * currentDirection
            * _contractMultiplier;
        var nextSignedQuantity = _signedQuantity + signedFillQuantity;

        if (nextSignedQuantity == 0m)
        {
            _averageEntryPrice = 0m;
        }
        else if (Math.Sign(nextSignedQuantity) != currentDirection)
        {
            _averageEntryPrice = fillPrice;
        }

        _signedQuantity = nextSignedQuantity;
        return grossRealizedPnl;
    }

    private bool CanApplyReduceOnly(decimal signedFillQuantity)
    {
        return _signedQuantity != 0m
            && Math.Sign(_signedQuantity) != Math.Sign(signedFillQuantity)
            && Math.Abs(signedFillQuantity) <= Math.Abs(_signedQuantity);
    }

    private PositionSnapshot CreateSnapshot()
    {
        TradeDirection? direction = _signedQuantity switch
        {
            > 0m => TradeDirection.Long,
            < 0m => TradeDirection.Short,
            _ => null
        };

        return new PositionSnapshot(
            _symbol,
            direction,
            Math.Abs(_signedQuantity),
            _signedQuantity,
            _averageEntryPrice,
            _contractMultiplier,
            _grossRealizedPnl,
            _feesPaid,
            _fundingNet,
            _grossRealizedPnl - _feesPaid + _fundingNet);
    }

    private static PositionFillApplicationResult UnchangedFill(
        ExecutionApplicationCode code,
        PositionSnapshot snapshot,
        string message)
    {
        return new PositionFillApplicationResult(
            code,
            snapshot,
            snapshot,
            0m,
            0m,
            message);
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

    private static FundingSettlement Normalize(FundingSettlement settlement)
    {
        return settlement with { OccurredAt = settlement.OccurredAt.ToUniversalTime() };
    }
}

