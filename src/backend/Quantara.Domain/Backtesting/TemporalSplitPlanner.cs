namespace Quantara.Domain.Backtesting;

public static class TemporalSplitPlanner
{
    public static SplitValidationResult Create(
        HistoricalDatasetManifest dataset,
        ResearchWindow train,
        ResearchWindow validation,
        ResearchWindow test,
        ResearchWindow holdout,
        TimeSpan minimumEmbargo)
    {
        ArgumentNullException.ThrowIfNull(dataset);
        ArgumentNullException.ThrowIfNull(train);
        ArgumentNullException.ThrowIfNull(validation);
        ArgumentNullException.ThrowIfNull(test);
        ArgumentNullException.ThrowIfNull(holdout);

        var rejections = new HashSet<SplitValidationCode>();
        var normalizedTrain = Normalize(train);
        var normalizedValidation = Normalize(validation);
        var normalizedTest = Normalize(test);
        var normalizedHoldout = Normalize(holdout);

        ValidateDataset(dataset, rejections);
        ValidateEmbargo(dataset, minimumEmbargo, rejections);
        ValidateWindow(
            dataset,
            normalizedTrain,
            SplitValidationCode.InvalidTrainWindow,
            rejections);
        ValidateWindow(
            dataset,
            normalizedValidation,
            SplitValidationCode.InvalidValidationWindow,
            rejections);
        ValidateWindow(
            dataset,
            normalizedTest,
            SplitValidationCode.InvalidTestWindow,
            rejections);
        ValidateWindow(
            dataset,
            normalizedHoldout,
            SplitValidationCode.InvalidHoldoutWindow,
            rejections);

        if (normalizedTrain.StartInclusive != dataset.StartInclusive)
        {
            rejections.Add(SplitValidationCode.TrainMustStartAtDatasetBoundary);
        }

        if (normalizedHoldout.EndExclusive != dataset.EndExclusive)
        {
            rejections.Add(SplitValidationCode.HoldoutMustEndAtDatasetBoundary);
        }

        var chronological = normalizedTrain.EndExclusive <= normalizedValidation.StartInclusive
            && normalizedValidation.EndExclusive <= normalizedTest.StartInclusive
            && normalizedTest.EndExclusive <= normalizedHoldout.StartInclusive;
        if (!chronological)
        {
            rejections.Add(SplitValidationCode.NonChronologicalWindows);
        }
        else if (minimumEmbargo >= TimeSpan.Zero
            && (!HasEmbargo(normalizedTrain, normalizedValidation, minimumEmbargo)
                || !HasEmbargo(normalizedValidation, normalizedTest, minimumEmbargo)
                || !HasEmbargo(normalizedTest, normalizedHoldout, minimumEmbargo)))
        {
            rejections.Add(SplitValidationCode.EmbargoViolation);
        }

        if (rejections.Count > 0)
        {
            return new SplitValidationResult(
                false,
                Array.AsReadOnly(rejections.Order().ToArray()),
                null);
        }

        var fingerprintSha256 = ComputeFingerprint(
            dataset.ContentSha256,
            normalizedTrain,
            normalizedValidation,
            normalizedTest,
            normalizedHoldout,
            minimumEmbargo);

        return new SplitValidationResult(
            true,
            Array.Empty<SplitValidationCode>(),
            new TemporalSplitPlan(
                dataset.ContentSha256,
                normalizedTrain,
                normalizedValidation,
                normalizedTest,
                normalizedHoldout,
                minimumEmbargo,
                fingerprintSha256));
    }

    private static void ValidateDataset(
        HistoricalDatasetManifest dataset,
        HashSet<SplitValidationCode> rejections)
    {
        if (!ResearchManifestIntegrity.IsDatasetConsistent(dataset))
        {
            rejections.Add(SplitValidationCode.InvalidDatasetManifest);
        }
    }

    private static void ValidateEmbargo(
        HistoricalDatasetManifest dataset,
        TimeSpan minimumEmbargo,
        HashSet<SplitValidationCode> rejections)
    {
        if (minimumEmbargo < TimeSpan.Zero
            || dataset.Timeframe <= TimeSpan.Zero
            || minimumEmbargo.Ticks % dataset.Timeframe.Ticks != 0)
        {
            rejections.Add(SplitValidationCode.InvalidEmbargo);
        }
    }

    private static void ValidateWindow(
        HistoricalDatasetManifest dataset,
        ResearchWindow window,
        SplitValidationCode invalidWindowCode,
        HashSet<SplitValidationCode> rejections)
    {
        if (window.EndExclusive <= window.StartInclusive
            || !IsAligned(dataset, window.StartInclusive)
            || !IsAligned(dataset, window.EndExclusive))
        {
            rejections.Add(invalidWindowCode);
        }

        if (window.StartInclusive < dataset.StartInclusive
            || window.EndExclusive > dataset.EndExclusive)
        {
            rejections.Add(SplitValidationCode.WindowOutsideDataset);
        }
    }

    private static bool IsAligned(
        HistoricalDatasetManifest dataset,
        DateTimeOffset timestamp)
    {
        if (dataset.Timeframe <= TimeSpan.Zero)
        {
            return false;
        }

        var deltaTicks = timestamp.ToUniversalTime().Ticks
            - dataset.StartInclusive.ToUniversalTime().Ticks;
        return deltaTicks % dataset.Timeframe.Ticks == 0;
    }

    private static bool HasEmbargo(
        ResearchWindow earlier,
        ResearchWindow later,
        TimeSpan minimumEmbargo)
    {
        return later.StartInclusive - earlier.EndExclusive >= minimumEmbargo;
    }

    private static ResearchWindow Normalize(ResearchWindow window)
    {
        return new ResearchWindow(
            window.StartInclusive.ToUniversalTime(),
            window.EndExclusive.ToUniversalTime());
    }

    private static string ComputeFingerprint(
        string datasetContentSha256,
        ResearchWindow train,
        ResearchWindow validation,
        ResearchWindow test,
        ResearchWindow holdout,
        TimeSpan minimumEmbargo)
    {
        return CanonicalResearchHash.Compute(builder =>
        {
            CanonicalResearchHash.Append(builder, "quantara-temporal-split-v1");
            CanonicalResearchHash.Append(builder, datasetContentSha256);
            AppendWindow(builder, train);
            AppendWindow(builder, validation);
            AppendWindow(builder, test);
            AppendWindow(builder, holdout);
            CanonicalResearchHash.Append(builder, minimumEmbargo);
        });
    }

    private static void AppendWindow(
        System.Text.StringBuilder builder,
        ResearchWindow window)
    {
        CanonicalResearchHash.Append(builder, window.StartInclusive);
        CanonicalResearchHash.Append(builder, window.EndExclusive);
    }
}
