using Quantara.Domain.Execution;

namespace Quantara.Domain.Backtesting;

public static class BacktestPerformanceReportBuilder
{
    public static BacktestReportBuildResult Build(
        ExperimentManifest manifest,
        BacktestCostModel costModel,
        BacktestExecutionRules rules,
        BacktestRunResult run,
        BenchmarkEquitySeries benchmark,
        BacktestReportSpecification specification)
    {
        ArgumentNullException.ThrowIfNull(manifest);
        ArgumentNullException.ThrowIfNull(costModel);
        ArgumentNullException.ThrowIfNull(rules);
        ArgumentNullException.ThrowIfNull(run);
        ArgumentNullException.ThrowIfNull(benchmark);
        ArgumentNullException.ThrowIfNull(specification);

        var rejections = new HashSet<BacktestReportCode>();
        if (!run.IsCompleted)
        {
            rejections.Add(BacktestReportCode.RunNotCompleted);
        }

        if (!IsValidSpecification(specification))
        {
            rejections.Add(BacktestReportCode.InvalidSpecification);
        }

        if (!IsValidRunIdentity(manifest, costModel, rules, run))
        {
            rejections.Add(BacktestReportCode.InvalidRunIdentity);
        }

        if (!IsValidEquityCurve(manifest, run, rules))
        {
            rejections.Add(BacktestReportCode.InvalidEquityCurve);
        }

        if (!IsValidBenchmark(benchmark))
        {
            rejections.Add(BacktestReportCode.InvalidBenchmark);
        }
        else if (!TimestampsAlign(run.EquityCurve, benchmark.Points))
        {
            rejections.Add(BacktestReportCode.BenchmarkTimestampMismatch);
        }

        if (!IsValidFinalState(run, rules, costModel))
        {
            rejections.Add(BacktestReportCode.InvalidFinalState);
        }

        if (rejections.Count > 0)
        {
            return new BacktestReportBuildResult(
                false,
                Array.AsReadOnly(rejections.Order().ToArray()),
                null);
        }

        var strategyReturns = CalculatePeriodicReturns(
            rules.StartingEquity,
            run.EquityCurve.Select(point => point.Equity));
        var benchmarkReturns = CalculatePeriodicReturns(
            benchmark.StartingValue,
            benchmark.Points.Select(point => point.Value));
        var totalReturn = CalculateTotalReturn(rules.StartingEquity, run.FinalEquity);
        var returnMetrics = CalculateReturnMetrics(
            strategyReturns,
            totalReturn,
            run.EquityCurve,
            rules.StartingEquity,
            manifest.EvaluationWindow.StartInclusive,
            specification);
        var executionMetrics = CalculateExecutionMetrics(run, rules);
        var benchmarkMetrics = CalculateBenchmarkMetrics(
            strategyReturns,
            benchmarkReturns,
            benchmark,
            specification,
            totalReturn);
        var bootstrap = CalculateBootstrapInterval(
            strategyReturns,
            manifest.RandomSeed,
            specification);
        var ledgerSha256 = BacktestLedgerHasher.ComputeSha256(run);
        var benchmarkSha256 = BenchmarkEquityHasher.ComputeSha256(benchmark);
        var reportSha256 = ComputeReportSha256(
            specification,
            ledgerSha256,
            benchmarkSha256,
            manifest,
            run,
            returnMetrics,
            executionMetrics,
            benchmarkMetrics,
            bootstrap,
            rules.StartingEquity);

        return new BacktestReportBuildResult(
            true,
            Array.Empty<BacktestReportCode>(),
            new BacktestPerformanceReport(
                specification.Version,
                ledgerSha256,
                benchmarkSha256,
                reportSha256,
                manifest.FingerprintSha256,
                run.RunFingerprintSha256!,
                manifest.EvaluationWindow.StartInclusive,
                run.EquityCurve[^1].Timestamp,
                rules.StartingEquity,
                run.FinalEquity,
                returnMetrics,
                executionMetrics,
                benchmarkMetrics,
                bootstrap,
                run.FinalPosition!,
                run.EffectiveTargetSignedQuantity,
                run.Warnings));
    }

