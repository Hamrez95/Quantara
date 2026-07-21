using Quantara.Domain.Backtesting;

namespace Quantara.Domain.Tests;

public sealed class TemporalSplitPlannerTests
{
    [Fact]
    public void CreatesChronologicalAlignedSplitWithEmbargo()
    {
        var dataset = ResearchTestData.CreateDataset();

        var result = TemporalSplitPlanner.Create(
            dataset,
            Window(0, 6),
            Window(7, 9),
            Window(10, 12),
            Window(13, 16),
            ResearchTestData.Hour);

        Assert.True(result.IsValid);
        Assert.Empty(result.RejectionReasons);
        Assert.NotNull(result.Plan);
        Assert.Equal(dataset.ContentSha256, result.Plan.DatasetContentSha256);
        Assert.True(result.Plan.Train.Contains(ResearchTestData.Start));
        Assert.False(result.Plan.Train.Contains(ResearchTestData.Start + TimeSpan.FromHours(6)));
        Assert.Equal(64, result.Plan.FingerprintSha256.Length);
    }

    [Fact]
    public void ProducesSameFingerprintForSameInstantsWithDifferentOffsets()
    {
        var dataset = ResearchTestData.CreateDataset();
        var original = ResearchTestData.CreateSplit(dataset);
        var offset = TimeSpan.FromHours(3);

        var rebuilt = TemporalSplitPlanner.Create(
            dataset,
            Offset(original.Train, offset),
            Offset(original.Validation, offset),
            Offset(original.Test, offset),
            Offset(original.Holdout, offset),
            original.MinimumEmbargo);

        Assert.True(rebuilt.IsValid);
        Assert.NotNull(rebuilt.Plan);
        Assert.Equal(original.FingerprintSha256, rebuilt.Plan.FingerprintSha256);
    }

    [Fact]
    public void RejectsOverlapAndInsufficientEmbargo()
    {
        var dataset = ResearchTestData.CreateDataset();

        var overlapping = TemporalSplitPlanner.Create(
            dataset,
            Window(0, 6),
            Window(5, 9),
            Window(10, 12),
            Window(13, 16),
            ResearchTestData.Hour);
        var insufficientEmbargo = TemporalSplitPlanner.Create(
            dataset,
            Window(0, 6),
            Window(6, 9),
            Window(10, 12),
            Window(13, 16),
            ResearchTestData.Hour);

        Assert.False(overlapping.IsValid);
        Assert.Contains(
            SplitValidationCode.NonChronologicalWindows,
            overlapping.RejectionReasons);
        Assert.False(insufficientEmbargo.IsValid);
        Assert.Contains(
            SplitValidationCode.EmbargoViolation,
            insufficientEmbargo.RejectionReasons);
    }

    [Fact]
    public void RejectsMisalignedWindowAndEmbargo()
    {
        var dataset = ResearchTestData.CreateDataset();

        var result = TemporalSplitPlanner.Create(
            dataset,
            Window(0, 6),
            new ResearchWindow(
                ResearchTestData.Start + TimeSpan.FromHours(7.5),
                ResearchTestData.Start + TimeSpan.FromHours(9)),
            Window(10, 12),
            Window(13, 16),
            TimeSpan.FromMinutes(90));

        Assert.False(result.IsValid);
        Assert.Contains(
            SplitValidationCode.InvalidValidationWindow,
            result.RejectionReasons);
        Assert.Contains(SplitValidationCode.InvalidEmbargo, result.RejectionReasons);
    }

    [Fact]
    public void RequiresDatasetBoundaryOwnershipForTrainAndHoldout()
    {
        var dataset = ResearchTestData.CreateDataset();

        var result = TemporalSplitPlanner.Create(
            dataset,
            Window(1, 6),
            Window(7, 9),
            Window(10, 12),
            Window(13, 15),
            ResearchTestData.Hour);

        Assert.False(result.IsValid);
        Assert.Contains(
            SplitValidationCode.TrainMustStartAtDatasetBoundary,
            result.RejectionReasons);
        Assert.Contains(
            SplitValidationCode.HoldoutMustEndAtDatasetBoundary,
            result.RejectionReasons);
    }

    [Fact]
    public void RejectsWindowOutsideDatasetCoverage()
    {
        var dataset = ResearchTestData.CreateDataset();

        var result = TemporalSplitPlanner.Create(
            dataset,
            new ResearchWindow(
                ResearchTestData.Start - ResearchTestData.Hour,
                ResearchTestData.Start + TimeSpan.FromHours(6)),
            Window(7, 9),
            Window(10, 12),
            Window(13, 17),
            ResearchTestData.Hour);

        Assert.False(result.IsValid);
        Assert.Contains(SplitValidationCode.WindowOutsideDataset, result.RejectionReasons);
    }

    private static ResearchWindow Window(int startHour, int endHour)
    {
        return new ResearchWindow(
            ResearchTestData.Start + TimeSpan.FromHours(startHour),
            ResearchTestData.Start + TimeSpan.FromHours(endHour));
    }

    private static ResearchWindow Offset(ResearchWindow window, TimeSpan offset)
    {
        return new ResearchWindow(
            window.StartInclusive.ToOffset(offset),
            window.EndExclusive.ToOffset(offset));
    }
}
