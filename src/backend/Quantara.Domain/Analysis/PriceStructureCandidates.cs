using Quantara.Domain.Trading;

namespace Quantara.Domain.Analysis;

internal enum PivotKind
{
    Low,
    High
}

internal sealed record PivotCandidate(
    decimal Price,
    PivotKind Kind,
    int CandleIndex,
    DateTimeOffset OccurredAt,
    decimal AverageTrueRange,
    decimal RejectionScore,
    decimal RelativeVolume);

internal sealed class PivotCluster
{
    private decimal _priceSum;
    private decimal _toleranceSum;
    private decimal _rejectionSum;
    private decimal _relativeVolumeSum;

    public PivotCluster(PivotCandidate candidate, decimal tolerance)
    {
        Candidates.Add(candidate);
        _priceSum = candidate.Price;
        _toleranceSum = tolerance;
        _rejectionSum = candidate.RejectionScore;
        _relativeVolumeSum = candidate.RelativeVolume;
        MaximumTolerance = tolerance;
        FirstTouchedAt = candidate.OccurredAt;
        LastTouchedAt = candidate.OccurredAt;
        LastCandleIndex = candidate.CandleIndex;
        HighCount = candidate.Kind == PivotKind.High ? 1 : 0;
        LowCount = candidate.Kind == PivotKind.Low ? 1 : 0;
    }

    public List<PivotCandidate> Candidates { get; } = new();

    public decimal Center => _priceSum / Candidates.Count;

    public decimal AverageTolerance => _toleranceSum / Candidates.Count;

    public decimal AverageRejectionScore => _rejectionSum / Candidates.Count;

    public decimal AverageRelativeVolume => _relativeVolumeSum / Candidates.Count;

    public decimal MaximumTolerance { get; private set; }

    public DateTimeOffset FirstTouchedAt { get; private set; }

    public DateTimeOffset LastTouchedAt { get; private set; }

    public int LastCandleIndex { get; private set; }

    public int HighCount { get; private set; }

    public int LowCount { get; private set; }

    public void Add(PivotCandidate candidate, decimal tolerance)
    {
        Candidates.Add(candidate);
        _priceSum += candidate.Price;
        _toleranceSum += tolerance;
        _rejectionSum += candidate.RejectionScore;
        _relativeVolumeSum += candidate.RelativeVolume;
        MaximumTolerance = Math.Max(MaximumTolerance, tolerance);
        FirstTouchedAt = candidate.OccurredAt < FirstTouchedAt
            ? candidate.OccurredAt
            : FirstTouchedAt;
        LastTouchedAt = candidate.OccurredAt > LastTouchedAt
            ? candidate.OccurredAt
            : LastTouchedAt;
        LastCandleIndex = Math.Max(LastCandleIndex, candidate.CandleIndex);
        HighCount += candidate.Kind == PivotKind.High ? 1 : 0;
        LowCount += candidate.Kind == PivotKind.Low ? 1 : 0;
    }

    public static PivotCandidate Create(
        decimal price,
        PivotKind kind,
        int candleIndex,
        Candle candle,
        decimal averageTrueRange,
        decimal averageVolume)
    {
        var safeAtr = averageTrueRange > 0m
            ? averageTrueRange
            : candle.High - candle.Low;
        var wick = kind == PivotKind.High
            ? candle.High - Math.Max(candle.Open, candle.Close)
            : Math.Min(candle.Open, candle.Close) - candle.Low;
        var rejectionScore = safeAtr > 0m
            ? Math.Clamp(wick / safeAtr, 0m, 3m)
            : 0m;
        var relativeVolume = averageVolume > 0m
            ? Math.Clamp(candle.Volume / averageVolume, 0m, 5m)
            : 0m;

        return new PivotCandidate(
            price,
            kind,
            candleIndex,
            candle.OpenTime,
            safeAtr,
            rejectionScore,
            relativeVolume);
    }
}
