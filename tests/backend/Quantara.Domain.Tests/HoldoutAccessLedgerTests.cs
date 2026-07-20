using Quantara.Domain.Backtesting;

namespace Quantara.Domain.Tests;

public sealed class HoldoutAccessLedgerTests
{
    [Fact]
    public void AuthorizesOnceAndIgnoresIdenticalReplay()
    {
        var manifest = ResearchTestData.CreateExperiment(stage: ExperimentStage.Holdout);
        var ledger = new HoldoutAccessLedger();
        var authorizationTime = manifest.CreatedAt + TimeSpan.FromMinutes(1);

        var first = ledger.Authorize(manifest, authorizationTime);
        var duplicate = ledger.Authorize(manifest, authorizationTime + TimeSpan.FromMinutes(1));

        Assert.Equal(HoldoutAccessCode.Authorized, first.Code);
        Assert.Equal(HoldoutAccessCode.DuplicateIgnored, duplicate.Code);
        Assert.NotNull(first.Receipt);
        Assert.Equal(first.Receipt, duplicate.Receipt);
        Assert.Single(ledger.Receipts);
    }

    [Fact]
    public void BlocksRetuningParametersAgainstConsumedHoldout()
    {
        var dataset = ResearchTestData.CreateDataset();
        var split = ResearchTestData.CreateSplit(dataset);
        var baseline = ResearchTestData.CreateExperiment(
            dataset,
            split,
            ExperimentStage.Holdout,
            experimentId: "holdout-baseline");
        var retuned = ResearchTestData.CreateExperiment(
            dataset,
            split,
            ExperimentStage.Holdout,
            new Dictionary<string, string>(StringComparer.Ordinal)
            {
                ["fast"] = "21",
                ["slow"] = "50"
            },
            experimentId: "holdout-retuned",
            strategyVersion: "1.0.1");
        var ledger = new HoldoutAccessLedger();
        Assert.Equal(
            HoldoutAccessCode.Authorized,
            ledger.Authorize(baseline, baseline.CreatedAt).Code);

        var blocked = ledger.Authorize(retuned, retuned.CreatedAt);

        Assert.Equal(HoldoutAccessCode.HoldoutAlreadyConsumed, blocked.Code);
        Assert.Single(ledger.Receipts);
        Assert.Equal(
            baseline.FingerprintSha256,
            blocked.Receipt?.ExperimentFingerprintSha256);
    }

    [Fact]
    public void DatasetAliasOrProvenanceChangeCannotResetSameContentHoldout()
    {
        var firstDataset = ResearchTestData.CreateDataset(
            provenance: ResearchTestData.CreateProvenance("fixture://source-a"),
            datasetId: "dataset-a");
        var secondDataset = ResearchTestData.CreateDataset(
            provenance: ResearchTestData.CreateProvenance("fixture://source-b"),
            datasetId: "dataset-b");
        Assert.Equal(firstDataset.ContentSha256, secondDataset.ContentSha256);
        Assert.NotEqual(firstDataset.ManifestSha256, secondDataset.ManifestSha256);
        var first = ResearchTestData.CreateExperiment(
            firstDataset,
            ResearchTestData.CreateSplit(firstDataset),
            ExperimentStage.Holdout,
            experimentId: "first-holdout");
        var second = ResearchTestData.CreateExperiment(
            secondDataset,
            ResearchTestData.CreateSplit(secondDataset),
            ExperimentStage.Holdout,
            experimentId: "second-holdout");
        Assert.NotEqual(first.FingerprintSha256, second.FingerprintSha256);
        var ledger = new HoldoutAccessLedger();
        Assert.Equal(HoldoutAccessCode.Authorized, ledger.Authorize(first, first.CreatedAt).Code);

        var blocked = ledger.Authorize(second, second.CreatedAt);

        Assert.Equal(HoldoutAccessCode.HoldoutAlreadyConsumed, blocked.Code);
        Assert.Single(ledger.Receipts);
    }

