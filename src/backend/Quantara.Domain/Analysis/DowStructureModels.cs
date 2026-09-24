namespace Quantara.Domain.Analysis;

public enum DowStructureLayer
{
    Internal,
    External
}

public enum DowSwingKind
{
    High,
    Low
}

public enum DowSwingClassification
{
    Unknown,
    HigherHigh,
    HigherLow,
    LowerHigh,
    LowerLow,
    EqualHigh,
    EqualLow
}

public enum DowStructureEventType
{
    BosUp,
    BosDown,
    ChochUp,
    ChochDown,
    FailedBreakUp,
    FailedBreakDown
}

public enum DowMarketState
{
    Unknown,
    BullishContinuation,
    BearishContinuation,
    Range,
    Transition,
    Disorder
}

public sealed record DowStructureSpecification(
    int InternalPivotRadius,
    int ExternalPivotRadius,
    int AtrPeriod,
    int AcceptanceBars,
    decimal BreakAcceptanceAtr,
    decimal MinimumDisplacementAtr,
    int FailedBreakWindowBars,
    string ConfigVersion,
    bool EnabledForDecisionAuthority)
{
    public static DowStructureSpecification Conservative { get; } = new(
        InternalPivotRadius: 2,
        ExternalPivotRadius: 5,
        AtrPeriod: 14,
        AcceptanceBars: 2,
        BreakAcceptanceAtr: 0.10m,
        MinimumDisplacementAtr: 0.35m,
        FailedBreakWindowBars: 3,
        ConfigVersion: "dow-structure-v1",
        EnabledForDecisionAuthority: false);

    public bool IsValid => InternalPivotRadius > 0
        && ExternalPivotRadius >= InternalPivotRadius
        && AtrPeriod > 1
        && AcceptanceBars > 0
        && BreakAcceptanceAtr >= 0m
        && MinimumDisplacementAtr >= 0m
        && FailedBreakWindowBars > 0
        && !string.IsNullOrWhiteSpace(ConfigVersion);
}

public sealed record DowSwingPoint(
    DowStructureLayer Layer,
    DowSwingKind Kind,
    DowSwingClassification Classification,
    decimal Price,
    int CandleIndex,
    int ConfirmedAtCandleIndex,
    DateTimeOffset OccurredAt,
    DateTimeOffset ConfirmedAt);

public sealed record DowStructureEvent(
    DowStructureLayer Layer,
    DowStructureEventType Type,
    DateTimeOffset OccurredAt,
    int CandleIndex,
    decimal PivotPrice,
    decimal ClosePrice,
    string ReasonCode,
    string ConfigVersion);

public sealed class DowStructureLayerSnapshot
{
    internal DowStructureLayerSnapshot(
        DowStructureLayer layer,
        DowMarketState state,
        IReadOnlyList<DowSwingPoint> swings,
        IReadOnlyList<DowStructureEvent> events)
    {
        Layer = layer;
        State = state;
        Swings = Array.AsReadOnly(swings.ToArray());
        Events = Array.AsReadOnly(events.ToArray());
    }

    public DowStructureLayer Layer { get; }

    public DowMarketState State { get; }

    public IReadOnlyList<DowSwingPoint> Swings { get; }

    public IReadOnlyList<DowStructureEvent> Events { get; }

    public DowSwingPoint? LastConfirmedHigh => Swings.LastOrDefault(static swing => swing.Kind == DowSwingKind.High);

    public DowSwingPoint? LastConfirmedLow => Swings.LastOrDefault(static swing => swing.Kind == DowSwingKind.Low);
}

public sealed class DowStructureSnapshot
{
    internal DowStructureSnapshot(
        DateTimeOffset asOf,
        string configVersion,
        bool enabledForDecisionAuthority,
        DowStructureLayerSnapshot internalStructure,
        DowStructureLayerSnapshot externalStructure,
        string fingerprintSha256)
    {
        AsOf = asOf;
        ConfigVersion = configVersion;
        EnabledForDecisionAuthority = enabledForDecisionAuthority;
        Internal = internalStructure;
        External = externalStructure;
        FingerprintSha256 = fingerprintSha256;
    }

    public DateTimeOffset AsOf { get; }

    public string ConfigVersion { get; }

    public bool EnabledForDecisionAuthority { get; }

    public DowStructureLayerSnapshot Internal { get; }

    public DowStructureLayerSnapshot External { get; }

    public string FingerprintSha256 { get; }
}

public sealed record DowStructureBuildResult(
    PriceStructureBuildCode Code,
    string Message,
    DowStructureSnapshot? Snapshot)
{
    public bool IsCreated => Code == PriceStructureBuildCode.Created;
}
