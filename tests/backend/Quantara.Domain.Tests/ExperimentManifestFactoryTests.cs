using Quantara.Domain.Backtesting;

namespace Quantara.Domain.Tests;

public sealed class ExperimentManifestFactoryTests
{
    [Fact]
    public void FingerprintIgnoresExecutionIdentifierTimeAndParameterInsertionOrder()
    {
        var dataset = ResearchTestData.CreateDataset();
        var split = ResearchTestData.CreateSplit(dataset);
        var firstParameters = new Dictionary<string, string>(StringComparer.Ordinal)
        {
            ["fast"] = "20",
            ["slow"] = "50"
        };
        var secondParameters = new Dictionary<string, string>(StringComparer.Ordinal)
        {
            ["slow"] = "50",
            ["fast"] = "20"
        };

        var first = Create(
            "experiment-a",
            ResearchTestData.CommitSha,
            dataset,
            split,
            ExperimentStage.Validation,
            firstParameters,
            new DateTimeOffset(2026, 7, 20, 8, 0, 0, TimeSpan.Zero));
        var second = Create(
            "experiment-b",
            ResearchTestData.CommitSha.ToUpperInvariant(),
            dataset,
            split,
            ExperimentStage.Validation,
            secondParameters,
            new DateTimeOffset(2026, 7, 21, 8, 0, 0, TimeSpan.Zero));

        Assert.True(first.IsCreated);
        Assert.True(second.IsCreated);
        Assert.NotNull(first.Manifest);
        Assert.NotNull(second.Manifest);
        Assert.Equal(first.Manifest.FingerprintSha256, second.Manifest.FingerprintSha256);
        Assert.Equal(ResearchTestData.CommitSha, second.Manifest.CodeCommitSha);
        Assert.NotEqual(first.Manifest.ExperimentId, second.Manifest.ExperimentId);
        Assert.NotEqual(first.Manifest.CreatedAt, second.Manifest.CreatedAt);
    }

    [Fact]
    public void FingerprintChangesWithStageOrParameterValue()
    {
        var dataset = ResearchTestData.CreateDataset();
        var split = ResearchTestData.CreateSplit(dataset);
        var baseline = ResearchTestData.CreateExperiment(
            dataset,
            split,
            ExperimentStage.Validation);
        var changedParameter = ResearchTestData.CreateExperiment(
            dataset,
            split,
            ExperimentStage.Validation,
            new Dictionary<string, string>(StringComparer.Ordinal)
            {
                ["fast"] = "21",
                ["slow"] = "50"
            },
            experimentId: "experiment-parameter");
        var changedStage = ResearchTestData.CreateExperiment(
            dataset,
            split,
            ExperimentStage.Test,
            experimentId: "experiment-stage");

        Assert.NotEqual(
            baseline.FingerprintSha256,
            changedParameter.FingerprintSha256);
        Assert.NotEqual(baseline.FingerprintSha256, changedStage.FingerprintSha256);
        Assert.NotEqual(baseline.EvaluationWindow, changedStage.EvaluationWindow);
    }

    [Fact]
    public void TakesImmutableParameterSnapshot()
    {
        var dataset = ResearchTestData.CreateDataset();
        var split = ResearchTestData.CreateSplit(dataset);
        var parameters = new Dictionary<string, string>(StringComparer.Ordinal)
        {
            ["fast"] = "20"
        };
        var result = Create(
            "experiment-immutable",
            ResearchTestData.CommitSha,
            dataset,
            split,
            ExperimentStage.Train,
            parameters,
            DateTimeOffset.UtcNow);
        Assert.NotNull(result.Manifest);

        parameters["fast"] = "999";
        parameters["late-added"] = "true";

        Assert.Equal("20", result.Manifest.Parameters["fast"]);
        Assert.False(result.Manifest.Parameters.ContainsKey("late-added"));
    }

    [Fact]
    public void RejectsInvalidCommitParameterAndMismatchedSplit()
    {
        var firstDataset = ResearchTestData.CreateDataset();
        var firstSplit = ResearchTestData.CreateSplit(firstDataset);
        var changedCandles = ResearchTestData.CreateCandles();
        changedCandles[0] = changedCandles[0] with
        {
            Close = changedCandles[0].Close + 1m
        };
        var secondDataset = ResearchTestData.CreateDataset(
            candles: changedCandles,
            datasetId: "second-dataset");
        var invalidParameters = new Dictionary<string, string>(StringComparer.Ordinal)
        {
            [" invalid-key "] = "20"
        };

        var result = Create(
            "experiment-invalid",
            "not-a-commit",
            secondDataset,
            firstSplit,
            ExperimentStage.Train,
            invalidParameters,
            DateTimeOffset.UtcNow);

        Assert.False(result.IsCreated);
        Assert.Null(result.Manifest);
        Assert.Contains(
            ExperimentManifestCode.InvalidCodeCommit,
            result.RejectionReasons);
        Assert.Contains(
            ExperimentManifestCode.InvalidParameter,
            result.RejectionReasons);
        Assert.Contains(
            ExperimentManifestCode.InvalidSplitPlan,
            result.RejectionReasons);
    }

    private static ExperimentManifestResult Create(
        string experimentId,
        string commitSha,
        HistoricalDatasetManifest dataset,
        TemporalSplitPlan split,
        ExperimentStage stage,
        IReadOnlyDictionary<string, string> parameters,
        DateTimeOffset createdAt)
    {
        return ExperimentManifestFactory.Create(
            experimentId,
            "lineage-1",
            "moving-average-cross",
            "1.0.0",
            commitSha,
            dataset,
            split,
            stage,
            42,
            "cost-v1",
            "execution-accounting-v1",
            parameters,
            createdAt);
    }
}
