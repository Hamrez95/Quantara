namespace Quantara.Domain.Backtesting;

public sealed class HoldoutAccessLedger
{
    private readonly Dictionary<string, HoldoutAccessReceipt> _receipts =
        new(StringComparer.Ordinal);

    public IReadOnlyList<HoldoutAccessReceipt> Receipts => _receipts.Values
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

        var scopeSha256 = ComputeScopeSha256(
            manifest.ResearchLineageId,
            manifest.Dataset.ContentSha256,
            manifest.SplitPlan.Holdout);

        if (_receipts.TryGetValue(scopeSha256, out var existingReceipt))
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
                    : "This research lineage has already consumed the same holdout data and cannot tune another experiment against it.");
        }

        var receipt = new HoldoutAccessReceipt(
            scopeSha256,
            manifest.ResearchLineageId,
            manifest.Dataset.ContentSha256,
            manifest.SplitPlan.Holdout.StartInclusive,
            manifest.SplitPlan.Holdout.EndExclusive,
            manifest.FingerprintSha256,
            normalizedAuthorizedAt);
        _receipts.Add(scopeSha256, receipt);

        return new HoldoutAccessResult(
            HoldoutAccessCode.Authorized,
            receipt,
            "The final holdout evaluation was authorized exactly once for this lineage and dataset content.");
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
                    "The persisted holdout access receipt is invalid or has a mismatched scope hash.");
            }

            if (!ledger._receipts.TryAdd(
                normalizedReceipt.ScopeSha256,
                normalizedReceipt))
            {
                throw new InvalidOperationException(
                    "The persisted holdout access ledger contains a duplicate scope.");
            }
        }

        return ledger;
    }

    private static bool IsValidReceipt(HoldoutAccessReceipt receipt)
    {
        if (!CanonicalResearchHash.IsSha256(receipt.ScopeSha256)
            || !CanonicalResearchHash.IsSha256(receipt.DatasetContentSha256)
            || !CanonicalResearchHash.IsSha256(receipt.ExperimentFingerprintSha256)
            || string.IsNullOrWhiteSpace(receipt.ResearchLineageId)
            || receipt.HoldoutEndExclusive <= receipt.HoldoutStartInclusive)
        {
            return false;
        }

        var expectedScopeSha256 = ComputeScopeSha256(
            receipt.ResearchLineageId,
            receipt.DatasetContentSha256,
            new ResearchWindow(
                receipt.HoldoutStartInclusive,
                receipt.HoldoutEndExclusive));
        return string.Equals(
            expectedScopeSha256,
            receipt.ScopeSha256,
            StringComparison.Ordinal);
    }

    private static string ComputeScopeSha256(
        string researchLineageId,
        string datasetContentSha256,
        ResearchWindow holdout)
    {
        return CanonicalResearchHash.Compute(builder =>
        {
            CanonicalResearchHash.Append(builder, "quantara-holdout-scope-v1");
            CanonicalResearchHash.Append(builder, researchLineageId);
            CanonicalResearchHash.Append(builder, datasetContentSha256);
            CanonicalResearchHash.Append(builder, holdout.StartInclusive);
            CanonicalResearchHash.Append(builder, holdout.EndExclusive);
        });
    }
}
