using System.Globalization;
using Quantara.Domain.Trading;

namespace Quantara.Domain.Analysis;

public sealed class DeterministicPriceStructureAnalyzer
{
    private const string SchemaVersion = "price-structure-v1";
    private readonly string _schemaVersion = SchemaVersion;

    public PriceStructureBuildResult Analyze(
        IReadOnlyList<Candle> candles,
        PriceStructureSpecification? specification = null)
    {
        ArgumentNullException.ThrowIfNull(candles);
        specification ??= PriceStructureSpecification.Conservative;

        if (!PriceStructureMath.IsValid(specification))
        {
            return Rejected(
                PriceStructureBuildCode.InvalidSpecification,
                "The price-structure specification is invalid.");
        }

        var minimumCandleCount = Math.Max(
            specification.AtrPeriod + (specification.PivotRadius * 2) + 1,
            24);
        if (candles.Count < minimumCandleCount)
        {
            return Rejected(
                PriceStructureBuildCode.InsufficientCandles,
                $"At least {minimumCandleCount.ToString(CultureInfo.InvariantCulture)} complete candles are required.");
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
        var volumeAverages = PriceStructureMath.CalculateRollingAverages(
            normalizedCandles.Select(static candle => candle.Volume).ToArray(),
            20);
        var candidates = DetectCandidates(
            normalizedCandles,
            averageTrueRanges,
            volumeAverages,
            specification.PivotRadius);
        var currentCandle = normalizedCandles[^1];
        var currentAtr = averageTrueRanges[^1];
        var zones = BuildZones(
            candidates,
            currentCandle,
            currentAtr,
            normalizedCandles.Length,
            specification);
        var (direction, directionStrength) = CalculateDirection(
            normalizedCandles,
            currentAtr);
        var volatilityPercent = PriceStructureMath.RoundScore(
            currentAtr / currentCandle.Close * 100m);
        var warnings = BuildWarnings(zones, candidates.Count);
        var fingerprint = ComputeFingerprint(
            normalizedCandles,
            specification,
            direction,
            directionStrength,
            volatilityPercent,
            zones,
            warnings);

        var analysis = new TimeframePriceStructureAnalysis(
            currentCandle.Symbol,
            currentCandle.Timeframe,
            currentCandle.OpenTime + currentCandle.Timeframe,
            currentCandle.Close,
            direction,
            directionStrength,
            volatilityPercent,
            zones,
            warnings,
            fingerprint);

        return new PriceStructureBuildResult(
            PriceStructureBuildCode.Created,
            "Price structure created from complete candles.",
            analysis);
    }

    private static List<PivotCandidate> DetectCandidates(
        IReadOnlyList<Candle> candles,
        IReadOnlyList<decimal> averageTrueRanges,
        IReadOnlyList<decimal> averageVolumes,
        int radius)
    {
        var candidates = new List<PivotCandidate>();
        for (var index = radius; index < candles.Count - radius; index++)
        {
            var candle = candles[index];
            if (PriceStructureMath.IsConfirmedHigh(candles, index, radius))
            {
                candidates.Add(PivotCluster.Create(
                    candle.High,
                    PivotKind.High,
                    index,
                    candle,
                    averageTrueRanges[index],
                    averageVolumes[index]));
            }

            if (PriceStructureMath.IsConfirmedLow(candles, index, radius))
            {
                candidates.Add(PivotCluster.Create(
                    candle.Low,
                    PivotKind.Low,
                    index,
                    candle,
                    averageTrueRanges[index],
                    averageVolumes[index]));
            }
        }

        return candidates;
    }

    private static PriceStructureZone[] BuildZones(
        IReadOnlyList<PivotCandidate> candidates,
        Candle currentCandle,
        decimal currentAtr,
        int candleCount,
        PriceStructureSpecification specification)
    {
        if (candidates.Count == 0)
        {
            return Array.Empty<PriceStructureZone>();
        }

        var orderedCandidates = candidates
            .OrderBy(static candidate => candidate.Price)
            .ThenBy(static candidate => candidate.CandleIndex)
            .ThenBy(static candidate => candidate.Kind)
            .ToArray();
        var clusters = new List<PivotCluster>();

        foreach (var candidate in orderedCandidates)
        {
            var tolerance = CalculateTolerance(
                candidate.Price,
                candidate.AverageTrueRange,
                specification);
            var target = clusters.Count == 0 ? null : clusters[^1];
            if (target is null
                || candidate.Price > target.Center + Math.Max(target.MaximumTolerance, tolerance))
            {
                clusters.Add(new PivotCluster(candidate, tolerance));
            }
            else
            {
                target.Add(candidate, tolerance);
            }
        }

        var safeCurrentAtr = currentAtr > 0m
            ? currentAtr
            : currentCandle.High - currentCandle.Low;
        var breakoutDistance = safeCurrentAtr * specification.BreakoutAtrMultiplier;
        var zones = new List<PriceStructureZone>();

        foreach (var cluster in clusters)
        {
            if (cluster.Candidates.Count < specification.MinimumTouches)
            {
                continue;
            }

            var halfWidth = Math.Max(
                cluster.AverageTolerance / 2m,
                cluster.Center * specification.MinimumZoneWidthBps / 20000m);
            var lower = cluster.Center - halfWidth;
            var upper = cluster.Center + halfWidth;
            var baseRole = cluster.HighCount > cluster.LowCount
                ? PriceZoneRole.Resistance
                : PriceZoneRole.Support;
            var role = ResolveCurrentRole(lower, upper, currentCandle.Close);
            var state = PriceZoneState.Active;

            if (baseRole == PriceZoneRole.Resistance
                && currentCandle.Close > upper + breakoutDistance)
            {
                role = PriceZoneRole.Support;
                state = PriceZoneState.Flipped;
            }
            else if (baseRole == PriceZoneRole.Support
                && currentCandle.Close < lower - breakoutDistance)
            {
                role = PriceZoneRole.Resistance;
                state = PriceZoneState.Flipped;
            }

            var barsSinceLastTouch = candleCount - 1 - cluster.LastCandleIndex;
            var touchScore = Math.Clamp(cluster.Candidates.Count / 12m, 0m, 1m);
            var recencyScore = 1m / (
                1m + (decimal)barsSinceLastTouch / specification.RecencyHalfLifeBars);
            var rejectionScore = Math.Clamp(cluster.AverageRejectionScore / 1.5m, 0m, 1m);
            var relativeVolumeScore = Math.Clamp(cluster.AverageRelativeVolume / 1.75m, 0m, 1m);
            var strength = (touchScore * 0.45m)
                + (recencyScore * 0.25m)
                + (rejectionScore * 0.20m)
                + (relativeVolumeScore * 0.10m);
            if (state == PriceZoneState.Flipped)
            {
                strength *= 0.90m;
            }

            var distancePercent = Math.Abs(cluster.Center - currentCandle.Close)
                / currentCandle.Close
                * 100m;
            zones.Add(new PriceStructureZone(
                PriceStructureMath.RoundPrice(lower),
                PriceStructureMath.RoundPrice(upper),
                PriceStructureMath.RoundPrice(cluster.Center),
                role,
                state,
                cluster.Candidates.Count,
                cluster.FirstTouchedAt,
                cluster.LastTouchedAt,
                PriceStructureMath.RoundScore(Math.Clamp(strength, 0m, 1m)),
                PriceStructureMath.RoundScore(distancePercent),
                PriceStructureMath.RoundScore(cluster.AverageRejectionScore),
                PriceStructureMath.RoundScore(cluster.AverageRelativeVolume),
                BuildExplanation(role, state, cluster.Candidates.Count, barsSinceLastTouch)));
        }

        return zones
            .OrderByDescending(static zone => zone.Strength)
            .ThenBy(static zone => zone.DistancePercent)
            .ThenBy(static zone => zone.Center)
            .Take(specification.MaximumZones)
            .ToArray();
    }

    private static decimal CalculateTolerance(
        decimal price,
        decimal averageTrueRange,
        PriceStructureSpecification specification)
    {
        var minimumWidth = price * specification.MinimumZoneWidthBps / 10000m;
        var volatilityWidth = averageTrueRange * specification.ZoneAtrMultiplier;
        return Math.Max(minimumWidth, volatilityWidth);
    }

    private static PriceZoneRole ResolveCurrentRole(
        decimal lower,
        decimal upper,
        decimal currentPrice)
    {
        if (currentPrice < lower)
        {
            return PriceZoneRole.Resistance;
        }

        if (currentPrice > upper)
        {
            return PriceZoneRole.Support;
        }

        return PriceZoneRole.Pivot;
    }

    private static (MarketStructureDirection Direction, decimal Strength) CalculateDirection(
        IReadOnlyList<Candle> candles,
        decimal currentAtr)
    {
        var fastWindow = Math.Clamp(candles.Count / 10, 3, 20);
        var slowWindow = Math.Clamp(candles.Count / 3, fastWindow + 1, 100);
        var fastAverage = AverageClose(candles, fastWindow);
        var slowAverage = AverageClose(candles, slowWindow);
        var safeAtr = currentAtr > 0m
            ? currentAtr
            : candles[^1].High - candles[^1].Low;
        if (safeAtr <= 0m)
        {
            return (MarketStructureDirection.Sideways, 0m);
        }

        var normalizedDifference = (fastAverage - slowAverage) / safeAtr;
        var direction = normalizedDifference switch
        {
            >= 0.50m => MarketStructureDirection.Bullish,
            <= -0.50m => MarketStructureDirection.Bearish,
            _ => MarketStructureDirection.Sideways
        };
        var strength = PriceStructureMath.RoundScore(
            Math.Clamp(Math.Abs(normalizedDifference) / 2m, 0m, 1m));
        return (direction, strength);
    }

    private static decimal AverageClose(IReadOnlyList<Candle> candles, int count)
    {
        var sum = 0m;
        for (var index = candles.Count - count; index < candles.Count; index++)
        {
            sum += candles[index].Close;
        }

        return sum / count;
    }

    private static List<string> BuildWarnings(
        IReadOnlyList<PriceStructureZone> zones,
        int candidateCount)
    {
        var warnings = new List<string>();
        if (candidateCount == 0)
        {
            warnings.Add("No confirmed pivots were found in the completed candle window.");
        }
        else if (zones.Count == 0)
        {
            warnings.Add("Confirmed pivots exist, but none met the minimum touch requirement.");
        }

        if (zones.Count > 0 && zones.All(static zone => zone.Strength < 0.45m))
        {
            warnings.Add("All detected zones have low evidence strength.");
        }

        return warnings;
    }

    private static string BuildExplanation(
        PriceZoneRole role,
        PriceZoneState state,
        int touchCount,
        int barsSinceLastTouch)
    {
        var stateText = state == PriceZoneState.Flipped
            ? "role changed after a confirmed break"
            : "active";
        return string.Create(
            CultureInfo.InvariantCulture,
            $"{role}; {stateText}; {touchCount} confirmed touches; last reaction {barsSinceLastTouch} bars ago.");
    }

    private string ComputeFingerprint(
        IReadOnlyList<Candle> candles,
        PriceStructureSpecification specification,
        MarketStructureDirection direction,
        decimal directionStrength,
        decimal volatilityPercent,
        IReadOnlyList<PriceStructureZone> zones,
        IReadOnlyList<string> warnings)
    {
        return PriceStructureMath.ComputeHash(builder =>
        {
            PriceStructureMath.Append(builder, _schemaVersion);
            PriceStructureMath.Append(builder, candles[0].Symbol.Value);
            PriceStructureMath.Append(builder, candles[0].Timeframe.Ticks);
            PriceStructureMath.Append(builder, specification.PivotRadius);
            PriceStructureMath.Append(builder, specification.AtrPeriod);
            PriceStructureMath.Append(builder, specification.MinimumTouches);
            PriceStructureMath.Append(builder, specification.ZoneAtrMultiplier);
            PriceStructureMath.Append(builder, specification.MinimumZoneWidthBps);
            PriceStructureMath.Append(builder, specification.BreakoutAtrMultiplier);
            PriceStructureMath.Append(builder, specification.RecencyHalfLifeBars);
            PriceStructureMath.Append(builder, specification.MaximumZones);

            foreach (var candle in candles)
            {
                PriceStructureMath.Append(builder, candle.OpenTime.ToUniversalTime().Ticks);
                PriceStructureMath.Append(builder, candle.Open);
                PriceStructureMath.Append(builder, candle.High);
                PriceStructureMath.Append(builder, candle.Low);
                PriceStructureMath.Append(builder, candle.Close);
                PriceStructureMath.Append(builder, candle.Volume);
            }

            PriceStructureMath.Append(builder, direction.ToString());
            PriceStructureMath.Append(builder, directionStrength);
            PriceStructureMath.Append(builder, volatilityPercent);
            foreach (var zone in zones)
            {
                PriceStructureMath.Append(builder, zone.Lower);
                PriceStructureMath.Append(builder, zone.Upper);
                PriceStructureMath.Append(builder, zone.Center);
                PriceStructureMath.Append(builder, zone.Role.ToString());
                PriceStructureMath.Append(builder, zone.State.ToString());
                PriceStructureMath.Append(builder, zone.TouchCount);
                PriceStructureMath.Append(builder, zone.FirstTouchedAt.ToUniversalTime().Ticks);
                PriceStructureMath.Append(builder, zone.LastTouchedAt.ToUniversalTime().Ticks);
                PriceStructureMath.Append(builder, zone.Strength);
                PriceStructureMath.Append(builder, zone.DistancePercent);
                PriceStructureMath.Append(builder, zone.RejectionScore);
                PriceStructureMath.Append(builder, zone.RelativeVolumeScore);
                PriceStructureMath.Append(builder, zone.Explanation);
            }

            foreach (var warning in warnings)
            {
                PriceStructureMath.Append(builder, warning);
            }
        });
    }

    private static PriceStructureBuildResult Rejected(
        PriceStructureBuildCode code,
        string message)
    {
        return new PriceStructureBuildResult(code, message, null);
    }
}
