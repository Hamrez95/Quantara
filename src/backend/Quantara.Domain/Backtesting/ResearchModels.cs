using System.Collections.Frozen;
using Quantara.Domain.Trading;

namespace Quantara.Domain.Backtesting;

public sealed record FundingRatePoint(
    Symbol Symbol,
    DateTimeOffset OccurredAt,
    decimal Rate);

public sealed record DatasetProvenance(
    string Provider,
    string Market,
    string SourceIdentifier,
    string SchemaVersion,
    DateTimeOffset RetrievedAt);

public sealed class HistoricalDatasetManifest
{
    internal HistoricalDatasetManifest(
        string datasetId,
        Symbol symbol,
        TimeSpan timeframe,
        DateTimeOffset startInclusive,
        DateTimeOffset endExclusive,
        int candleCount,
        int fundingPointCount,
        string contentSha256,
        string manifestSha256,
        DatasetProvenance provenance,
        DateTimeOffset createdAt)
    {
        DatasetId = datasetId;
        Symbol = symbol;
        Timeframe = timeframe;
        StartInclusive = startInclusive;
        EndExclusive = endExclusive;
        CandleCount = candleCount;
        FundingPointCount = fundingPointCount;
        ContentSha256 = contentSha256;
        ManifestSha256 = manifestSha256;
        Provenance = provenance;
        CreatedAt = createdAt;
    }

    public string DatasetId { get; }

    public Symbol Symbol { get; }

    public TimeSpan Timeframe { get; }

    public DateTimeOffset StartInclusive { get; }

    public DateTimeOffset EndExclusive { get; }

    public int CandleCount { get; }

    public int FundingPointCount { get; }

    public string ContentSha256 { get; }

    public string ManifestSha256 { get; }

    public DatasetProvenance Provenance { get; }

    public DateTimeOffset CreatedAt { get; }
}

public enum DatasetBuildCode
{
    Created,
    InvalidDatasetIdentifier,
    InvalidProvenance,
    EmptyCandles,
    InvalidCandle,
    MixedSymbol,
    MixedTimeframe,
    DuplicateCandle,
    UnorderedCandle,
    MissingCandle,
    InvalidFundingPoint,
    MixedFundingSymbol,
    DuplicateFundingPoint,
    UnorderedFundingPoint,
    FundingOutsideCoverage
}

public sealed record DatasetBuildResult(
    bool IsCreated,
    IReadOnlyList<DatasetBuildCode> RejectionReasons,
    HistoricalDatasetManifest? Manifest);

public sealed record ResearchWindow(
    DateTimeOffset StartInclusive,
    DateTimeOffset EndExclusive)
{
    public TimeSpan Duration => EndExclusive - StartInclusive;

    public bool Contains(DateTimeOffset timestamp)
    {
        var normalized = timestamp.ToUniversalTime();
        return normalized >= StartInclusive && normalized < EndExclusive;
    }
}

public enum SplitValidationCode
{
    Valid,
    InvalidDatasetManifest,
    InvalidEmbargo,
    InvalidTrainWindow,
    InvalidValidationWindow,
    InvalidTestWindow,
    InvalidHoldoutWindow,
    WindowOutsideDataset,
    TrainMustStartAtDatasetBoundary,
    HoldoutMustEndAtDatasetBoundary,
    NonChronologicalWindows,
    EmbargoViolation
}

public sealed class TemporalSplitPlan
{
    internal TemporalSplitPlan(
        string datasetContentSha256,
        ResearchWindow train,
        ResearchWindow validation,
        ResearchWindow test,
        ResearchWindow holdout,
        TimeSpan minimumEmbargo,
        string fingerprintSha256)
    {
        DatasetContentSha256 = datasetContentSha256;
        Train = train;
        Validation = validation;
        Test = test;
        Holdout = holdout;
        MinimumEmbargo = minimumEmbargo;
        FingerprintSha256 = fingerprintSha256;
    }

    public string DatasetContentSha256 { get; }

    public ResearchWindow Train { get; }

