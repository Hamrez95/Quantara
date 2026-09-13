using Quantara.Domain.Trading;

namespace Quantara.Domain.Analysis;

public sealed class DeterministicDowStructureAnalyzer
{
    public DowStructureBuildResult Analyze(
        IReadOnlyList<Candle> candles,
        DowStructureSpecification? specification = null)
    {
        ArgumentNullException.ThrowIfNull(candles);
        specification ??= DowStructureSpecification.Conservative;

        if (!specification.IsValid)
        {
            return Rejected(
                PriceStructureBuildCode.InvalidSpecification,
                "The Dow structure specification is invalid.");
        }

        var minimumCandleCount = Math.Max(
            specification.AtrPeriod + (specification.ExternalPivotRadius * 2) + 1,
            24);
        if (candles.Count < minimumCandleCount)
        {
            return Rejected(
                PriceStructureBuildCode.InsufficientCandles,
                $"At least {minimumCandleCount} complete candles are required for Dow structure.");
        }

        var validation = PriceStructureMath.ValidateCandles(candles);
        if (validation.Code != PriceStructureBuildCode.Created)
        {
            return Rejected(validation.Code, validation.Message);
        }

        var normalizedCandles = candles
            .Select(static candle => candle with
            {
                OpenTime = candle.OpenTime.ToUniversalTime()
            })
            .ToArray();
        var trueRanges = PriceStructureMath.CalculateTrueRanges(normalizedCandles);
        var averageTrueRanges = PriceStructureMath.CalculateRollingAverages(
            trueRanges,
            specification.AtrPeriod);
        var internalStructure = BuildLayer(
            normalizedCandles,
            averageTrueRanges,
            DowStructureLayer.Internal,
            specification.InternalPivotRadius,
            specification);
        var externalStructure = BuildLayer(
            normalizedCandles,
            averageTrueRanges,
            DowStructureLayer.External,
            specification.ExternalPivotRadius,
            specification);
        var asOf = normalizedCandles[^1].OpenTime + normalizedCandles[^1].Timeframe;
        var fingerprint = ComputeFingerprint(
            normalizedCandles,
            specification,
            internalStructure,
            externalStructure);

        return new DowStructureBuildResult(
            PriceStructureBuildCode.Created,
            "Dow structure created from confirmed pivots and closed candles.",
            new DowStructureSnapshot(
                asOf,
                specification.ConfigVersion,
                specification.EnabledForDecisionAuthority,
                internalStructure,
                externalStructure,
                fingerprint));
    }

    private static DowStructureLayerSnapshot BuildLayer(
        IReadOnlyList<Candle> candles,
        IReadOnlyList<decimal> averageTrueRanges,
        DowStructureLayer layer,
        int radius,
        DowStructureSpecification specification)
    {
        var swings = DetectSwings(candles, layer, radius);
        var events = DetectEvents(
            candles,
            averageTrueRanges,
            swings,
            layer,
            specification);
        var state = ResolveState(swings);
        return new DowStructureLayerSnapshot(layer, state, swings, events);
    }

    private static DowSwingPoint[] DetectSwings(
        IReadOnlyList<Candle> candles,
        DowStructureLayer layer,
        int radius)
    {
        var swings = new List<DowSwingPoint>();
        decimal? previousHigh = null;
        decimal? previousLow = null;

        for (var index = radius; index < candles.Count - radius; index++)
        {
            if (PriceStructureMath.IsConfirmedHigh(candles, index, radius))
            {
                var price = candles[index].High;
                swings.Add(CreateSwing(
                    candles,
                    layer,
                    DowSwingKind.High,
                    ClassifyHigh(price, previousHigh),
                    price,
                    index,
                    index + radius));
                previousHigh = price;
            }

            if (PriceStructureMath.IsConfirmedLow(candles, index, radius))
            {
                var price = candles[index].Low;
                swings.Add(CreateSwing(
                    candles,
                    layer,
                    DowSwingKind.Low,
                    ClassifyLow(price, previousLow),
                    price,
                    index,
                    index + radius));
                previousLow = price;
            }
        }

        return swings
            .OrderBy(static swing => swing.ConfirmedAtCandleIndex)
            .ThenBy(static swing => swing.CandleIndex)
            .ThenBy(static swing => swing.Kind)
            .ToArray();
    }

