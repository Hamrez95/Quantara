using System.Globalization;
using Quantara.Domain.Execution;
using Quantara.Domain.Trading;

namespace Quantara.Domain.Backtesting;

public static class DeterministicBacktestRunner
{
    public const string RunnerVersion = "deterministic-runner-v1";
    public const string AccountingKernelVersion = "execution-accounting-v1";

    public static BacktestRunResult Run(
        ExperimentManifest manifest,
        BacktestCostModel costModel,
        BacktestExecutionRules rules,
        IReadOnlyList<Candle> candles,
        IReadOnlyList<FundingRatePoint> fundingPoints,
        IBacktestStrategy strategy)
    {
        ArgumentNullException.ThrowIfNull(manifest);
        ArgumentNullException.ThrowIfNull(costModel);
        ArgumentNullException.ThrowIfNull(rules);
        ArgumentNullException.ThrowIfNull(candles);
        ArgumentNullException.ThrowIfNull(fundingPoints);
        ArgumentNullException.ThrowIfNull(strategy);

        var validation = ValidateInputs(
            manifest,
            costModel,
            rules,
            candles,
            fundingPoints,
            strategy);
        if (validation is not null)
        {
            return validation;
        }

        var normalizedCandles = candles
            .Select(candle => candle with
            {
                OpenTime = candle.OpenTime.ToUniversalTime()
            })
            .ToArray();
        var normalizedFunding = fundingPoints
            .Select(point => point with
            {
                OccurredAt = point.OccurredAt.ToUniversalTime()
            })
            .ToArray();
        var evaluationWindow = manifest.EvaluationWindow;
        var evaluationStartIndex = FindCandleIndex(
            normalizedCandles,
            evaluationWindow.StartInclusive);
        var evaluationEndIndex = FindCandleIndex(
            normalizedCandles,
            evaluationWindow.EndExclusive);
        if (evaluationStartIndex < 0
            || evaluationEndIndex < 0
            || evaluationEndIndex - evaluationStartIndex < 2)
        {
            return Rejected(
                BacktestRunCode.InsufficientEvaluationCandles,
                "The evaluation window requires at least two aligned candles so close-time decisions can execute on a later bar.");
        }

        var position = new PositionAccountingAggregate(
            manifest.Dataset.Symbol,
            rules.ContractMultiplier);
        var random = new StableDeterministicRandom(manifest.RandomSeed);
        var visibleCandles = new List<Candle>(evaluationEndIndex);
        visibleCandles.AddRange(normalizedCandles.Take(evaluationStartIndex));
        var decisions = new List<BacktestDecisionRecord>();
        var fills = new List<BacktestFillRecord>();
        var funding = new List<BacktestFundingRecord>();
        var equityCurve = new List<BacktestEquityPoint>();
        var warnings = new List<BacktestRunWarning>();
        PendingTarget? pendingTarget = null;
        long decisionSequence = 0;
        long fillSequence = 0;
        long fundingSequence = 0;
        var fundingIndex = FindFirstFundingIndex(
            normalizedFunding,
            evaluationWindow.StartInclusive);
        var latestEquity = rules.StartingEquity;

        for (var candleIndex = evaluationStartIndex;
             candleIndex < evaluationEndIndex;
             candleIndex++)
        {
            var candle = normalizedCandles[candleIndex];
            if (pendingTarget is not null && pendingTarget.DueCandleIndex <= candleIndex)
            {
                var execution = ExecutePendingTarget(
                    manifest,
                    costModel,
                    rules,
                    candle,
                    candleIndex,
                    position,
                    pendingTarget,
                    fillSequence);
                if (execution.Code != BacktestRunCode.Completed)
                {
                    return FailedWithState(
                        execution.Code,
                        execution.Message,
                        manifest,
                        costModel,
                        rules,
                        decisions,
                        fills,
                        funding,
                        equityCurve,
                        warnings,
                        position,
                        latestEquity,
                        pendingTarget.TargetSignedQuantity);
                }

                if (execution.Fill is not null)
                {
                    fills.Add(execution.Fill);
                    fillSequence++;
                }

                pendingTarget = execution.RemainingTarget;
            }

            var fundingBoundary = candle.OpenTime + candle.Timeframe;
            while (fundingIndex < normalizedFunding.Length
                && normalizedFunding[fundingIndex].OccurredAt < fundingBoundary)
            {
                var point = normalizedFunding[fundingIndex];
                fundingIndex++;
                if (point.OccurredAt < candle.OpenTime
                    || position.Snapshot.SignedQuantity == 0m)
                {
                    continue;
                }

                var signedQuantity = position.Snapshot.SignedQuantity;
                var netAmount = -signedQuantity
                    * candle.Open
                    * rules.ContractMultiplier
                    * point.Rate;
                var settlementId = CreateDeterministicId(
                    "funding",
                    manifest.FingerprintSha256,
                    fundingSequence,
                    candleIndex);
                var application = position.ApplyFunding(
                    new FundingSettlement(
                        settlementId,
                        manifest.Dataset.Symbol,
                        netAmount,
                        point.OccurredAt));
                if (application.Code != ExecutionApplicationCode.Applied)
                {
                    return FailedWithState(
                        BacktestRunCode.ExecutionRejected,
                        $"Funding settlement was rejected by the accounting kernel with {application.Code}.",
                        manifest,
                        costModel,
                        rules,
                        decisions,
                        fills,
                        funding,
                        equityCurve,
                        warnings,
                        position,
                        latestEquity,
                        pendingTarget?.TargetSignedQuantity ?? position.Snapshot.SignedQuantity);
                }

                funding.Add(new BacktestFundingRecord(
                    fundingSequence,
                    point.OccurredAt,
                    point.Rate,
                    candle.Open,
                    signedQuantity,
                    netAmount,
                    settlementId));
                fundingSequence++;
            }

            var valuation = position.ValueAt(candle.Close);
            latestEquity = rules.StartingEquity + valuation.NetPnl;
            var grossExposure = Math.Abs(valuation.Position.SignedQuantity)
                * candle.Close
                * rules.ContractMultiplier;
            var leverage = latestEquity > 0m
                ? grossExposure / latestEquity
                : decimal.MaxValue;
            equityCurve.Add(new BacktestEquityPoint(
                candle.OpenTime + candle.Timeframe,
                candle.Close,
                latestEquity,
                valuation.Position.NetRealizedPnl,
                valuation.UnrealizedPnl,
                grossExposure,
                leverage));

            if (latestEquity <= 0m)
            {
                warnings.Add(new BacktestRunWarning(
                    "insolvent",
                    "Equity reached zero or below; the run stopped before another strategy decision."));
                return FailedWithState(
                    BacktestRunCode.Insolvent,
                    "The backtest account became insolvent.",
                    manifest,
                    costModel,
                    rules,
                    decisions,
                    fills,
                    funding,
                    equityCurve,
                    warnings,
                    position,
                    latestEquity,
                    pendingTarget?.TargetSignedQuantity ?? position.Snapshot.SignedQuantity);
            }

            visibleCandles.Add(candle);
            var context = new BacktestStrategyContext(
                visibleCandles,
                position.Snapshot,
                latestEquity,
                manifest.Parameters,
                random);
            var decision = strategy.Evaluate(context);
            var decisionResult = EvaluateDecision(
                decision,
                rules,
                costModel,
                candle,
                candleIndex,
                evaluationEndIndex,
                position.Snapshot.SignedQuantity,
                latestEquity,
                pendingTarget,
                decisionSequence);
            decisions.Add(decisionResult.Record);
            decisionSequence++;
            pendingTarget = decisionResult.PendingTarget;
        }

        if (fills.Count == 0)
        {
            warnings.Add(new BacktestRunWarning(
                "no-fills",
                "The strategy produced no executable fills in the evaluation window."));
        }

        if (pendingTarget is not null)
        {
            warnings.Add(new BacktestRunWarning(
                "pending-target-at-end",
                "The evaluation window ended before the final target could be fully executed."));
        }

        return new BacktestRunResult(
            BacktestRunCode.Completed,
            "The deterministic cost-aware backtest completed.",
            ComputeRunFingerprint(manifest, costModel, rules),
            decisions,
            fills,
            funding,
            equityCurve,
            warnings,
            position.Snapshot,
            latestEquity,
            pendingTarget?.TargetSignedQuantity ?? position.Snapshot.SignedQuantity);
    }