    private static bool IsValidSpecification(BacktestReportSpecification specification)
    {
        return !string.IsNullOrWhiteSpace(specification.Version)
            && specification.Version.Length <= 128
            && string.Equals(
                specification.Version,
                specification.Version.Trim(),
                StringComparison.Ordinal)
            && double.IsFinite(specification.PeriodsPerYear)
            && specification.PeriodsPerYear > 0d
            && double.IsFinite(specification.AnnualRiskFreeRate)
            && specification.AnnualRiskFreeRate > -1d
            && specification.BootstrapSamples is >= 100 and <= 100_000
            && double.IsFinite(specification.BootstrapConfidenceLevel)
            && specification.BootstrapConfidenceLevel > 0.5d
            && specification.BootstrapConfidenceLevel < 1d
            && specification.BootstrapBlockLength >= 1;
    }

    private static bool IsValidRunIdentity(
        ExperimentManifest manifest,
        BacktestCostModel costModel,
        BacktestExecutionRules rules,
        BacktestRunResult run)
    {
        if (!CanonicalResearchHash.IsSha256(run.RunFingerprintSha256)
            || !CanonicalResearchHash.IsSha256(costModel.FingerprintSha256))
        {
            return false;
        }

        var rebuiltCostModel = BacktestCostModelFactory.Create(
            costModel.Version,
            costModel.HalfSpreadBps,
            costModel.BaseSlippageBps,
            costModel.ImpactBpsAtMaximumParticipation,
            costModel.TakerFeeBps,
            costModel.MaximumVolumeParticipation,
            costModel.LatencyBars);
        if (!rebuiltCostModel.IsCreated
            || rebuiltCostModel.Model is null
            || !string.Equals(
                rebuiltCostModel.Model.FingerprintSha256,
                costModel.FingerprintSha256,
                StringComparison.Ordinal))
        {
            return false;
        }

        var expectedFingerprint = CanonicalResearchHash.Compute(builder =>
        {
            CanonicalResearchHash.Append(builder, "quantara-backtest-run-v1");
            CanonicalResearchHash.Append(
                builder,
                DeterministicBacktestRunner.RunnerVersion);
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

        return string.Equals(
            expectedFingerprint,
            run.RunFingerprintSha256,
            StringComparison.Ordinal);
    }

    private static bool IsValidEquityCurve(
        ExperimentManifest manifest,
        BacktestRunResult run,
        BacktestExecutionRules rules)
    {
        if (rules.StartingEquity <= 0m
            || manifest.Dataset.Timeframe <= TimeSpan.Zero)
        {
            return false;
        }

        var startUtc = manifest.EvaluationWindow.StartInclusive.ToUniversalTime();
        var endUtc = manifest.EvaluationWindow.EndExclusive.ToUniversalTime();
        var timeframeTicks = manifest.Dataset.Timeframe.Ticks;
        long windowTicks;
        try
        {
            windowTicks = checked(endUtc.Ticks - startUtc.Ticks);
        }
        catch (OverflowException)
        {
            return false;
        }

        if (windowTicks <= 0
            || windowTicks % timeframeTicks != 0)
        {
            return false;
        }

        var expectedCount = windowTicks / timeframeTicks;
        if (expectedCount < 2
            || expectedCount > int.MaxValue
            || run.EquityCurve.Count != expectedCount)
        {
            return false;
        }

        try
        {
            for (var index = 0; index < run.EquityCurve.Count; index++)
            {
                var expectedTimestampTicks = checked(
                    startUtc.Ticks
                    + checked(timeframeTicks * (index + 1L)));
                var point = run.EquityCurve[index];
                if (point.Timestamp.ToUniversalTime().Ticks != expectedTimestampTicks
                    || point.Equity <= 0m
                    || point.MarkPrice <= 0m
                    || point.GrossExposure < 0m
                    || point.GrossLeverage < 0m)
                {
                    return false;
                }
            }
        }
        catch (OverflowException)
        {
            return false;
        }

        return run.EquityCurve[^1].Timestamp.ToUniversalTime() == endUtc
            && run.EquityCurve[^1].Equity == run.FinalEquity;
    }

    private static bool IsValidBenchmark(BenchmarkEquitySeries benchmark)
    {
        if (string.IsNullOrWhiteSpace(benchmark.Name)
            || benchmark.Name.Length > 128
            || !string.Equals(benchmark.Name, benchmark.Name.Trim(), StringComparison.Ordinal)
            || benchmark.StartingValue <= 0m
            || benchmark.Points.Count < 2
            || benchmark.Points.Any(point => point.Value <= 0m))
        {
            return false;
        }

        for (var index = 1; index < benchmark.Points.Count; index++)
        {
            if (benchmark.Points[index].Timestamp
                <= benchmark.Points[index - 1].Timestamp)
            {
                return false;
            }
        }

        return true;
    }

    private static bool TimestampsAlign(
        IReadOnlyList<BacktestEquityPoint> equityCurve,
        IReadOnlyList<BenchmarkEquityPoint> benchmark)
    {
        return equityCurve.Count == benchmark.Count
            && equityCurve
                .Select(point => point.Timestamp.ToUniversalTime())
                .SequenceEqual(
                    benchmark.Select(point => point.Timestamp.ToUniversalTime()));
    }

    private static bool IsValidFinalState(
        BacktestRunResult run,
        BacktestExecutionRules rules,
        BacktestCostModel costModel)
    {
        if (run.FinalPosition is null
            || !IsValidPosition(run.FinalPosition, rules)
            || Math.Abs(run.EffectiveTargetSignedQuantity)
                > rules.MaximumAbsoluteTargetQuantity
            || !HasContiguousSequences(run.Decisions.Select(item => item.Sequence))
            || !HasContiguousSequences(run.Fills.Select(item => item.Sequence))
            || !HasContiguousSequences(run.Funding.Select(item => item.Sequence)))
        {
            return false;
        }

        var fillIds = new HashSet<string>(StringComparer.Ordinal);
        var settlementIds = new HashSet<string>(StringComparer.Ordinal);

        return run.Decisions.All(decision =>
                Enum.IsDefined(typeof(BacktestDecisionCode), decision.Code)
                && decision.EarliestExecutionAt >= decision.DecidedAt
                && !string.IsNullOrWhiteSpace(decision.Reason))
            && run.Fills.All(fill =>
                IsValidFill(fill, rules, costModel)
                && fillIds.Add(fill.FillId))
            && run.Funding.All(point =>
                IsValidFunding(point, rules)
                && settlementIds.Add(point.SettlementId))
            && run.Warnings.All(warning =>
                !string.IsNullOrWhiteSpace(warning.Code)
                && !string.IsNullOrWhiteSpace(warning.Message));
    }

    private static bool IsValidFill(
        BacktestFillRecord fill,
        BacktestExecutionRules rules,
        BacktestCostModel costModel)
    {
        if (!Enum.IsDefined(typeof(Trading.OrderSide), fill.Side)
            || fill.ExecutionPrice <= 0m
            || fill.ReferencePrice <= 0m
            || fill.Quantity <= 0m
            || fill.Fee < 0m
            || fill.SpreadBps != costModel.HalfSpreadBps
            || fill.SlippageBps < costModel.BaseSlippageBps
            || fill.SlippageBps
                > costModel.BaseSlippageBps
                    + costModel.ImpactBpsAtMaximumParticipation
            || fill.VolumeParticipation < 0m
            || fill.VolumeParticipation > costModel.MaximumVolumeParticipation
            || string.IsNullOrWhiteSpace(fill.FillId))
        {
            return false;
        }

        var expectedSlippageBps = BacktestCostModelMath.CalculateSlippageBps(
            fill.VolumeParticipation,
            costModel);
        var direction = fill.Side == Trading.OrderSide.Buy ? 1m : -1m;
        var expectedExecutionPrice = fill.ReferencePrice
            * (1m + (direction
                * (fill.SpreadBps + fill.SlippageBps)
                / 10_000m));
        var expectedFee = fill.ExecutionPrice
            * fill.Quantity
            * rules.ContractMultiplier
            * costModel.TakerFeeBps
            / 10_000m;

        return fill.SlippageBps == expectedSlippageBps
            && fill.ExecutionPrice == expectedExecutionPrice
            && fill.Fee == expectedFee;
    }

    private static bool IsValidFunding(
        BacktestFundingRecord point,
        BacktestExecutionRules rules)
    {
        if (point.ReferencePrice <= 0m
            || string.IsNullOrWhiteSpace(point.SettlementId))
        {
            return false;
        }

        var expectedNetAmount = -point.SignedQuantity
            * point.ReferencePrice
            * rules.ContractMultiplier
            * point.Rate;
        return point.NetAmount == expectedNetAmount;
    }

    private static bool IsValidPosition(
        PositionSnapshot position,
        BacktestExecutionRules rules)
    {
        if (position.ContractMultiplier != rules.ContractMultiplier
            || position.Quantity < 0m
            || position.Quantity != Math.Abs(position.SignedQuantity)
            || position.FeesPaid < 0m)
        {
            return false;
        }

        if (position.Quantity == 0m)
        {
            return position.Direction is null
                && position.SignedQuantity == 0m
                && position.AverageEntryPrice == 0m;
        }

        return position.Direction is not null
            && position.AverageEntryPrice > 0m
            && ((position.SignedQuantity > 0m
                    && position.Direction == Trading.TradeDirection.Long)
                || (position.SignedQuantity < 0m
                    && position.Direction == Trading.TradeDirection.Short));
    }

    private static bool HasContiguousSequences(IEnumerable<long> sequences)
    {
        long expected = 0;
        foreach (var sequence in sequences)
        {
            if (sequence != expected)
            {
                return false;
            }

            expected++;
        }

        return true;
    }

    private static double[] CalculatePeriodicReturns(
        decimal startingValue,
        IEnumerable<decimal> values)
    {
        var previous = startingValue;
        var returns = new List<double>();
        foreach (var value in values)
        {
            returns.Add((double)((value / previous) - 1m));
            previous = value;
        }

        return returns.ToArray();
    }

    private static double CalculateTotalReturn(
        decimal startingEquity,
        decimal finalEquity)
    {
        return (double)((finalEquity / startingEquity) - 1m);
    }

    private static BacktestReturnMetrics CalculateReturnMetrics(
        IReadOnlyList<double> returns,
        double totalReturn,
        IReadOnlyList<BacktestEquityPoint> equityCurve,
        decimal startingEquity,
        DateTimeOffset evaluationStart,
        BacktestReportSpecification specification)
    {
        var mean = Mean(returns);
        var standardDeviation = SampleStandardDeviation(returns, mean);
        var annualizedReturn = FiniteMetric(
            Math.Pow(
                1d + totalReturn,
                specification.PeriodsPerYear / returns.Count)
                - 1d,
            "Annualized return is not finite for this return path and annualization factor.");
        var annualizedVolatility = BacktestMetric.Defined(
            standardDeviation * Math.Sqrt(specification.PeriodsPerYear));
        var riskFreePerPeriod = Math.Pow(
                1d + specification.AnnualRiskFreeRate,
                1d / specification.PeriodsPerYear)
            - 1d;
        var excessMean = mean - riskFreePerPeriod;
        var sharpe = standardDeviation == 0d
            ? BacktestMetric.Undefined(
                "Sharpe ratio is undefined for a zero-variance return series.")
            : FiniteMetric(
                excessMean
                    * Math.Sqrt(specification.PeriodsPerYear)
                    / standardDeviation,
                "Sharpe ratio is not finite for this return path.");
        var downsideDeviation = DownsideDeviation(returns, riskFreePerPeriod);
        var sortino = downsideDeviation == 0d
            ? BacktestMetric.Undefined(
                "Sortino ratio is undefined when there are no downside observations.")
            : FiniteMetric(
                excessMean
                    * Math.Sqrt(specification.PeriodsPerYear)
                    / downsideDeviation,
                "Sortino ratio is not finite for this return path.");
        var drawdown = CalculateDrawdown(
            equityCurve,
            startingEquity,
            evaluationStart);
        var calmar = drawdown.MaximumDrawdown == 0d
            ? BacktestMetric.Undefined(
                "Calmar ratio is undefined when maximum drawdown is zero.")
            : annualizedReturn.IsDefined
                ? FiniteMetric(
                    annualizedReturn.Value!.Value / drawdown.MaximumDrawdown,
                    "Calmar ratio is not finite for this return path.")
                : BacktestMetric.Undefined(
                    "Calmar ratio is undefined because annualized return is undefined.");
        var wins = returns.Count(value => value > 0d);
        var losses = returns.Count(value => value < 0d);

        return new BacktestReturnMetrics(
            totalReturn,
            annualizedReturn,
            annualizedVolatility,
            sharpe,
            sortino,
            calmar,
            drawdown.MaximumDrawdown,
            drawdown.MaximumDuration,
            wins / (double)returns.Count,
            losses / (double)returns.Count);
    }

    private static BacktestMetric FiniteMetric(double value, string undefinedReason)
    {
        return double.IsFinite(value)
            ? BacktestMetric.Defined(value)
            : BacktestMetric.Undefined(undefinedReason);
    }

    private static BacktestExecutionMetrics CalculateExecutionMetrics(
        BacktestRunResult run,
        BacktestExecutionRules rules)
    {
        var totalFees = run.Fills.Sum(fill => fill.Fee);
        var netFunding = run.Funding.Sum(point => point.NetAmount);
        var spreadCost = run.Fills.Sum(fill =>
            fill.ReferencePrice
            * fill.Quantity
            * rules.ContractMultiplier
            * fill.SpreadBps
            / 10_000m);
        var slippageCost = run.Fills.Sum(fill =>
            fill.ReferencePrice
            * fill.Quantity
            * rules.ContractMultiplier
            * fill.SlippageBps
            / 10_000m);
        var tradedNotional = run.Fills.Sum(fill =>
            fill.ExecutionPrice * fill.Quantity * rules.ContractMultiplier);
        var averageEquity = run.EquityCurve.Average(point => point.Equity);
        var turnover = averageEquity > 0m
            ? (double)(tradedNotional / averageEquity)
            : 0d;
        var timeInMarket = run.EquityCurve.Count(point => point.GrossExposure > 0m)
            / (double)run.EquityCurve.Count;
        var averageLeverage = run.EquityCurve.Average(point =>
            (double)point.GrossLeverage);
        var maximumLeverage = run.EquityCurve.Max(point =>
            (double)point.GrossLeverage);
        var averageParticipation = run.Fills.Count == 0
            ? 0d
            : run.Fills.Average(fill => (double)fill.VolumeParticipation);
        var maximumParticipation = run.Fills.Count == 0
            ? 0d
            : run.Fills.Max(fill => (double)fill.VolumeParticipation);

        return new BacktestExecutionMetrics(
            totalFees,
            netFunding,
            spreadCost,
            slippageCost,
            tradedNotional,
            turnover,
            timeInMarket,
            averageLeverage,
            maximumLeverage,
            run.Fills.Count,
            averageParticipation,
            maximumParticipation);
    }

    private static BacktestBenchmarkMetrics CalculateBenchmarkMetrics(
        IReadOnlyList<double> strategyReturns,
        IReadOnlyList<double> benchmarkReturns,
        BenchmarkEquitySeries benchmark,
        BacktestReportSpecification specification,
        double strategyTotalReturn)
    {
        var benchmarkTotalReturn = (double)(
            (benchmark.Points[^1].Value / benchmark.StartingValue) - 1m);
        var benchmarkMean = Mean(benchmarkReturns);
        var strategyMean = Mean(strategyReturns);
        var benchmarkVariance = SampleVariance(benchmarkReturns, benchmarkMean);
        var strategyVariance = SampleVariance(strategyReturns, strategyMean);
        var covariance = SampleCovariance(
            strategyReturns,
            benchmarkReturns,
            strategyMean,
            benchmarkMean);
        var beta = benchmarkVariance == 0d
            ? BacktestMetric.Undefined(
                "Beta is undefined for a zero-variance benchmark.")
            : FiniteMetric(
                covariance / benchmarkVariance,
                "Beta is not finite for these return paths.");
        var correlationDenominator = Math.Sqrt(
            strategyVariance * benchmarkVariance);
        var correlation = correlationDenominator == 0d
            ? BacktestMetric.Undefined(
                "Correlation is undefined when either return series has zero variance.")
            : BacktestMetric.Defined(Math.Clamp(
                covariance / correlationDenominator,
                -1d,
                1d));
        var activeReturns = strategyReturns
            .Zip(benchmarkReturns, (strategy, baseline) => strategy - baseline)
            .ToArray();
        var activeMean = Mean(activeReturns);
        var activeStandardDeviation = SampleStandardDeviation(
            activeReturns,
            activeMean);
        var trackingError = BacktestMetric.Defined(
            activeStandardDeviation * Math.Sqrt(specification.PeriodsPerYear));
        var informationRatio = activeStandardDeviation == 0d
            ? BacktestMetric.Undefined(
                "Information ratio is undefined for a zero-variance active-return series.")
            : FiniteMetric(
                activeMean
                    * Math.Sqrt(specification.PeriodsPerYear)
                    / activeStandardDeviation,
                "Information ratio is not finite for these return paths.");

        return new BacktestBenchmarkMetrics(
            benchmark.Name,
            benchmarkTotalReturn,
            strategyTotalReturn - benchmarkTotalReturn,
            beta,
            correlation,
            trackingError,
            informationRatio);
    }

    private static BacktestBootstrapInterval CalculateBootstrapInterval(
        IReadOnlyList<double> returns,
        int seed,
        BacktestReportSpecification specification)
    {
        var blockLength = Math.Min(
            specification.BootstrapBlockLength,
            returns.Count);
        var random = new StableDeterministicRandom(
            unchecked(seed ^ 0x5EEDB007));
        var samples = new double[specification.BootstrapSamples];

        for (var sampleIndex = 0;
             sampleIndex < samples.Length;
             sampleIndex++)
        {
            var compounded = 1d;
            var generated = 0;
            while (generated < returns.Count)
            {
                var start = (int)(random.NextUInt32() % (uint)returns.Count);
                for (var offset = 0;
                     offset < blockLength && generated < returns.Count;
                     offset++)
                {
                    compounded *= 1d + returns[(start + offset) % returns.Count];
                    generated++;
                }
            }

            samples[sampleIndex] = compounded - 1d;
        }

        Array.Sort(samples);
        var alpha = (1d - specification.BootstrapConfidenceLevel) / 2d;
        return new BacktestBootstrapInterval(
            specification.BootstrapConfidenceLevel,
            specification.BootstrapSamples,
            blockLength,
            Quantile(samples, alpha),
            Quantile(samples, 0.5d),
            Quantile(samples, 1d - alpha));
    }

    private static DrawdownResult CalculateDrawdown(
        IReadOnlyList<BacktestEquityPoint> equityCurve,
        decimal startingEquity,
        DateTimeOffset evaluationStart)
    {
        var peak = startingEquity;
        var peakTimestamp = evaluationStart.ToUniversalTime();
        var underwaterStart = (DateTimeOffset?)null;
        var maximumDrawdown = 0d;
        var maximumDuration = TimeSpan.Zero;

        foreach (var point in equityCurve)
        {
            if (point.Equity >= peak)
            {
                if (underwaterStart.HasValue)
                {
                    var recoveredDuration = point.Timestamp - underwaterStart.Value;
                    if (recoveredDuration > maximumDuration)
                    {
                        maximumDuration = recoveredDuration;
                    }
                }

                peak = point.Equity;
                peakTimestamp = point.Timestamp;
                underwaterStart = null;
                continue;
            }

            underwaterStart ??= peakTimestamp;
            var drawdown = (double)(1m - (point.Equity / peak));
            if (drawdown > maximumDrawdown)
            {
                maximumDrawdown = drawdown;
            }
        }

        if (underwaterStart.HasValue)
        {
            var openDuration = equityCurve[^1].Timestamp - underwaterStart.Value;
            if (openDuration > maximumDuration)
            {
                maximumDuration = openDuration;
            }
        }

        return new DrawdownResult(maximumDrawdown, maximumDuration);
    }

    private static double Mean(IReadOnlyList<double> values)
    {
        return values.Sum() / values.Count;
    }

    private static double SampleVariance(
        IReadOnlyList<double> values,
        double mean)
    {
        if (values.Count < 2)
        {
            return 0d;
        }

        var sum = values.Sum(value =>
        {
            var difference = value - mean;
            return difference * difference;
        });
        return sum / (values.Count - 1);
    }

    private static double SampleStandardDeviation(
        IReadOnlyList<double> values,
        double mean)
    {
        return Math.Sqrt(SampleVariance(values, mean));
    }

    private static double SampleCovariance(
        IReadOnlyList<double> left,
        IReadOnlyList<double> right,
        double leftMean,
        double rightMean)
    {
        if (left.Count < 2)
        {
            return 0d;
        }

        var sum = 0d;
        for (var index = 0; index < left.Count; index++)
        {
            sum += (left[index] - leftMean) * (right[index] - rightMean);
        }

        return sum / (left.Count - 1);
    }

    private static double DownsideDeviation(
        IReadOnlyList<double> returns,
        double riskFreePerPeriod)
    {
        var sum = 0d;
        var downsideCount = 0;
        foreach (var value in returns)
        {
            var downside = value - riskFreePerPeriod;
            if (downside >= 0d)
            {
                continue;
            }

            sum += downside * downside;
            downsideCount++;
        }

        return downsideCount == 0
            ? 0d
            : Math.Sqrt(sum / downsideCount);
    }

    private static double Quantile(
        IReadOnlyList<double> sortedValues,
        double probability)
    {
        var position = probability * (sortedValues.Count - 1);
        var lowerIndex = (int)Math.Floor(position);
        var upperIndex = (int)Math.Ceiling(position);
        if (lowerIndex == upperIndex)
        {
            return sortedValues[lowerIndex];
        }

        var weight = position - lowerIndex;
        return sortedValues[lowerIndex]
            + ((sortedValues[upperIndex] - sortedValues[lowerIndex]) * weight);
    }

    private static string ComputeReportSha256(
        BacktestReportSpecification specification,
        string ledgerSha256,
        string benchmarkSha256,
        ExperimentManifest manifest,
        BacktestRunResult run,
        BacktestReturnMetrics returns,
        BacktestExecutionMetrics execution,
        BacktestBenchmarkMetrics benchmark,
        BacktestBootstrapInterval bootstrap,
        decimal startingEquity)
    {
        return CanonicalResearchHash.Compute(builder =>
        {
            CanonicalResearchHash.Append(builder, "quantara-performance-report-v2");
            CanonicalResearchHash.Append(builder, specification.Version);
            CanonicalResearchHash.Append(builder, specification.PeriodsPerYear);
            CanonicalResearchHash.Append(builder, specification.AnnualRiskFreeRate);
            CanonicalResearchHash.Append(builder, specification.BootstrapSamples);
            CanonicalResearchHash.Append(
                builder,
                specification.BootstrapConfidenceLevel);
            CanonicalResearchHash.Append(builder, specification.BootstrapBlockLength);
            CanonicalResearchHash.Append(builder, ledgerSha256);
            CanonicalResearchHash.Append(builder, benchmarkSha256);
            CanonicalResearchHash.Append(builder, manifest.FingerprintSha256);
            CanonicalResearchHash.Append(builder, run.RunFingerprintSha256!);
            CanonicalResearchHash.Append(builder, startingEquity);
            CanonicalResearchHash.Append(builder, run.FinalEquity);
            AppendReturnMetrics(builder, returns);
            AppendExecutionMetrics(builder, execution);
            AppendBenchmarkMetrics(builder, benchmark);
            CanonicalResearchHash.Append(builder, bootstrap.ConfidenceLevel);
            CanonicalResearchHash.Append(builder, bootstrap.SampleCount);
            CanonicalResearchHash.Append(builder, bootstrap.BlockLength);
            CanonicalResearchHash.Append(builder, bootstrap.Lower);
            CanonicalResearchHash.Append(builder, bootstrap.Median);
            CanonicalResearchHash.Append(builder, bootstrap.Upper);
        });
    }

    private static void AppendReturnMetrics(
        System.Text.StringBuilder builder,
        BacktestReturnMetrics metrics)
    {
        CanonicalResearchHash.Append(builder, metrics.TotalReturn);
        AppendMetric(builder, metrics.AnnualizedReturn);
        AppendMetric(builder, metrics.AnnualizedVolatility);
        AppendMetric(builder, metrics.SharpeRatio);
        AppendMetric(builder, metrics.SortinoRatio);
        AppendMetric(builder, metrics.CalmarRatio);
        CanonicalResearchHash.Append(builder, metrics.MaximumDrawdown);
        CanonicalResearchHash.Append(builder, metrics.MaximumDrawdownDuration);
        CanonicalResearchHash.Append(builder, metrics.WinPeriodRate);
        CanonicalResearchHash.Append(builder, metrics.LossPeriodRate);
    }

    private static void AppendExecutionMetrics(
        System.Text.StringBuilder builder,
        BacktestExecutionMetrics metrics)
    {
        CanonicalResearchHash.Append(builder, metrics.TotalFees);
        CanonicalResearchHash.Append(builder, metrics.NetFunding);
        CanonicalResearchHash.Append(builder, metrics.EstimatedSpreadCost);
        CanonicalResearchHash.Append(builder, metrics.EstimatedSlippageCost);
        CanonicalResearchHash.Append(builder, metrics.TradedNotional);
        CanonicalResearchHash.Append(builder, metrics.Turnover);
        CanonicalResearchHash.Append(builder, metrics.TimeInMarket);
        CanonicalResearchHash.Append(builder, metrics.AverageGrossLeverage);
        CanonicalResearchHash.Append(builder, metrics.MaximumGrossLeverage);
        CanonicalResearchHash.Append(builder, metrics.FillCount);
        CanonicalResearchHash.Append(builder, metrics.AverageVolumeParticipation);
        CanonicalResearchHash.Append(builder, metrics.MaximumVolumeParticipation);
    }

    private static void AppendBenchmarkMetrics(
        System.Text.StringBuilder builder,
        BacktestBenchmarkMetrics metrics)
    {
        CanonicalResearchHash.Append(builder, metrics.BenchmarkName);
        CanonicalResearchHash.Append(builder, metrics.BenchmarkTotalReturn);
        CanonicalResearchHash.Append(builder, metrics.ExcessTotalReturn);
        AppendMetric(builder, metrics.Beta);
        AppendMetric(builder, metrics.Correlation);
        AppendMetric(builder, metrics.TrackingError);
        AppendMetric(builder, metrics.InformationRatio);
    }

    private static void AppendMetric(
        System.Text.StringBuilder builder,
        BacktestMetric metric)
    {
        CanonicalResearchHash.Append(builder, metric.IsDefined ? "defined" : "undefined");
        if (metric.IsDefined)
        {
            CanonicalResearchHash.Append(builder, metric.Value!.Value);
        }
        else
        {
            CanonicalResearchHash.Append(builder, metric.UndefinedReason!);
        }
    }

    private sealed record DrawdownResult(
        double MaximumDrawdown,
        TimeSpan MaximumDuration);
}