    private static DowSwingPoint CreateSwing(
        IReadOnlyList<Candle> candles,
        DowStructureLayer layer,
        DowSwingKind kind,
        DowSwingClassification classification,
        decimal price,
        int candleIndex,
        int confirmedAtCandleIndex)
    {
        var candle = candles[candleIndex];
        var confirmation = candles[confirmedAtCandleIndex];
        return new DowSwingPoint(
            layer,
            kind,
            classification,
            PriceStructureMath.RoundPrice(price),
            candleIndex,
            confirmedAtCandleIndex,
            candle.OpenTime + candle.Timeframe,
            confirmation.OpenTime + confirmation.Timeframe);
    }

    private static DowSwingClassification ClassifyHigh(decimal price, decimal? previous)
    {
        if (!previous.HasValue)
        {
            return DowSwingClassification.Unknown;
        }

        if (price > previous.Value)
        {
            return DowSwingClassification.HigherHigh;
        }

        return price < previous.Value
            ? DowSwingClassification.LowerHigh
            : DowSwingClassification.EqualHigh;
    }

    private static DowSwingClassification ClassifyLow(decimal price, decimal? previous)
    {
        if (!previous.HasValue)
        {
            return DowSwingClassification.Unknown;
        }

        if (price > previous.Value)
        {
            return DowSwingClassification.HigherLow;
        }

        return price < previous.Value
            ? DowSwingClassification.LowerLow
            : DowSwingClassification.EqualLow;
    }