    private static BacktestRunResult? ValidateInputs(
        ExperimentManifest manifest,
        BacktestCostModel costModel,
        BacktestExecutionRules rules,
        IReadOnlyList<Candle> candles,
        IReadOnlyList<FundingRatePoint> fundingPoints,
        IBacktestStrategy strategy)
    {
        if (manifest.Stage == ExperimentStage.Holdout)
        {
            return Rejected(
                BacktestRunCode.InvalidExperimentStage,
                "The generic runner cannot execute final holdout experiments; holdout authorization and immutable result publication require a separate orchestration path.");
        }

        if (!ResearchManifestIntegrity.IsDatasetConsistent(manifest.Dataset)
            || !ResearchManifestIntegrity.IsSplitConsistent(
                manifest.Dataset,
                manifest.SplitPlan))
        {
            return Rejected(
                BacktestRunCode.InvalidDataset,
                "The experiment references an invalid dataset or temporal split manifest.");
        }

        var rebuiltDataset = HistoricalDatasetManifestBuilder.Build(
            manifest.Dataset.DatasetId,
            manifest.Dataset.Provenance,
            candles,
            fundingPoints,
            manifest.Dataset.CreatedAt);
        if (!rebuiltDataset.IsCreated || rebuiltDataset.Manifest is null)
        {
            return Rejected(
                BacktestRunCode.InvalidDataset,
                $"The supplied market data is invalid: {string.Join(", ", rebuiltDataset.RejectionReasons)}.");
        }

        if (!string.Equals(
                rebuiltDataset.Manifest.ContentSha256,
                manifest.Dataset.ContentSha256,
                StringComparison.Ordinal)
            || !string.Equals(
                rebuiltDataset.Manifest.ManifestSha256,
                manifest.Dataset.ManifestSha256,
                StringComparison.Ordinal))
        {
            return Rejected(
                BacktestRunCode.DatasetDoesNotMatchManifest,
                "The supplied candle or funding content does not match the immutable experiment dataset manifest.");
        }

        if (!IsValidCostModel(costModel))
        {
            return Rejected(
                BacktestRunCode.InvalidCostModel,
                "The backtest cost model is invalid or has a mismatched fingerprint.");
        }

        if (!string.Equals(
            manifest.CostModelVersion,
            costModel.Version,
            StringComparison.Ordinal))
        {
            return Rejected(
                BacktestRunCode.CostModelVersionMismatch,
                "The supplied cost-model version does not match the immutable experiment manifest.");
        }

        if (!string.Equals(
            manifest.AccountingKernelVersion,
            AccountingKernelVersion,
            StringComparison.Ordinal))
        {
            return Rejected(
                BacktestRunCode.AccountingKernelVersionMismatch,
                "The experiment accounting-kernel version is not supported by this runner.");
        }

        if (!string.Equals(strategy.Name, manifest.StrategyName, StringComparison.Ordinal)
            || !string.Equals(strategy.Version, manifest.StrategyVersion, StringComparison.Ordinal))
        {
            return Rejected(
                BacktestRunCode.StrategyIdentityMismatch,
                "The strategy implementation identity does not match the immutable experiment manifest.");
        }

        if (!IsValidRules(rules))
        {
            return Rejected(
                BacktestRunCode.InvalidExecutionRules,
                "Backtest execution rules require positive equity, multiplier, quantity limits, and candle-aligned normalization settings.");
        }

        return null;
    }

