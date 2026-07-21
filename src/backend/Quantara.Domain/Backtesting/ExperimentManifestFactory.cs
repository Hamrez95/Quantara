namespace Quantara.Domain.Backtesting;

public static class ExperimentManifestFactory
{
    public static ExperimentManifestResult Create(
        string experimentId,
        string researchLineageId,
        string strategyName,
        string strategyVersion,
        string codeCommitSha,
        HistoricalDatasetManifest dataset,
        TemporalSplitPlan splitPlan,
        ExperimentStage stage,
        int randomSeed,
        string costModelVersion,
        string accountingKernelVersion,
        IReadOnlyDictionary<string, string> parameters,
        DateTimeOffset createdAt)
    {
        ArgumentNullException.ThrowIfNull(dataset);
        ArgumentNullException.ThrowIfNull(splitPlan);
        ArgumentNullException.ThrowIfNull(parameters);

        var rejections = new HashSet<ExperimentManifestCode>();
        if (!IsCanonicalIdentifier(experimentId, 128))
        {
            rejections.Add(ExperimentManifestCode.InvalidExperimentIdentifier);
        }

        if (!IsCanonicalIdentifier(researchLineageId, 128))
        {
            rejections.Add(ExperimentManifestCode.InvalidResearchLineage);
        }

        if (!IsCanonicalIdentifier(strategyName, 128)
            || !IsCanonicalIdentifier(strategyVersion, 128)
            || !Enum.IsDefined(stage))
        {
            rejections.Add(ExperimentManifestCode.InvalidStrategyIdentity);
        }

        if (string.IsNullOrWhiteSpace(codeCommitSha)
            || !CanonicalResearchHash.IsGitCommitSha(codeCommitSha))
        {
            rejections.Add(ExperimentManifestCode.InvalidCodeCommit);
        }

        if (!ResearchManifestIntegrity.IsDatasetConsistent(dataset))
        {
            rejections.Add(ExperimentManifestCode.InvalidDatasetManifest);
        }

        if (!ResearchManifestIntegrity.IsSplitConsistent(dataset, splitPlan))
        {
            rejections.Add(ExperimentManifestCode.InvalidSplitPlan);
        }

        if (!IsCanonicalIdentifier(costModelVersion, 128))
        {
            rejections.Add(ExperimentManifestCode.InvalidCostModelVersion);
        }

        if (!IsCanonicalIdentifier(accountingKernelVersion, 128))
        {
            rejections.Add(ExperimentManifestCode.InvalidAccountingKernelVersion);
        }

        if (!AreValidParameters(parameters))
        {
            rejections.Add(ExperimentManifestCode.InvalidParameter);
        }

        if (rejections.Count > 0)
        {
            return new ExperimentManifestResult(
                false,
                Array.AsReadOnly(rejections.Order().ToArray()),
                null);
        }

        var normalizedCodeCommitSha = codeCommitSha.ToLowerInvariant();
        var normalizedCreatedAt = createdAt.ToUniversalTime();
        var parameterSnapshot = parameters
            .OrderBy(pair => pair.Key, StringComparer.Ordinal)
            .ToDictionary(
                pair => pair.Key,
                pair => pair.Value,
                StringComparer.Ordinal);
        var fingerprintSha256 = ComputeFingerprint(
            researchLineageId,
            strategyName,
            strategyVersion,
            normalizedCodeCommitSha,
            dataset,
            splitPlan,
            stage,
            randomSeed,
            costModelVersion,
            accountingKernelVersion,
            parameterSnapshot);

        return new ExperimentManifestResult(
            true,
            Array.Empty<ExperimentManifestCode>(),
            new ExperimentManifest(
                experimentId,
                researchLineageId,
                strategyName,
                strategyVersion,
                normalizedCodeCommitSha,
                dataset,
                splitPlan,
                stage,
                randomSeed,
                costModelVersion,
                accountingKernelVersion,
                parameterSnapshot,
                normalizedCreatedAt,
                fingerprintSha256));
    }

    private static bool IsCanonicalIdentifier(string value, int maximumLength)
    {
        return !string.IsNullOrWhiteSpace(value)
            && value.Length <= maximumLength
            && string.Equals(value, value.Trim(), StringComparison.Ordinal);
    }

    private static bool AreValidParameters(IReadOnlyDictionary<string, string> parameters)
    {
        if (parameters.Count > 256)
        {
            return false;
        }

        return parameters.All(pair =>
            IsCanonicalIdentifier(pair.Key, 128)
            && pair.Value is not null
            && pair.Value.Length <= 2048);
    }

    private static string ComputeFingerprint(
        string researchLineageId,
        string strategyName,
        string strategyVersion,
        string codeCommitSha,
        HistoricalDatasetManifest dataset,
        TemporalSplitPlan splitPlan,
        ExperimentStage stage,
        int randomSeed,
        string costModelVersion,
        string accountingKernelVersion,
        IReadOnlyDictionary<string, string> parameters)
    {
        return CanonicalResearchHash.Compute(builder =>
        {
            CanonicalResearchHash.Append(builder, "quantara-experiment-manifest-v1");
            CanonicalResearchHash.Append(builder, researchLineageId);
            CanonicalResearchHash.Append(builder, strategyName);
            CanonicalResearchHash.Append(builder, strategyVersion);
            CanonicalResearchHash.Append(builder, codeCommitSha);
            CanonicalResearchHash.Append(builder, dataset.ManifestSha256);
            CanonicalResearchHash.Append(builder, splitPlan.FingerprintSha256);
            CanonicalResearchHash.Append(builder, stage.ToString());
            CanonicalResearchHash.Append(builder, randomSeed);
            CanonicalResearchHash.Append(builder, costModelVersion);
            CanonicalResearchHash.Append(builder, accountingKernelVersion);
            CanonicalResearchHash.Append(builder, parameters.Count);
            foreach (var parameter in parameters.OrderBy(
                pair => pair.Key,
                StringComparer.Ordinal))
            {
                CanonicalResearchHash.Append(builder, parameter.Key);
                CanonicalResearchHash.Append(builder, parameter.Value);
            }
        });
    }
}

