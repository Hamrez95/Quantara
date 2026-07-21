using System.Globalization;

namespace Quantara.Domain.Analysis;

public sealed class MultiTimeframePriceStructureAnalyzer
{
    private const string SchemaVersion = "multi-timeframe-structure-v1";
    private readonly string _schemaVersion = SchemaVersion;

    public MultiTimeframeBuildResult Analyze(
        IReadOnlyList<TimeframePriceStructureAnalysis> analyses,
        decimal mergeToleranceBps = 25m,
        int maximumZones = 8)
    {
        ArgumentNullException.ThrowIfNull(analyses);
        if (analyses.Count == 0)
        {
            return Rejected(
                MultiTimeframeBuildCode.EmptyAnalyses,
                "At least one timeframe analysis is required.");
        }

        if (mergeToleranceBps is <= 0m or > 1000m || maximumZones is < 1 or > 50)
        {
            return Rejected(
                MultiTimeframeBuildCode.InvalidTolerance,
                "Confluence tolerance or maximum-zone count is invalid.");
        }

        var symbol = analyses[0].Symbol;
        var seenTimeframes = new HashSet<TimeSpan>();
        foreach (var analysis in analyses)
        {
            if (!StringComparer.Ordinal.Equals(analysis.Symbol.Value, symbol.Value))
            {
                return Rejected(
                    MultiTimeframeBuildCode.MixedSymbol,
                    "All timeframe analyses must use one symbol.");
            }

            if (!seenTimeframes.Add(analysis.Timeframe))
            {
                return Rejected(
                    MultiTimeframeBuildCode.DuplicateTimeframe,
                    "Each timeframe may appear only once.");
            }
        }

        var orderedAnalyses = analyses
            .OrderBy(static analysis => analysis.Timeframe)
            .ToArray();
        var currentPrice = orderedAnalyses[0].CurrentPrice;
        var candidates = orderedAnalyses
            .SelectMany(analysis => analysis.Zones.Select(zone => new WeightedZone(
                analysis.Timeframe,
                TimeframeWeight(analysis.Timeframe),
                zone)))
            .OrderBy(static candidate => candidate.Zone.Center)
            .ThenBy(static candidate => candidate.Timeframe)
            .ToArray();
        var clusters = Cluster(candidates, mergeToleranceBps);
        var confluenceZones = clusters
            .Select(cluster => BuildZone(cluster, currentPrice))
            .OrderByDescending(static zone => zone.Strength)
            .ThenByDescending(static zone => zone.TimeframeCount)
            .ThenBy(static zone => zone.DistancePercent)
            .Take(maximumZones)
            .ToArray();
        var (direction, directionStrength) = ResolveDirection(orderedAnalyses);
        var asOf = orderedAnalyses.Max(static analysis => analysis.AsOf);
        var fingerprint = ComputeFingerprint(
            orderedAnalyses,
            mergeToleranceBps,
            maximumZones,
            direction,
            directionStrength,
            confluenceZones);
        var result = new MultiTimeframePriceStructureAnalysis(
            symbol,
            asOf,
            direction,
            directionStrength,
            confluenceZones,
            fingerprint);

        return new MultiTimeframeBuildResult(
            MultiTimeframeBuildCode.Created,
            "Multi-timeframe confluence created.",
            result);
    }

    private static List<ConfluenceCluster> Cluster(
        IReadOnlyList<WeightedZone> candidates,
        decimal mergeToleranceBps)
    {
        var clusters = new List<ConfluenceCluster>();
        foreach (var candidate in candidates)
        {
            var tolerance = candidate.Zone.Center * mergeToleranceBps / 10000m;
            var target = clusters.Count == 0 ? null : clusters[^1];
            if (target is null || candidate.Zone.Center > target.Center + tolerance)
            {
                clusters.Add(new ConfluenceCluster(candidate));
            }
            else
            {
                target.Add(candidate);
            }
        }

        return clusters;
    }

    private static MultiTimeframeConfluenceZone BuildZone(
        ConfluenceCluster cluster,
        decimal currentPrice)
    {
        var distinctTimeframes = cluster.Candidates
            .Select(static candidate => candidate.Timeframe)
            .Distinct()
            .Order()
            .ToArray();
        var supportWeight = cluster.Candidates
            .Where(static candidate => candidate.Zone.Role == PriceZoneRole.Support)
            .Sum(static candidate => candidate.Weight);
        var resistanceWeight = cluster.Candidates
            .Where(static candidate => candidate.Zone.Role == PriceZoneRole.Resistance)
            .Sum(static candidate => candidate.Weight);
        var role = supportWeight == resistanceWeight
            ? PriceZoneRole.Pivot
            : supportWeight > resistanceWeight
                ? PriceZoneRole.Support
                : PriceZoneRole.Resistance;
        var weightedStrength = cluster.Candidates.Sum(
            static candidate => candidate.Zone.Strength * candidate.Weight);
        var totalWeight = cluster.Candidates.Sum(static candidate => candidate.Weight);
        var confluenceBonus = Math.Min(0.24m, (distinctTimeframes.Length - 1) * 0.08m);
        var strength = PriceStructureMath.RoundScore(
            Math.Clamp(weightedStrength / totalWeight + confluenceBonus, 0m, 1m));
        var distance = PriceStructureMath.RoundScore(
            Math.Abs(cluster.Center - currentPrice) / currentPrice * 100m);
        var timeframeLabel = string.Join(
            ", ",
            distinctTimeframes.Select(FormatTimeframe));
        var explanation = string.Create(
            CultureInfo.InvariantCulture,
            $"{distinctTimeframes.Length} timeframe(s) align near this {role.ToString().ToLowerInvariant()} zone: {timeframeLabel}.");

        return new MultiTimeframeConfluenceZone(
            PriceStructureMath.RoundPrice(cluster.Lower),
            PriceStructureMath.RoundPrice(cluster.Upper),
            PriceStructureMath.RoundPrice(cluster.Center),
            role,
            distinctTimeframes.Length,
            Array.AsReadOnly(distinctTimeframes),
            strength,
            distance,
            explanation);
    }

