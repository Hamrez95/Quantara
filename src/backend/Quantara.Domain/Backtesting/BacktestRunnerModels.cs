using System.Collections;
using Quantara.Domain.Execution;
using Quantara.Domain.Trading;

namespace Quantara.Domain.Backtesting;

public sealed record BacktestTargetDecision(
    decimal TargetSignedQuantity,
    string Reason);

public sealed class BacktestStrategyContext
{
    private readonly IReadOnlyList<Candle> _visibleCandles;
    private readonly IReadOnlyDictionary<string, string> _parameters;

    internal BacktestStrategyContext(
        IReadOnlyList<Candle> allCandles,
        PositionSnapshot position,
        decimal equity,
        IReadOnlyDictionary<string, string> parameters,
        IDeterministicRandom random)
        : this(
            allCandles,
            allCandles.Count,
            position,
            equity,
            parameters,
            random)
    {
    }

    internal BacktestStrategyContext(
        IReadOnlyList<Candle> allCandles,
        int visibleCandleCount,
        PositionSnapshot position,
        decimal equity,
        IReadOnlyDictionary<string, string> parameters,
        IDeterministicRandom random)
    {
        ArgumentNullException.ThrowIfNull(allCandles);
        ArgumentOutOfRangeException.ThrowIfLessThan(visibleCandleCount, 1);
        ArgumentOutOfRangeException.ThrowIfGreaterThan(
            visibleCandleCount,
            allCandles.Count);
        ArgumentNullException.ThrowIfNull(parameters);
        ArgumentNullException.ThrowIfNull(random);

        _visibleCandles = new CandlePrefixView(allCandles, visibleCandleCount);
        Position = position;
        Equity = equity;
        _parameters = parameters;
        Random = random;
    }

    public IReadOnlyList<Candle> VisibleCandles => _visibleCandles;

    public Candle CurrentCandle => _visibleCandles[^1];

    public PositionSnapshot Position { get; }

    public decimal Equity { get; }

    public IReadOnlyDictionary<string, string> Parameters => _parameters;

    public IDeterministicRandom Random { get; }

    private sealed class CandlePrefixView(
        IReadOnlyList<Candle> candles,
        int count) : IReadOnlyList<Candle>
    {
        public int Count { get; } = count;

        public Candle this[int index]
        {
            get
            {
                ArgumentOutOfRangeException.ThrowIfNegative(index);
                ArgumentOutOfRangeException.ThrowIfGreaterThanOrEqual(index, Count);
                return candles[index];
            }
        }

        public IEnumerator<Candle> GetEnumerator()
        {
            for (var index = 0; index < Count; index++)
            {
                yield return candles[index];
            }
        }

        IEnumerator IEnumerable.GetEnumerator()
        {
            return GetEnumerator();
        }
    }
}

public interface IBacktestStrategy
{
    string Name { get; }

    string Version { get; }

    BacktestTargetDecision Evaluate(BacktestStrategyContext context);
}

public interface IDeterministicRandom
{
    uint NextUInt32();

    decimal NextUnitDecimal();
}

public sealed class BacktestCostModel
{
    internal BacktestCostModel(
        string version,
        decimal halfSpreadBps,
        decimal baseSlippageBps,
        decimal impactBpsAtMaximumParticipation,
        decimal takerFeeBps,
        decimal maximumVolumeParticipation,
        int latencyBars,
        string fingerprintSha256)
    {
        Version = version;
        HalfSpreadBps = halfSpreadBps;
        BaseSlippageBps = baseSlippageBps;
        ImpactBpsAtMaximumParticipation = impactBpsAtMaximumParticipation;
        TakerFeeBps = takerFeeBps;
        MaximumVolumeParticipation = maximumVolumeParticipation;
        LatencyBars = latencyBars;
        FingerprintSha256 = fingerprintSha256;
    }

    public string Version { get; }

    public decimal HalfSpreadBps { get; }

    public decimal BaseSlippageBps { get; }

    public decimal ImpactBpsAtMaximumParticipation { get; }

    public decimal TakerFeeBps { get; }

    public decimal MaximumVolumeParticipation { get; }

    public int LatencyBars { get; }

    public string FingerprintSha256 { get; }
}