    private static PendingExecutionResult ExecutePendingTarget(
        ExperimentManifest manifest,
        BacktestCostModel costModel,
        BacktestExecutionRules rules,
        Candle candle,
        int candleIndex,
        PositionAccountingAggregate position,
        PendingTarget pendingTarget,
        long fillSequence)
    {
        var delta = pendingTarget.TargetSignedQuantity
            - position.Snapshot.SignedQuantity;
        if (delta == 0m)
        {
            return new PendingExecutionResult(
                BacktestRunCode.Completed,
                "The pending target is already satisfied.",
                null,
                null);
        }

        var maximumRawFill = candle.Volume * costModel.MaximumVolumeParticipation;
        var maximumFill = NormalizeQuantityTowardsZero(
            maximumRawFill,
            rules.QuantityStep,
            rules.MinimumOrderQuantity);
        if (maximumFill == 0m)
        {
            return new PendingExecutionResult(
                BacktestRunCode.Completed,
                "No candle liquidity was available for the pending target.",
                null,
                pendingTarget with { DueCandleIndex = candleIndex + 1 });
        }

        var fillQuantity = Math.Min(Math.Abs(delta), maximumFill);
        fillQuantity = NormalizeQuantityTowardsZero(
            fillQuantity,
            rules.QuantityStep,
            rules.MinimumOrderQuantity);
        if (fillQuantity == 0m)
        {
            return new PendingExecutionResult(
                BacktestRunCode.Completed,
                "The remaining target was below the minimum executable quantity.",
                null,
                null);
        }

        var side = delta > 0m ? OrderSide.Buy : OrderSide.Sell;
        var volumeParticipation = candle.Volume > 0m
            ? fillQuantity / candle.Volume
            : 0m;
        var slippageBps = BacktestCostModelMath.CalculateSlippageBps(
            volumeParticipation,
            costModel);
        var adverseBps = costModel.HalfSpreadBps + slippageBps;
        var direction = side == OrderSide.Buy ? 1m : -1m;
        var executionPrice = candle.Open
            * (1m + (direction * adverseBps / 10_000m));
        if (executionPrice <= 0m)
        {
            return new PendingExecutionResult(
                BacktestRunCode.ExecutionRejected,
                "The configured spread and slippage produced a non-positive execution price.",
                null,
                pendingTarget);
        }

        var fee = executionPrice
            * fillQuantity
            * rules.ContractMultiplier
            * costModel.TakerFeeBps
            / 10_000m;
        var fillId = CreateDeterministicId(
            "fill",
            manifest.FingerprintSha256,
            fillSequence,
            candleIndex);
        var application = position.ApplyFill(new ExecutionFill(
            fillId,
            CreateDeterministicId(
                "order",
                manifest.FingerprintSha256,
                pendingTarget.DecisionSequence,
                pendingTarget.DueCandleIndex),
            manifest.Dataset.Symbol,
            side,
            executionPrice,
            fillQuantity,
            fee,
            candle.OpenTime,
            false));
        if (application.Code != ExecutionApplicationCode.Applied)
        {
            return new PendingExecutionResult(
                BacktestRunCode.ExecutionRejected,
                $"The execution accounting kernel rejected a simulated fill with {application.Code}.",
                null,
                pendingTarget);
        }

        var remainingTarget = position.Snapshot.SignedQuantity
                == pendingTarget.TargetSignedQuantity
            ? null
            : pendingTarget with { DueCandleIndex = candleIndex + 1 };
        return new PendingExecutionResult(
            BacktestRunCode.Completed,
            "The pending target received a deterministic partial or complete fill.",
            new BacktestFillRecord(
                fillSequence,
                candle.OpenTime,
                candle.Open,
                executionPrice,
                fillQuantity,
                side,
                costModel.HalfSpreadBps,
                slippageBps,
                fee,
                volumeParticipation,
                pendingTarget.TargetSignedQuantity,
                fillId),
            remainingTarget);
    }

