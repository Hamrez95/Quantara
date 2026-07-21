namespace Quantara.Domain.Backtesting;

public sealed class HoldoutAccessLedger
{
    private readonly Dictionary<string, HoldoutAccessReceipt> _receiptsByCohortScope =
        new(StringComparer.Ordinal);
    private readonly Dictionary<string, HoldoutAccessReceipt> _receiptsByContentScope =
        new(StringComparer.Ordinal);

    public IReadOnlyList<HoldoutAccessReceipt> Receipts => _receiptsByCohortScope.Values
        .OrderBy(receipt => receipt.ScopeSha256, StringComparer.Ordinal)
        .ToArray();

    public HoldoutAccessResult Authorize(
        ExperimentManifest manifest,
        DateTimeOffset authorizedAt)
    {
        ArgumentNullException.ThrowIfNull(manifest);

        if (manifest.Stage != ExperimentStage.Holdout)
        {
            return new HoldoutAccessResult(
                HoldoutAccessCode.NotHoldoutExperiment,
                null,
                "Only a final holdout-stage experiment consumes holdout access.");
        }

        var normalizedAuthorizedAt = authorizedAt.ToUniversalTime();
        if (normalizedAuthorizedAt < manifest.CreatedAt)
        {
            return new HoldoutAccessResult(
                HoldoutAccessCode.InvalidAuthorizationTimestamp,
                null,
                "Holdout authorization cannot predate the immutable experiment manifest.");
        }

        var datasetCohortSha256 = ComputeDatasetCohortSha256(manifest.Dataset);
        var cohortScopeSha256 = ComputeCohortScopeSha256(
            manifest.ResearchLineageId,
            datasetCohortSha256,
            manifest.SplitPlan.Holdout);
        var contentScopeSha256 = ComputeContentScopeSha256(
            manifest.ResearchLineageId,
            manifest.Dataset.ContentSha256,
            manifest.SplitPlan.Holdout);

        var existingReceipt = FindExistingReceipt(
            cohortScopeSha256,
            contentScopeSha256);
        if (existingReceipt is not null)
        {
            var isIdenticalReplay = string.Equals(
                existingReceipt.ExperimentFingerprintSha256,
                manifest.FingerprintSha256,
                StringComparison.Ordinal);
            return new HoldoutAccessResult(
                isIdenticalReplay
                    ? HoldoutAccessCode.DuplicateIgnored
                    : HoldoutAccessCode.HoldoutAlreadyConsumed,
                existingReceipt,
                isIdenticalReplay
                    ? "The identical final holdout evaluation was already authorized."
                    : "This research lineage has already consumed the same holdout content or market cohort and cannot retune another experiment against it.");
        }

        var receipt = new HoldoutAccessReceipt(
            cohortScopeSha256,
            datasetCohortSha256,
            manifest.ResearchLineageId,
            manifest.Dataset.ContentSha256,
            manifest.SplitPlan.Holdout.StartInclusive,
            manifest.SplitPlan.Holdout.EndExclusive,
            manifest.FingerprintSha256,
            normalizedAuthorizedAt);
        _receiptsByCohortScope.Add(cohortScopeSha256, receipt);
        _receiptsByContentScope.Add(contentScopeSha256, receipt);

        return new HoldoutAccessResult(
            HoldoutAccessCode.Authorized,
            receipt,
            "The final holdout evaluation was authorized once and locked by both market cohort and exact dataset content.");
    }

    public static HoldoutAccessLedger Rehydrate(
        IEnumerable<HoldoutAccessReceipt> receipts)
    {
        ArgumentNullException.ThrowIfNull(receipts);

        var ledger = new HoldoutAccessLedger();
        foreach (var receipt in receipts)
        {
            ArgumentNullException.ThrowIfNull(receipt);
            var normalizedReceipt = receipt with
            {
                HoldoutStartInclusive = receipt.HoldoutStartInclusive.ToUniversalTime(),
                HoldoutEndExclusive = receipt.HoldoutEndExclusive.ToUniversalTime(),
                AuthorizedAt = receipt.AuthorizedAt.ToUniversalTime()
            };

            if (!IsValidReceipt(normalizedReceipt))
            {
                throw new InvalidOperationException(
                    "The persisted holdout access receipt is invalid or has a mismatched cohort scope hash.");
            }

            var holdout = new ResearchWindow(
                normalizedReceipt.HoldoutStartInclusive,
                normalizedReceipt.HoldoutEndExclusive);
            var contentScopeSha256 = ComputeContentScopeSha256(
                normalizedReceipt.ResearchLineageId,
                normalizedReceipt.DatasetContentSha256,
                holdout);
            if (!ledger._receiptsByCohortScope.TryAdd(
                    normalizedReceipt.ScopeSha256,
                    normalizedReceipt)
                || !ledger._receiptsByContentScope.TryAdd(
                    contentScopeSha256,
                    normalizedReceipt))
            {
                throw new InvalidOperationException(
                    "The persisted holdout access ledger contains a duplicate cohort or content scope.");
            }
        }

        return ledger;
    }

