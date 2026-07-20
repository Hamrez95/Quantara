from pathlib import Path


def replace_once(path: Path, old: str, new: str) -> None:
    content = path.read_text(encoding="utf-8")
    occurrences = content.count(old)
    if occurrences != 1:
        raise RuntimeError(
            f"Expected exactly one source block in {path}, found {occurrences}."
        )
    path.write_text(content.replace(old, new, 1), encoding="utf-8")


builder_path = Path(
    "src/backend/Quantara.Domain/Backtesting/BacktestPerformanceReportBuilder.cs"
)
runner_path = Path(
    "src/backend/Quantara.Domain/Backtesting/DeterministicBacktestRunner.cs"
)

old_equity_validation = """    private static bool IsValidEquityCurve(
        ExperimentManifest manifest,
        BacktestRunResult run,
        BacktestExecutionRules rules)
    {
        if (run.EquityCurve.Count < 2
            || rules.StartingEquity <= 0m
            || run.EquityCurve.Any(point =>
                point.Timestamp <= manifest.EvaluationWindow.StartInclusive
                || point.Timestamp > manifest.EvaluationWindow.EndExclusive
                || point.Equity <= 0m
                || point.MarkPrice <= 0m
                || point.GrossExposure < 0m
                || point.GrossLeverage < 0m))
        {
            return false;
        }

        for (var index = 1; index < run.EquityCurve.Count; index++)
        {
            if (run.EquityCurve[index].Timestamp
                <= run.EquityCurve[index - 1].Timestamp)
            {
                return false;
            }
        }

        return run.EquityCurve[^1].Equity == run.FinalEquity;
    }
"""

new_equity_validation = """    private static bool IsValidEquityCurve(
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
"""

old_fill_reconciliation = """        var direction = fill.Side == Trading.OrderSide.Buy ? 1m : -1m;
        var expectedExecutionPrice = fill.ReferencePrice
            * (1m + (direction
                * (fill.SpreadBps + fill.SlippageBps)
                / 10_000m));
        var expectedFee = fill.ExecutionPrice
            * fill.Quantity
            * rules.ContractMultiplier
            * costModel.TakerFeeBps
            / 10_000m;

        return fill.ExecutionPrice == expectedExecutionPrice
            && fill.Fee == expectedFee;
"""

new_fill_reconciliation = """        var expectedSlippageBps = BacktestCostModelMath.CalculateSlippageBps(
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
"""

old_runner_slippage = """        var liquidityUsage = maximumRawFill > 0m
            ? fillQuantity / maximumRawFill
            : 0m;
        var slippageBps = costModel.BaseSlippageBps
            + (costModel.ImpactBpsAtMaximumParticipation * liquidityUsage);
"""

new_runner_slippage = """        var slippageBps = BacktestCostModelMath.CalculateSlippageBps(
            volumeParticipation,
            costModel);
"""

replace_once(
    builder_path,
    old_equity_validation,
    new_equity_validation,
)
replace_once(
    builder_path,
    old_fill_reconciliation,
    new_fill_reconciliation,
)
replace_once(
    runner_path,
    old_runner_slippage,
    new_runner_slippage,
)