    private static DecisionEvaluation EvaluateDecision(
        BacktestTargetDecision decision,
        BacktestExecutionRules rules,
        BacktestCostModel costModel,
        Candle candle,
        int candleIndex,
        int evaluationEndIndex,
        decimal currentSignedQuantity,
        decimal equity,
        PendingTarget? pendingTarget,
        long decisionSequence)
    {
        if (decision is null || string.IsNullOrWhiteSpace(decision.Reason)
            || decision.Reason.Length > 1024)
        {
            return DecisionEvaluation.Rejected(
                decisionSequence,
                candle,
                costModel,
                decision?.TargetSignedQuantity ?? 0m,
                currentSignedQuantity,
                BacktestDecisionCode.RejectedInvalidReason,
                "A strategy decision requires a non-empty reason up to 1024 characters.",
                pendingTarget);
        }

        var requestedTarget = decision.TargetSignedQuantity;
        var normalizedTarget = NormalizeSignedQuantityTowardsZero(
            requestedTarget,
            rules.QuantityStep,
            rules.MinimumOrderQuantity);
        if (Math.Abs(normalizedTarget) > rules.MaximumAbsoluteTargetQuantity)
        {
            return DecisionEvaluation.Rejected(
                decisionSequence,
                candle,
                costModel,
                requestedTarget,
                normalizedTarget,
                BacktestDecisionCode.RejectedTargetLimit,
                "The requested target exceeds the configured absolute quantity limit.",
                pendingTarget);
        }

        var targetExposure = Math.Abs(normalizedTarget)
            * candle.Close
            * rules.ContractMultiplier;
        if (targetExposure > equity * rules.MaximumGrossLeverage)
        {
            return DecisionEvaluation.Rejected(
                decisionSequence,
                candle,
                costModel,
                requestedTarget,
                normalizedTarget,
                BacktestDecisionCode.RejectedLeverage,
                "The requested target exceeds the configured gross-leverage limit.",
                pendingTarget);
        }

        var existingTarget = pendingTarget?.TargetSignedQuantity
            ?? currentSignedQuantity;
        var code = normalizedTarget == existingTarget
            ? BacktestDecisionCode.NoChange
            : pendingTarget is null
                ? normalizedTarget == 0m && requestedTarget != 0m
                    ? BacktestDecisionCode.NormalizedToFlat
                    : BacktestDecisionCode.Scheduled
                : BacktestDecisionCode.ReplacedPendingTarget;
        var dueCandleIndex = checked(candleIndex + costModel.LatencyBars);
        var earliestExecutionAt = dueCandleIndex < evaluationEndIndex
            ? candle.OpenTime + TimeSpan.FromTicks(
                checked(candle.Timeframe.Ticks * costModel.LatencyBars))
            : candle.OpenTime + TimeSpan.FromTicks(
                checked(candle.Timeframe.Ticks * costModel.LatencyBars));
        var record = new BacktestDecisionRecord(
            decisionSequence,
            candle.OpenTime + candle.Timeframe,
            earliestExecutionAt,
            requestedTarget,
            normalizedTarget,
            code,
            decision.Reason);

        if (code == BacktestDecisionCode.NoChange)
        {
            return new DecisionEvaluation(record, pendingTarget);
        }

        return new DecisionEvaluation(
            record,
            new PendingTarget(
                decisionSequence,
                dueCandleIndex,
                normalizedTarget));
    }

