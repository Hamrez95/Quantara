namespace Quantara.Domain.Backtesting;

internal static class ResearchManifestIntegrity
{
    public static bool IsDatasetConsistent(HistoricalDatasetManifest dataset)
    {
        ArgumentNullException.ThrowIfNull(dataset);

        if (string.IsNullOrWhiteSpace(dataset.DatasetId)
            || string.IsNullOrWhiteSpace(dataset.Symbol.Value)
            || dataset.Timeframe <= TimeSpan.Zero
            || dataset.CandleCount <= 0
            || dataset.FundingPointCount < 0
            || dataset.EndExclusive <= dataset.StartInclusive
            || !CanonicalResearchHash.IsSha256(dataset.ContentSha256)
            || !CanonicalResearchHash.IsSha256(dataset.ManifestSha256)
            || !IsValidProvenance(dataset.Provenance))
        {
            return false;
        }

        long expectedCoverageTicks;
        try
        {
            expectedCoverageTicks = checked(dataset.Timeframe.Ticks * dataset.CandleCount);
        }
        catch (OverflowException)
        {
            return false;
        }

        if ((dataset.EndExclusive - dataset.StartInclusive).Ticks != expectedCoverageTicks)
        {
            return false;
        }

        var expectedManifestSha256 = ComputeDatasetManifestSha256(dataset);
        return string.Equals(
            expectedManifestSha256,
            dataset.ManifestSha256,
            StringComparison.Ordinal);
    }

    public static bool IsSplitConsistent(
        HistoricalDatasetManifest dataset,
        TemporalSplitPlan splitPlan)
    {
        ArgumentNullException.ThrowIfNull(dataset);
        ArgumentNullException.ThrowIfNull(splitPlan);

        if (!IsDatasetConsistent(dataset)
            || !string.Equals(
                dataset.ContentSha256,
                splitPlan.DatasetContentSha256,
                StringComparison.Ordinal)
            || !CanonicalResearchHash.IsSha256(splitPlan.FingerprintSha256))
        {
            return false;
        }

        var rebuilt = TemporalSplitPlanner.Create(
            dataset,
            splitPlan.Train,
            splitPlan.Validation,
            splitPlan.Test,
            splitPlan.Holdout,
            splitPlan.MinimumEmbargo);

        return rebuilt.IsValid
            && rebuilt.Plan is not null
            && string.Equals(
                rebuilt.Plan.FingerprintSha256,
                splitPlan.FingerprintSha256,
                StringComparison.Ordinal);
    }

    private static bool IsValidProvenance(DatasetProvenance provenance)
    {
        return provenance is not null
            && IsValidText(provenance.Provider, 128)
            && IsValidText(provenance.Market, 128)
            && IsValidText(provenance.SourceIdentifier, 512)
            && IsValidText(provenance.SchemaVersion, 128);
    }

    private static bool IsValidText(string value, int maximumLength)
    {
        return !string.IsNullOrWhiteSpace(value) && value.Length <= maximumLength;
    }

    private static string ComputeDatasetManifestSha256(
        HistoricalDatasetManifest dataset)
    {
        return CanonicalResearchHash.Compute(builder =>
        {
            CanonicalResearchHash.Append(builder, "quantara-dataset-manifest-v1");
            CanonicalResearchHash.Append(builder, dataset.Symbol.Value);
            CanonicalResearchHash.Append(builder, dataset.Timeframe);
            CanonicalResearchHash.Append(builder, dataset.StartInclusive);
            CanonicalResearchHash.Append(builder, dataset.EndExclusive);
            CanonicalResearchHash.Append(builder, dataset.CandleCount);
            CanonicalResearchHash.Append(builder, dataset.FundingPointCount);
            CanonicalResearchHash.Append(builder, dataset.ContentSha256);
            CanonicalResearchHash.Append(builder, dataset.Provenance.Provider);
            CanonicalResearchHash.Append(builder, dataset.Provenance.Market);
            CanonicalResearchHash.Append(builder, dataset.Provenance.SourceIdentifier);
            CanonicalResearchHash.Append(builder, dataset.Provenance.SchemaVersion);
            CanonicalResearchHash.Append(builder, dataset.Provenance.RetrievedAt);
        });
    }
}