    private static (MarketStructureDirection Direction, decimal Strength) ResolveDirection(
        IReadOnlyList<TimeframePriceStructureAnalysis> analyses)
    {
        var bullish = 0m;
        var bearish = 0m;
        var totalWeight = 0m;
        foreach (var analysis in analyses)
        {
            var weight = TimeframeWeight(analysis.Timeframe);
            totalWeight += weight;
            if (analysis.Direction == MarketStructureDirection.Bullish)
            {
                bullish += weight * analysis.DirectionStrength;
            }
            else if (analysis.Direction == MarketStructureDirection.Bearish)
            {
                bearish += weight * analysis.DirectionStrength;
            }
        }

        var difference = bullish - bearish;
        var threshold = totalWeight * 0.10m;
        var direction = difference switch
        {
            > 0m when difference >= threshold => MarketStructureDirection.Bullish,
            < 0m when -difference >= threshold => MarketStructureDirection.Bearish,
            _ => MarketStructureDirection.Sideways
        };
        var strength = totalWeight == 0m
            ? 0m
            : PriceStructureMath.RoundScore(Math.Clamp(Math.Abs(difference) / totalWeight, 0m, 1m));
        return (direction, strength);
    }

    private static decimal TimeframeWeight(TimeSpan timeframe)
    {
        if (timeframe <= TimeSpan.FromMinutes(15))
        {
            return 1m;
        }

        if (timeframe <= TimeSpan.FromHours(1))
        {
            return 2m;
        }

        if (timeframe <= TimeSpan.FromHours(4))
        {
            return 3m;
        }

        if (timeframe <= TimeSpan.FromDays(1))
        {
            return 4m;
        }

        return 5m;
    }

    private static string FormatTimeframe(TimeSpan timeframe)
    {
        if (timeframe.TotalDays >= 1 && timeframe.TotalDays % 1 == 0)
        {
            return string.Create(
                CultureInfo.InvariantCulture,
                $"{timeframe.TotalDays:0}D");
        }

        if (timeframe.TotalHours >= 1 && timeframe.TotalHours % 1 == 0)
        {
            return string.Create(
                CultureInfo.InvariantCulture,
                $"{timeframe.TotalHours:0}h");
        }

        return string.Create(
            CultureInfo.InvariantCulture,
            $"{timeframe.TotalMinutes:0}m");
    }

    private string ComputeFingerprint(
        IReadOnlyList<TimeframePriceStructureAnalysis> analyses,
        decimal mergeToleranceBps,
        int maximumZones,
        MarketStructureDirection direction,
        decimal directionStrength,
        IReadOnlyList<MultiTimeframeConfluenceZone> zones)
    {
        return PriceStructureMath.ComputeHash(builder =>
        {
            PriceStructureMath.Append(builder, _schemaVersion);
            PriceStructureMath.Append(builder, mergeToleranceBps);
            PriceStructureMath.Append(builder, maximumZones);
            foreach (var analysis in analyses)
            {
                PriceStructureMath.Append(builder, analysis.Timeframe.Ticks);
                PriceStructureMath.Append(builder, analysis.FingerprintSha256);
            }

            PriceStructureMath.Append(builder, direction.ToString());
            PriceStructureMath.Append(builder, directionStrength);
            foreach (var zone in zones)
            {
                PriceStructureMath.Append(builder, zone.Lower);
                PriceStructureMath.Append(builder, zone.Upper);
                PriceStructureMath.Append(builder, zone.Center);
                PriceStructureMath.Append(builder, zone.Role.ToString());
                PriceStructureMath.Append(builder, zone.TimeframeCount);
                PriceStructureMath.Append(builder, zone.Strength);
                PriceStructureMath.Append(builder, zone.DistancePercent);
                PriceStructureMath.Append(builder, zone.Explanation);
                foreach (var timeframe in zone.Timeframes)
                {
                    PriceStructureMath.Append(builder, timeframe.Ticks);
                }
            }
        });
    }

    private static MultiTimeframeBuildResult Rejected(
        MultiTimeframeBuildCode code,
        string message)
    {
        return new MultiTimeframeBuildResult(code, message, null);
    }

    private sealed record WeightedZone(
        TimeSpan Timeframe,
        decimal Weight,
        PriceStructureZone Zone);

    private sealed class ConfluenceCluster
    {
        private decimal _weightedCenter;
        private decimal _totalWeight;

        public ConfluenceCluster(WeightedZone candidate)
        {
            Candidates.Add(candidate);
            _weightedCenter = candidate.Zone.Center * candidate.Weight;
            _totalWeight = candidate.Weight;
            Lower = candidate.Zone.Lower;
            Upper = candidate.Zone.Upper;
        }

        public List<WeightedZone> Candidates { get; } = new();

        public decimal Lower { get; private set; }

        public decimal Upper { get; private set; }

        public decimal Center => _weightedCenter / _totalWeight;

        public void Add(WeightedZone candidate)
        {
            Candidates.Add(candidate);
            _weightedCenter += candidate.Zone.Center * candidate.Weight;
            _totalWeight += candidate.Weight;
            Lower = Math.Min(Lower, candidate.Zone.Lower);
            Upper = Math.Max(Upper, candidate.Zone.Upper);
        }
    }
}