    private HoldoutAccessReceipt? FindExistingReceipt(
        string cohortScopeSha256,
        string contentScopeSha256)
    {
        if (_receiptsByCohortScope.TryGetValue(
            cohortScopeSha256,
            out var cohortReceipt))
        {
            return cohortReceipt;
        }

        return _receiptsByContentScope.TryGetValue(
            contentScopeSha256,
            out var contentReceipt)
            ? contentReceipt
            : null;
    }

    private static bool IsValidReceipt(HoldoutAccessReceipt receipt)
    {
        if (!CanonicalResearchHash.IsSha256(receipt.ScopeSha256)
            || !CanonicalResearchHash.IsSha256(receipt.DatasetCohortSha256)
            || !CanonicalResearchHash.IsSha256(receipt.DatasetContentSha256)
            || !CanonicalResearchHash.IsSha256(receipt.ExperimentFingerprintSha256)
            || string.IsNullOrWhiteSpace(receipt.ResearchLineageId)
            || receipt.ResearchLineageId.Length > 128
            || !string.Equals(
                receipt.ResearchLineageId,
                receipt.ResearchLineageId.Trim(),
                StringComparison.Ordinal)
            || receipt.HoldoutEndExclusive <= receipt.HoldoutStartInclusive
            || receipt.AuthorizedAt == default)
        {
            return false;
        }

        var expectedScopeSha256 = ComputeCohortScopeSha256(
            receipt.ResearchLineageId,
            receipt.DatasetCohortSha256,
            new ResearchWindow(
                receipt.HoldoutStartInclusive,
                receipt.HoldoutEndExclusive));
        return string.Equals(
            expectedScopeSha256,
            receipt.ScopeSha256,
            StringComparison.Ordinal);
    }

    private static string ComputeDatasetCohortSha256(
        HistoricalDatasetManifest dataset)
    {
        return CanonicalResearchHash.Compute(builder =>
        {
            CanonicalResearchHash.Append(builder, "quantara-dataset-cohort-v1");
            CanonicalResearchHash.Append(builder, dataset.Provenance.Market);
            CanonicalResearchHash.Append(builder, dataset.Symbol.Value);
            CanonicalResearchHash.Append(builder, dataset.Timeframe);
        });
    }

    private static string ComputeCohortScopeSha256(
        string researchLineageId,
        string datasetCohortSha256,
        ResearchWindow holdout)
    {
        return CanonicalResearchHash.Compute(builder =>
        {
            CanonicalResearchHash.Append(builder, "quantara-holdout-cohort-scope-v1");
            CanonicalResearchHash.Append(builder, researchLineageId);
            CanonicalResearchHash.Append(builder, datasetCohortSha256);
            CanonicalResearchHash.Append(builder, holdout.StartInclusive);
            CanonicalResearchHash.Append(builder, holdout.EndExclusive);
        });
    }

    private static string ComputeContentScopeSha256(
        string researchLineageId,
        string datasetContentSha256,
        ResearchWindow holdout)
    {
        return CanonicalResearchHash.Compute(builder =>
        {
            CanonicalResearchHash.Append(builder, "quantara-holdout-content-scope-v1");
            CanonicalResearchHash.Append(builder, researchLineageId);
            CanonicalResearchHash.Append(builder, datasetContentSha256);
            CanonicalResearchHash.Append(builder, holdout.StartInclusive);
            CanonicalResearchHash.Append(builder, holdout.EndExclusive);
        });
    }
}
