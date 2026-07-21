using Quantara.Domain.Execution;

namespace Quantara.Domain.Backtesting;

public sealed record BacktestMetric(
    double? Value,
    string? UndefinedReason)
{
    public bool IsDefined => Value.HasValue;

    public static BacktestMetric Defined(double value)
    {
        if (!double.IsFinite(value))
        {
            throw new ArgumentOutOfRangeException(
                nameof(value),
                "A defined performance metric must be finite.");
        }

        return new BacktestMetric(value, null);
    }

    public static BacktestMetric Undefined(string reason)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(reason);
        return new BacktestMetric(null, reason);
    }
}

public sealed record BacktestBootstrapInterval(
    double ConfidenceLevel,
    int SampleCount,
    int BlockLength,
    double Lower,
    double Median,
    double Upper);

public sealed record BenchmarkEquityPoint(
    DateTimeOffset Timestamp,
    decimal Value);

public sealed class BenchmarkEquitySeries
{
    private readonly IReadOnlyList<BenchmarkEquityPoint> _points;

    public BenchmarkEquitySeries(
        string name,
        decimal startingValue,
        IReadOnlyList<BenchmarkEquityPoint> points)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(name);
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(startingValue);
        ArgumentNullException.ThrowIfNull(points);

        Name = name.Trim();
        StartingValue = startingValue;
        _points = Array.AsReadOnly(points
            .Select(point => point with
            {
                Timestamp = point.Timestamp.ToUniversalTime()
            })
            .ToArray());
    }

    public string Name { get; }

    public decimal StartingValue { get; }

    public IReadOnlyList<BenchmarkEquityPoint> Points => _points;
}

public sealed record BacktestReportSpecification(
    string Version,
    double PeriodsPerYear,
    double AnnualRiskFreeRate,
    int BootstrapSamples,
    double BootstrapConfidenceLevel,
    int BootstrapBlockLength);

public enum BacktestReportCode
{
    Created,
    RunNotCompleted,
    InvalidRunIdentity,
    InvalidSpecification,
    InvalidEquityCurve,
    InvalidBenchmark,
    BenchmarkTimestampMismatch,
    InvalidFinalState
}

public sealed record BacktestReportBuildResult(
    bool IsCreated,
    IReadOnlyList<BacktestReportCode> RejectionReasons,
    BacktestPerformanceReport? Report);

public sealed record BacktestReturnMetrics(
    double TotalReturn,
    BacktestMetric AnnualizedReturn,
    BacktestMetric AnnualizedVolatility,
    BacktestMetric SharpeRatio,
    BacktestMetric SortinoRatio,
    BacktestMetric CalmarRatio,
    double MaximumDrawdown,
    TimeSpan MaximumDrawdownDuration,
    double WinPeriodRate,
    double LossPeriodRate);

public sealed record BacktestExecutionMetrics(
    decimal TotalFees,
    decimal NetFunding,
    decimal EstimatedSpreadCost,
    decimal EstimatedSlippageCost,
    decimal TradedNotional,
    double Turnover,
    double TimeInMarket,
    double AverageGrossLeverage,
    double MaximumGrossLeverage,
    int FillCount,
    double AverageVolumeParticipation,
    double MaximumVolumeParticipation);

public sealed record BacktestBenchmarkMetrics(
    string BenchmarkName,
    double BenchmarkTotalReturn,
    double ExcessTotalReturn,
    BacktestMetric Beta,
    BacktestMetric Correlation,
    BacktestMetric TrackingError,
    BacktestMetric InformationRatio);

public sealed class BacktestPerformanceReport
{
    internal BacktestPerformanceReport(
        string reportVersion,
        string ledgerSha256,
        string benchmarkSha256,
        string reportSha256,
        string experimentFingerprintSha256,
        string runFingerprintSha256,
        DateTimeOffset startTimestamp,
        DateTimeOffset endTimestamp,
        decimal startingEquity,
        decimal finalEquity,
        BacktestReturnMetrics returns,
        BacktestExecutionMetrics execution,
        BacktestBenchmarkMetrics benchmark,
        BacktestBootstrapInterval totalReturnBootstrap,
        PositionSnapshot finalPosition,
        decimal effectiveTargetSignedQuantity,
        IReadOnlyList<BacktestRunWarning> warnings)
    {
        ReportVersion = reportVersion;
        LedgerSha256 = ledgerSha256;
        BenchmarkSha256 = benchmarkSha256;
        ReportSha256 = reportSha256;
        ExperimentFingerprintSha256 = experimentFingerprintSha256;
        RunFingerprintSha256 = runFingerprintSha256;
        StartTimestamp = startTimestamp;
        EndTimestamp = endTimestamp;
        StartingEquity = startingEquity;
        FinalEquity = finalEquity;
        Returns = returns;
        Execution = execution;
        Benchmark = benchmark;
        TotalReturnBootstrap = totalReturnBootstrap;
        FinalPosition = finalPosition;
        EffectiveTargetSignedQuantity = effectiveTargetSignedQuantity;
        Warnings = Array.AsReadOnly(warnings.ToArray());
    }

    public string ReportVersion { get; }

    public string LedgerSha256 { get; }

    public string BenchmarkSha256 { get; }

    public string ReportSha256 { get; }

    public string ExperimentFingerprintSha256 { get; }

    public string RunFingerprintSha256 { get; }

    public DateTimeOffset StartTimestamp { get; }

    public DateTimeOffset EndTimestamp { get; }

    public decimal StartingEquity { get; }

    public decimal FinalEquity { get; }

    public BacktestReturnMetrics Returns { get; }

    public BacktestExecutionMetrics Execution { get; }

    public BacktestBenchmarkMetrics Benchmark { get; }

    public BacktestBootstrapInterval TotalReturnBootstrap { get; }

    public PositionSnapshot FinalPosition { get; }

    public decimal EffectiveTargetSignedQuantity { get; }

    public IReadOnlyList<BacktestRunWarning> Warnings { get; }
}

