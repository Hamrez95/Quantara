namespace Quantara.Domain.Backtesting;

public static class BenchmarkEquityHasher
{
    public const string BenchmarkSchemaVersion = "benchmark-equity-v1";

    public static string ComputeSha256(BenchmarkEquitySeries benchmark)
    {
        ArgumentNullException.ThrowIfNull(benchmark);

        return CanonicalResearchHash.Compute(builder =>
        {
            CanonicalResearchHash.Append(builder, BenchmarkSchemaVersion);
            CanonicalResearchHash.Append(builder, benchmark.Name);
            CanonicalResearchHash.Append(builder, benchmark.StartingValue);
            CanonicalResearchHash.Append(builder, benchmark.Points.Count);
            foreach (var point in benchmark.Points)
            {
                CanonicalResearchHash.Append(builder, point.Timestamp);
                CanonicalResearchHash.Append(builder, point.Value);
            }
        });
    }
}
