using Quantara.Domain.Trading;

namespace Quantara.Domain.Analysis;

public enum PriceZoneRole
{
    Support,
    Resistance,
    Pivot
}

public enum PriceZoneState
{
    Active,
    Flipped
}

public enum MarketStructureDirection
{
    Bullish,
    Bearish,
    Sideways
}

public enum PriceStructureBuildCode
{
    Created,
    InvalidSpecification,
    InsufficientCandles,
    InvalidCandle,
    MixedSymbol,
    MixedTimeframe,
    DuplicateCandle,
    UnorderedCandle,
    MissingCandle
}

public sealed record PriceStructureSpecification(
    int PivotRadius,
    int AtrPeriod,
    int MinimumTouches,
    decimal ZoneAtrMultiplier,
    decimal MinimumZoneWidthBps,
    decimal BreakoutAtrMultiplier,
    int RecencyHalfLifeBars,
    int MaximumZones)
{
    public static PriceStructureSpecification Conservative { get; } = new(
        PivotRadius: 2,
        AtrPeriod: 14,
        MinimumTouches: 2,
        ZoneAtrMultiplier: 0.55m,
        MinimumZoneWidthBps: 8m,
        BreakoutAtrMultiplier: 0.75m,
        RecencyHalfLifeBars: 80,
        MaximumZones: 8);
}

public sealed record PriceStructureZone(
    decimal Lower,
    decimal Upper,
    decimal Center,
    PriceZoneRole Role,
    PriceZoneState State,
    int TouchCount,
    DateTimeOffset FirstTouchedAt,
    DateTimeOffset LastTouchedAt,
    decimal Strength,
    decimal DistancePercent,
    decimal RejectionScore,
    decimal RelativeVolumeScore,
    string Explanation);

public sealed class TimeframePriceStructureAnalysis
{
    internal TimeframePriceStructureAnalysis(
        Symbol symbol,
        TimeSpan timeframe,
        DateTimeOffset asOf,
        decimal currentPrice,
        MarketStructureDirection direction,
        decimal directionStrength,
        decimal volatilityPercent,
        IReadOnlyList<PriceStructureZone> zones,
        IReadOnlyList<string> warnings,
        string fingerprintSha256)
    {
        Symbol = symbol;
        Timeframe = timeframe;
        AsOf = asOf;
        CurrentPrice = currentPrice;
        Direction = direction;
        DirectionStrength = directionStrength;
        VolatilityPercent = volatilityPercent;
        Zones = Array.AsReadOnly(zones.ToArray());
        Warnings = Array.AsReadOnly(warnings.ToArray());
        FingerprintSha256 = fingerprintSha256;
    }

    public Symbol Symbol { get; }

    public TimeSpan Timeframe { get; }

    public DateTimeOffset AsOf { get; }

    public decimal CurrentPrice { get; }

    public MarketStructureDirection Direction { get; }

    public decimal DirectionStrength { get; }

    public decimal VolatilityPercent { get; }

    public IReadOnlyList<PriceStructureZone> Zones { get; }

    public IReadOnlyList<string> Warnings { get; }

    public string FingerprintSha256 { get; }
}

public sealed record PriceStructureBuildResult(
    PriceStructureBuildCode Code,
    string Message,
    TimeframePriceStructureAnalysis? Analysis)
{
    public bool IsCreated => Code == PriceStructureBuildCode.Created;
}

public sealed record MultiTimeframeConfluenceZone(
    decimal Lower,
    decimal Upper,
    decimal Center,
    PriceZoneRole Role,
    int TimeframeCount,
    IReadOnlyList<TimeSpan> Timeframes,
    decimal Strength,
    decimal DistancePercent,
    string Explanation);

public sealed class MultiTimeframePriceStructureAnalysis
{
    internal MultiTimeframePriceStructureAnalysis(
        Symbol symbol,
        DateTimeOffset asOf,
        MarketStructureDirection consensusDirection,
        decimal consensusStrength,
        IReadOnlyList<MultiTimeframeConfluenceZone> zones,
        string fingerprintSha256)
    {
        Symbol = symbol;
        AsOf = asOf;
        ConsensusDirection = consensusDirection;
        ConsensusStrength = consensusStrength;
        Zones = Array.AsReadOnly(zones.ToArray());
        FingerprintSha256 = fingerprintSha256;
    }

    public Symbol Symbol { get; }

    public DateTimeOffset AsOf { get; }

    public MarketStructureDirection ConsensusDirection { get; }

    public decimal ConsensusStrength { get; }

    public IReadOnlyList<MultiTimeframeConfluenceZone> Zones { get; }

    public string FingerprintSha256 { get; }
}

public enum MultiTimeframeBuildCode
{
    Created,
    EmptyAnalyses,
    MixedSymbol,
    DuplicateTimeframe,
    InvalidTolerance
}

public sealed record MultiTimeframeBuildResult(
    MultiTimeframeBuildCode Code,
    string Message,
    MultiTimeframePriceStructureAnalysis? Analysis)
{
    public bool IsCreated => Code == MultiTimeframeBuildCode.Created;
}