    private static bool IsValidCostModel(BacktestCostModel model)
    {
        var rebuilt = BacktestCostModelFactory.Create(
            model.Version,
            model.HalfSpreadBps,
            model.BaseSlippageBps,
            model.ImpactBpsAtMaximumParticipation,
            model.TakerFeeBps,
            model.MaximumVolumeParticipation,
            model.LatencyBars);
        return rebuilt.IsCreated
            && rebuilt.Model is not null
            && string.Equals(
                rebuilt.Model.FingerprintSha256,
                model.FingerprintSha256,
                StringComparison.Ordinal);
    }

    private static bool IsValidRules(BacktestExecutionRules rules)
    {
        return rules.StartingEquity > 0m
            && rules.ContractMultiplier > 0m
            && rules.QuantityStep > 0m
            && rules.MinimumOrderQuantity > 0m
            && rules.MinimumOrderQuantity >= rules.QuantityStep
            && rules.MaximumAbsoluteTargetQuantity >= rules.MinimumOrderQuantity
            && rules.MaximumGrossLeverage > 0m;
    }

    private static int FindCandleIndex(
        IReadOnlyList<Candle> candles,
        DateTimeOffset timestamp)
    {
        var normalized = timestamp.ToUniversalTime();
        for (var index = 0; index < candles.Count; index++)
        {
            if (candles[index].OpenTime == normalized)
            {
                return index;
            }
        }

        return normalized == candles[^1].OpenTime + candles[^1].Timeframe
            ? candles.Count
            : -1;
    }

    private static int FindFirstFundingIndex(
        IReadOnlyList<FundingRatePoint> funding,
        DateTimeOffset startInclusive)
    {
        var normalizedStart = startInclusive.ToUniversalTime();
        for (var index = 0; index < funding.Count; index++)
        {
            if (funding[index].OccurredAt >= normalizedStart)
            {
                return index;
            }
        }

        return funding.Count;
    }

    private static decimal NormalizeSignedQuantityTowardsZero(
        decimal quantity,
        decimal quantityStep,
        decimal minimumQuantity)
    {
        var normalizedAbsolute = NormalizeQuantityTowardsZero(
            Math.Abs(quantity),
            quantityStep,
            minimumQuantity);
        return quantity < 0m ? -normalizedAbsolute : normalizedAbsolute;
    }