    private static DowStructureEvent[] DetectEvents(
        IReadOnlyList<Candle> candles,
        IReadOnlyList<decimal> averageTrueRanges,
        IReadOnlyList<DowSwingPoint> swings,
        DowStructureLayer layer,
        DowStructureSpecification specification)
    {
        var events = new List<DowStructureEvent>();
        var brokenHighs = new HashSet<int>();
        var brokenLows = new HashSet<int>();
        var failedHighs = new HashSet<int>();
        var failedLows = new HashSet<int>();
        var pendingHighBreaks = new Dictionary<int, int>();
        var pendingLowBreaks = new Dictionary<int, int>();

        for (var index = 0; index < candles.Count; index++)
        {
            var available = swings
                .Where(swing => swing.ConfirmedAtCandleIndex <= index)
                .ToArray();
            if (available.Length == 0)
            {
                continue;
            }

            var high = available.LastOrDefault(static swing => swing.Kind == DowSwingKind.High);
            var low = available.LastOrDefault(static swing => swing.Kind == DowSwingKind.Low);
            var context = ResolveState(available);

            if (high is not null && !brokenHighs.Contains(high.CandleIndex))
            {
                if (candles[index].Close > high.Price)
                {
                    pendingHighBreaks.TryAdd(high.CandleIndex, index);
                }

                if (HasAcceptedBreak(
                    candles,
                    averageTrueRanges,
                    index,
                    high.Price,
                    true,
                    specification))
                {
                    events.Add(CreateBreakEvent(
                        candles[index],
                        index,
                        layer,
                        context == DowMarketState.BearishContinuation
                            ? DowStructureEventType.ChochUp
                            : DowStructureEventType.BosUp,
                        high.Price,
                        context == DowMarketState.BearishContinuation
                            ? "DOW_CHOCH_UP_CONFIRMED"
                            : "DOW_BOS_UP_CONFIRMED",
                        specification.ConfigVersion));
                    brokenHighs.Add(high.CandleIndex);
                    pendingHighBreaks.Remove(high.CandleIndex);
                }
                else if (pendingHighBreaks.TryGetValue(high.CandleIndex, out var pendingAt)
                    && index > pendingAt
                    && index - pendingAt <= specification.FailedBreakWindowBars
                    && candles[index].Close <= high.Price
                    && failedHighs.Add(high.CandleIndex))
                {
                    events.Add(CreateBreakEvent(
                        candles[index],
                        index,
                        layer,
                        DowStructureEventType.FailedBreakUp,
                        high.Price,
                        "DOW_FAILED_BREAK_UP_RECLAIMED",
                        specification.ConfigVersion));
                    pendingHighBreaks.Remove(high.CandleIndex);
                }
            }

            if (low is not null && !brokenLows.Contains(low.CandleIndex))
            {
                if (candles[index].Close < low.Price)
                {
                    pendingLowBreaks.TryAdd(low.CandleIndex, index);
                }

                if (HasAcceptedBreak(
                    candles,
                    averageTrueRanges,
                    index,
                    low.Price,
                    false,
                    specification))
                {
                    events.Add(CreateBreakEvent(
                        candles[index],
                        index,
                        layer,
                        context == DowMarketState.BullishContinuation
                            ? DowStructureEventType.ChochDown
                            : DowStructureEventType.BosDown,
                        low.Price,
                        context == DowMarketState.BullishContinuation
                            ? "DOW_CHOCH_DOWN_CONFIRMED"
                            : "DOW_BOS_DOWN_CONFIRMED",
                        specification.ConfigVersion));
                    brokenLows.Add(low.CandleIndex);
                    pendingLowBreaks.Remove(low.CandleIndex);
                }
                else if (pendingLowBreaks.TryGetValue(low.CandleIndex, out var pendingAt)
                    && index > pendingAt
                    && index - pendingAt <= specification.FailedBreakWindowBars
                    && candles[index].Close >= low.Price
                    && failedLows.Add(low.CandleIndex))
                {
                    events.Add(CreateBreakEvent(
                        candles[index],
                        index,
                        layer,
                        DowStructureEventType.FailedBreakDown,
                        low.Price,
                        "DOW_FAILED_BREAK_DOWN_RECLAIMED",
                        specification.ConfigVersion));
                    pendingLowBreaks.Remove(low.CandleIndex);
                }
            }
        }

        return events
            .OrderBy(static item => item.CandleIndex)
            .ThenBy(static item => item.Type)
            .ToArray();
    }

    private static bool HasAcceptedBreak(
        IReadOnlyList<Candle> candles,
        IReadOnlyList<decimal> averageTrueRanges,
        int index,
        decimal pivotPrice,
        bool upward,
        DowStructureSpecification specification)
    {
        var firstIndex = index - specification.AcceptanceBars + 1;
        if (firstIndex < 0)
        {
            return false;
        }

        var hasDisplacement = false;
        for (var candleIndex = firstIndex; candleIndex <= index; candleIndex++)
        {
            var candle = candles[candleIndex];
            var atr = averageTrueRanges[candleIndex];
            var acceptanceDistance = atr * specification.BreakAcceptanceAtr;
            var acceptedClose = upward
                ? candle.Close > pivotPrice + acceptanceDistance
                : candle.Close < pivotPrice - acceptanceDistance;
            if (!acceptedClose)
            {
                return false;
            }

            var body = Math.Abs(candle.Close - candle.Open);
            if (atr > 0m && body >= atr * specification.MinimumDisplacementAtr)
            {
                hasDisplacement = true;
            }
        }

        return specification.MinimumDisplacementAtr == 0m || hasDisplacement;
    }

    private static DowStructureEvent CreateBreakEvent(
        Candle candle,
        int candleIndex,
        DowStructureLayer layer,
        DowStructureEventType type,
        decimal pivotPrice,
        string reasonCode,
        string configVersion)
    {
        return new DowStructureEvent(
            layer,
            type,
            candle.OpenTime + candle.Timeframe,
            candleIndex,
            PriceStructureMath.RoundPrice(pivotPrice),
            PriceStructureMath.RoundPrice(candle.Close),
            reasonCode,
            configVersion);
    }