    public ResearchWindow Validation { get; }

    public ResearchWindow Test { get; }

    public ResearchWindow Holdout { get; }

    public TimeSpan MinimumEmbargo { get; }

    public string FingerprintSha256 { get; }
}

public sealed record SplitValidationResult(
    bool IsValid,
    IReadOnlyList<SplitValidationCode> RejectionReasons,
    TemporalSplitPlan? Plan);

public enum ExperimentStage
{
    Train,
    Validation,
    Test,
    Holdout
}

public enum ExperimentManifestCode
{
    Created,
    InvalidExperimentIdentifier,
    InvalidResearchLineage,
    InvalidStrategyIdentity,
    InvalidCodeCommit,
    InvalidDatasetManifest,
    InvalidSplitPlan,
    InvalidCostModelVersion,
    InvalidAccountingKernelVersion,
    InvalidParameter
}

public sealed class ExperimentManifest
{
    private readonly FrozenDictionary<string, string> _parameters;

    internal ExperimentManifest(
        string experimentId,
        string researchLineageId,
        string strategyName,
        string strategyVersion,
        string codeCommitSha,
        HistoricalDatasetManifest dataset,
        TemporalSplitPlan splitPlan,
        ExperimentStage stage,
        int randomSeed,
        string costModelVersion,
        string accountingKernelVersion,
        IReadOnlyDictionary<string, string> parameters,
        DateTimeOffset createdAt,
        string fingerprintSha256)
    {
        ExperimentId = experimentId;
        ResearchLineageId = researchLineageId;
        StrategyName = strategyName;
        StrategyVersion = strategyVersion;
        CodeCommitSha = codeCommitSha;
        Dataset = dataset;
        SplitPlan = splitPlan;
        Stage = stage;
        RandomSeed = randomSeed;
        CostModelVersion = costModelVersion;
        AccountingKernelVersion = accountingKernelVersion;
        _parameters = parameters.ToFrozenDictionary(StringComparer.Ordinal);
        CreatedAt = createdAt;
        FingerprintSha256 = fingerprintSha256;
    }

    public string ExperimentId { get; }

    public string ResearchLineageId { get; }

    public string StrategyName { get; }

    public string StrategyVersion { get; }

    public string CodeCommitSha { get; }

    public HistoricalDatasetManifest Dataset { get; }

    public TemporalSplitPlan SplitPlan { get; }

    public ExperimentStage Stage { get; }

    public int RandomSeed { get; }

    public string CostModelVersion { get; }

    public string AccountingKernelVersion { get; }

    public IReadOnlyDictionary<string, string> Parameters => _parameters;

    public DateTimeOffset CreatedAt { get; }

    public string FingerprintSha256 { get; }

    public ResearchWindow EvaluationWindow => Stage switch
    {
        ExperimentStage.Train => SplitPlan.Train,
        ExperimentStage.Validation => SplitPlan.Validation,
        ExperimentStage.Test => SplitPlan.Test,
        ExperimentStage.Holdout => SplitPlan.Holdout,
        _ => throw new InvalidOperationException("Unknown experiment stage.")
    };
}

public sealed record ExperimentManifestResult(
    bool IsCreated,
    IReadOnlyList<ExperimentManifestCode> RejectionReasons,
    ExperimentManifest? Manifest);

public enum HoldoutAccessCode
{
    Authorized,
    DuplicateIgnored,
    NotHoldoutExperiment,
    HoldoutAlreadyConsumed,
    InvalidAuthorizationTimestamp,
    InvalidSnapshot
}

public sealed record HoldoutAccessReceipt(
    string ScopeSha256,
    string ResearchLineageId,
    string DatasetContentSha256,
    DateTimeOffset HoldoutStartInclusive,
    DateTimeOffset HoldoutEndExclusive,
    string ExperimentFingerprintSha256,
    DateTimeOffset AuthorizedAt);

public sealed record HoldoutAccessResult(
    HoldoutAccessCode Code,
    HoldoutAccessReceipt? Receipt,
    string Message);