    private static decimal NormalizeQuantityTowardsZero(
        decimal quantity,
        decimal quantityStep,
        decimal minimumQuantity)
    {
        if (quantity < minimumQuantity)
        {
            return 0m;
        }

        var normalized = Math.Floor(quantity / quantityStep) * quantityStep;
        return normalized < minimumQuantity ? 0m : normalized;
    }

    private static string ComputeRunFingerprint(
        ExperimentManifest manifest,
        BacktestCostModel costModel,
        BacktestExecutionRules rules)
    {
        return CanonicalResearchHash.Compute(builder =>
        {
            CanonicalResearchHash.Append(builder, "quantara-backtest-run-v1");
            CanonicalResearchHash.Append(builder, RunnerVersion);
            CanonicalResearchHash.Append(builder, manifest.FingerprintSha256);
            CanonicalResearchHash.Append(builder, costModel.FingerprintSha256);
            CanonicalResearchHash.Append(builder, rules.StartingEquity);
            CanonicalResearchHash.Append(builder, rules.ContractMultiplier);
            CanonicalResearchHash.Append(builder, rules.QuantityStep);
            CanonicalResearchHash.Append(builder, rules.MinimumOrderQuantity);
            CanonicalResearchHash.Append(
                builder,
                rules.MaximumAbsoluteTargetQuantity);
            CanonicalResearchHash.Append(builder, rules.MaximumGrossLeverage);
        });
    }

    private static string CreateDeterministicId(
        string kind,
        string experimentFingerprint,
        long sequence,
        int candleIndex)
    {
        var fingerprint = CanonicalResearchHash.Compute(builder =>
        {
            CanonicalResearchHash.Append(builder, "quantara-backtest-event-id-v1");
            CanonicalResearchHash.Append(builder, kind);
            CanonicalResearchHash.Append(builder, experimentFingerprint);
            CanonicalResearchHash.Append(builder, sequence);
            CanonicalResearchHash.Append(builder, candleIndex);
        });
        return $"bt-{kind}-{fingerprint[..24]}";
    }

    private static BacktestRunResult Rejected(
        BacktestRunCode code,
        string message)
    {
        return new BacktestRunResult(
            code,
            message,
            null,
            Array.Empty<BacktestDecisionRecord>(),
            Array.Empty<BacktestFillRecord>(),
            Array.Empty<BacktestFundingRecord>(),
            Array.Empty<BacktestEquityPoint>(),
            Array.Empty<BacktestRunWarning>(),
            null,
            0m,
            0m);
    }

    private static BacktestRunResult FailedWithState(
        BacktestRunCode code,
        string message,
        ExperimentManifest manifest,
        BacktestCostModel costModel,
        BacktestExecutionRules rules,
        IReadOnlyList<BacktestDecisionRecord> decisions,
        IReadOnlyList<BacktestFillRecord> fills,
        IReadOnlyList<BacktestFundingRecord> funding,
        IReadOnlyList<BacktestEquityPoint> equityCurve,
        IReadOnlyList<BacktestRunWarning> warnings,
        PositionAccountingAggregate position,
        decimal equity,
        decimal pendingTarget)
    {
        return new BacktestRunResult(
            code,
            message,
            ComputeRunFingerprint(manifest, costModel, rules),
            decisions,
            fills,
            funding,
            equityCurve,
            warnings,
            position.Snapshot,
            equity,
            pendingTarget);
    }

    private sealed record PendingTarget(
        long DecisionSequence,
        int DueCandleIndex,
        decimal TargetSignedQuantity);

    private sealed record PendingExecutionResult(
        BacktestRunCode Code,
        string Message,
        BacktestFillRecord? Fill,
        PendingTarget? RemainingTarget);

    private sealed record DecisionEvaluation(
        BacktestDecisionRecord Record,
        PendingTarget? PendingTarget)
    {
        public static DecisionEvaluation Rejected(
            long sequence,
            Candle candle,
            BacktestCostModel costModel,
            decimal requestedTarget,
            decimal normalizedTarget,
            BacktestDecisionCode code,
            string message,
            PendingTarget? pendingTarget)
        {
            return new DecisionEvaluation(
                new BacktestDecisionRecord(
                    sequence,
                    candle.OpenTime + candle.Timeframe,
                    candle.OpenTime + TimeSpan.FromTicks(
                        checked(candle.Timeframe.Ticks * costModel.LatencyBars)),
                    requestedTarget,
                    normalizedTarget,
                    code,
                    message),
                pendingTarget);
        }
    }
}