    private static DowMarketState ResolveState(IReadOnlyList<DowSwingPoint> swings)
    {
        var latest = swings.TakeLast(6).ToArray();
        if (latest.Length >= 4)
        {
            for (var index = 1; index < latest.Length; index++)
            {
                if (latest[index - 1].Kind == latest[index].Kind)
                {
                    return DowMarketState.Disorder;
                }
            }
        }

        var highs = swings
            .Where(static swing => swing.Kind == DowSwingKind.High)
            .TakeLast(2)
            .ToArray();
        var lows = swings
            .Where(static swing => swing.Kind == DowSwingKind.Low)
            .TakeLast(2)
            .ToArray();
        if (highs.Length < 2 || lows.Length < 2)
        {
            return DowMarketState.Unknown;
        }

        var high = highs[^1].Classification;
        var low = lows[^1].Classification;
        if (high == DowSwingClassification.HigherHigh
            && low == DowSwingClassification.HigherLow)
        {
            return DowMarketState.BullishContinuation;
        }

        if (high == DowSwingClassification.LowerHigh
            && low == DowSwingClassification.LowerLow)
        {
            return DowMarketState.BearishContinuation;
        }

        if (high == DowSwingClassification.EqualHigh
            || low == DowSwingClassification.EqualLow)
        {
            return DowMarketState.Range;
        }

        return DowMarketState.Transition;
    }

    private static string ComputeFingerprint(
        IReadOnlyList<Candle> candles,
        DowStructureSpecification specification,
        DowStructureLayerSnapshot internalStructure,
        DowStructureLayerSnapshot externalStructure)
    {
        return PriceStructureMath.ComputeHash(builder =>
        {
            PriceStructureMath.Append(builder, specification.ConfigVersion);
            PriceStructureMath.Append(builder, specification.InternalPivotRadius);
            PriceStructureMath.Append(builder, specification.ExternalPivotRadius);
            PriceStructureMath.Append(builder, specification.AtrPeriod);
            PriceStructureMath.Append(builder, specification.AcceptanceBars);
            PriceStructureMath.Append(builder, specification.BreakAcceptanceAtr);
            PriceStructureMath.Append(builder, specification.MinimumDisplacementAtr);
            PriceStructureMath.Append(builder, specification.FailedBreakWindowBars);
            PriceStructureMath.Append(builder, specification.EnabledForDecisionAuthority);
            PriceStructureMath.Append(builder, candles[0].Symbol.Value);
            PriceStructureMath.Append(builder, candles[0].Timeframe.Ticks);

            AppendLayer(builder, internalStructure);
            AppendLayer(builder, externalStructure);
        });
    }

    private static void AppendLayer(
        System.Text.StringBuilder builder,
        DowStructureLayerSnapshot snapshot)
    {
        PriceStructureMath.Append(builder, snapshot.Layer.ToString());
        PriceStructureMath.Append(builder, snapshot.State.ToString());
        foreach (var swing in snapshot.Swings)
        {
            PriceStructureMath.Append(builder, swing.Kind.ToString());
            PriceStructureMath.Append(builder, swing.Classification.ToString());
            PriceStructureMath.Append(builder, swing.Price);
            PriceStructureMath.Append(builder, swing.CandleIndex);
            PriceStructureMath.Append(builder, swing.ConfirmedAtCandleIndex);
        }

        foreach (var item in snapshot.Events)
        {
            PriceStructureMath.Append(builder, item.Type.ToString());
            PriceStructureMath.Append(builder, item.CandleIndex);
            PriceStructureMath.Append(builder, item.PivotPrice);
            PriceStructureMath.Append(builder, item.ClosePrice);
            PriceStructureMath.Append(builder, item.ReasonCode);
        }
    }

    private static DowStructureBuildResult Rejected(
        PriceStructureBuildCode code,
        string message)
    {
        return new DowStructureBuildResult(code, message, null);
    }
}