    [Fact]
    public void ChangedContentCannotResetSameMarketCohortHoldout()
    {
        var firstDataset = ResearchTestData.CreateDataset(datasetId: "dataset-a");
        var changedCandles = ResearchTestData.CreateCandles();
        changedCandles[0] = changedCandles[0] with
        {
            Close = changedCandles[0].Close + 1m
        };
        var secondDataset = ResearchTestData.CreateDataset(
            candles: changedCandles,
            datasetId: "dataset-b");
        Assert.NotEqual(firstDataset.ContentSha256, secondDataset.ContentSha256);
        var first = ResearchTestData.CreateExperiment(
            firstDataset,
            ResearchTestData.CreateSplit(firstDataset),
            ExperimentStage.Holdout,
            experimentId: "first-content");
        var second = ResearchTestData.CreateExperiment(
            secondDataset,
            ResearchTestData.CreateSplit(secondDataset),
            ExperimentStage.Holdout,
            experimentId: "second-content");
        var ledger = new HoldoutAccessLedger();
        Assert.Equal(HoldoutAccessCode.Authorized, ledger.Authorize(first, first.CreatedAt).Code);

        var blocked = ledger.Authorize(second, second.CreatedAt);

        Assert.Equal(HoldoutAccessCode.HoldoutAlreadyConsumed, blocked.Code);
        Assert.Single(ledger.Receipts);
    }

    [Fact]
    public void AllowsDistinctContentAndMarketCohortForSameResearchLineage()
    {
        var firstDataset = ResearchTestData.CreateDataset(datasetId: "dataset-a");
        var changedCandles = ResearchTestData.CreateCandles();
        changedCandles[0] = changedCandles[0] with
        {
            Close = changedCandles[0].Close + 1m
        };
        var secondDataset = ResearchTestData.CreateDataset(
            candles: changedCandles,
            provenance: ResearchTestData.CreateProvenance(
                "fixture://independent-source",
                provider: "independent-provider"),
            datasetId: "dataset-b");
        var first = ResearchTestData.CreateExperiment(
            firstDataset,
            ResearchTestData.CreateSplit(firstDataset),
            ExperimentStage.Holdout,
            experimentId: "first-cohort");
        var second = ResearchTestData.CreateExperiment(
            secondDataset,
            ResearchTestData.CreateSplit(secondDataset),
            ExperimentStage.Holdout,
            experimentId: "second-cohort");
        var ledger = new HoldoutAccessLedger();

        var firstResult = ledger.Authorize(first, first.CreatedAt);
        var secondResult = ledger.Authorize(second, second.CreatedAt);

        Assert.Equal(HoldoutAccessCode.Authorized, firstResult.Code);
        Assert.Equal(HoldoutAccessCode.Authorized, secondResult.Code);
        Assert.Equal(2, ledger.Receipts.Count);
    }

    [Fact]
    public void NonHoldoutStageAndPredatedAuthorizationDoNotConsumeAccess()
    {
        var validation = ResearchTestData.CreateExperiment(stage: ExperimentStage.Validation);
        var holdout = ResearchTestData.CreateExperiment(
            stage: ExperimentStage.Holdout,
            experimentId: "holdout-time-check");
        var ledger = new HoldoutAccessLedger();

        var notHoldout = ledger.Authorize(validation, validation.CreatedAt);
        var predatesManifest = ledger.Authorize(
            holdout,
            holdout.CreatedAt - TimeSpan.FromTicks(1));

        Assert.Equal(HoldoutAccessCode.NotHoldoutExperiment, notHoldout.Code);
        Assert.Equal(
            HoldoutAccessCode.InvalidAuthorizationTimestamp,
            predatesManifest.Code);
        Assert.Empty(ledger.Receipts);
    }

    [Fact]
    public void RehydratesValidReceiptsAndRejectsTamperingOrDuplicateScope()
    {
        var manifest = ResearchTestData.CreateExperiment(stage: ExperimentStage.Holdout);
        var source = new HoldoutAccessLedger();
        var authorized = source.Authorize(manifest, manifest.CreatedAt);
        Assert.NotNull(authorized.Receipt);

        var rehydrated = HoldoutAccessLedger.Rehydrate(source.Receipts);
        var replay = rehydrated.Authorize(manifest, manifest.CreatedAt);
        var tampered = authorized.Receipt with
        {
            ResearchLineageId = "tampered-lineage"
        };

        Assert.Equal(HoldoutAccessCode.DuplicateIgnored, replay.Code);
        Assert.Throws<InvalidOperationException>(
            () => HoldoutAccessLedger.Rehydrate([tampered]));
        Assert.Throws<InvalidOperationException>(
            () => HoldoutAccessLedger.Rehydrate(
            [
                authorized.Receipt,
                authorized.Receipt
            ]));
    }
}