public sealed record BacktestExecutionRules(
    decimal StartingEquity,
    decimal ContractMultiplier,
    decimal QuantityStep,
    decimal MinimumOrderQuantity,
    decimal MaximumAbsoluteTargetQuantity,
    decimal MaximumGrossLeverage);

public enum BacktestRunCode
{
    Completed,
    InvalidExperimentStage,
    InvalidDataset,
    DatasetDoesNotMatchManifest,
    InvalidCostModel,
    CostModelVersionMismatch,
    AccountingKernelVersionMismatch,
    StrategyIdentityMismatch,
    InvalidExecutionRules,
    InsufficientEvaluationCandles,
    ExecutionRejected,
    Insolvent
}

public enum BacktestDecisionCode
{
    Scheduled,
    ReplacedPendingTarget,
    NoChange,
    RejectedInvalidReason,
    RejectedTargetLimit,
    RejectedLeverage,
    NormalizedToFlat
}

public sealed record BacktestDecisionRecord(
    long Sequence,
    DateTimeOffset DecidedAt,
    DateTimeOffset EarliestExecutionAt,
    decimal RequestedTargetSignedQuantity,
    decimal NormalizedTargetSignedQuantity,
    BacktestDecisionCode Code,
    string Reason);

public sealed record BacktestFillRecord(
    long Sequence,
    DateTimeOffset OccurredAt,
    decimal ReferencePrice,
    decimal ExecutionPrice,
    decimal Quantity,
    OrderSide Side,
    decimal SpreadBps,
    decimal SlippageBps,
    decimal Fee,
    decimal VolumeParticipation,
    decimal TargetSignedQuantity,
    string FillId);

public sealed record BacktestFundingRecord(
    long Sequence,
    DateTimeOffset OccurredAt,
    decimal Rate,
    decimal ReferencePrice,
    decimal SignedQuantity,
    decimal NetAmount,
    string SettlementId);

public sealed record BacktestEquityPoint(
    DateTimeOffset Timestamp,
    decimal MarkPrice,
    decimal Equity,
    decimal NetRealizedPnl,
    decimal UnrealizedPnl,
    decimal GrossExposure,
    decimal GrossLeverage);

public sealed record BacktestRunWarning(
    string Code,
    string Message);

public sealed class BacktestRunResult
{
    internal BacktestRunResult(
        BacktestRunCode code,
        string message,
        string? runFingerprintSha256,
        IReadOnlyList<BacktestDecisionRecord> decisions,
        IReadOnlyList<BacktestFillRecord> fills,
        IReadOnlyList<BacktestFundingRecord> funding,
        IReadOnlyList<BacktestEquityPoint> equityCurve,
        IReadOnlyList<BacktestRunWarning> warnings,
        PositionSnapshot? finalPosition,
        decimal finalEquity,
        decimal effectiveTargetSignedQuantity)
    {
        Code = code;
        Message = message;
        RunFingerprintSha256 = runFingerprintSha256;
        Decisions = Array.AsReadOnly(decisions.ToArray());
        Fills = Array.AsReadOnly(fills.ToArray());
        Funding = Array.AsReadOnly(funding.ToArray());
        EquityCurve = Array.AsReadOnly(equityCurve.ToArray());
        Warnings = Array.AsReadOnly(warnings.ToArray());
        FinalPosition = finalPosition;
        FinalEquity = finalEquity;
        EffectiveTargetSignedQuantity = effectiveTargetSignedQuantity;
    }

    public BacktestRunCode Code { get; }

    public string Message { get; }

    public string? RunFingerprintSha256 { get; }

    public IReadOnlyList<BacktestDecisionRecord> Decisions { get; }

    public IReadOnlyList<BacktestFillRecord> Fills { get; }

    public IReadOnlyList<BacktestFundingRecord> Funding { get; }

    public IReadOnlyList<BacktestEquityPoint> EquityCurve { get; }

    public IReadOnlyList<BacktestRunWarning> Warnings { get; }

    public PositionSnapshot? FinalPosition { get; }

    public decimal FinalEquity { get; }

    public decimal EffectiveTargetSignedQuantity { get; }

    public bool IsCompleted => Code == BacktestRunCode.Completed;
}
