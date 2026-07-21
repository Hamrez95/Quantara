using Quantara.Domain.Execution;

namespace Quantara.Domain.Backtesting;

public static class BacktestLedgerHasher
{
    public const string LedgerSchemaVersion = "backtest-ledger-v1";

    public static string ComputeSha256(BacktestRunResult result)
    {
        ArgumentNullException.ThrowIfNull(result);

        return CanonicalResearchHash.Compute(builder =>
        {
            CanonicalResearchHash.Append(builder, LedgerSchemaVersion);
            CanonicalResearchHash.Append(builder, result.Code.ToString());
            CanonicalResearchHash.Append(builder, result.Message);
            CanonicalResearchHash.Append(
                builder,
                result.RunFingerprintSha256 ?? string.Empty);
            AppendDecisions(builder, result.Decisions);
            AppendFills(builder, result.Fills);
            AppendFunding(builder, result.Funding);
            AppendEquity(builder, result.EquityCurve);
            AppendWarnings(builder, result.Warnings);
            AppendFinalPosition(builder, result.FinalPosition);
            CanonicalResearchHash.Append(builder, result.FinalEquity);
            CanonicalResearchHash.Append(
                builder,
                result.EffectiveTargetSignedQuantity);
        });
    }

    private static void AppendDecisions(
        System.Text.StringBuilder builder,
        IReadOnlyList<BacktestDecisionRecord> decisions)
    {
        CanonicalResearchHash.Append(builder, decisions.Count);
        foreach (var decision in decisions)
        {
            CanonicalResearchHash.Append(builder, decision.Sequence);
            CanonicalResearchHash.Append(builder, decision.DecidedAt);
            CanonicalResearchHash.Append(builder, decision.EarliestExecutionAt);
            CanonicalResearchHash.Append(
                builder,
                decision.RequestedTargetSignedQuantity);
            CanonicalResearchHash.Append(
                builder,
                decision.NormalizedTargetSignedQuantity);
            CanonicalResearchHash.Append(builder, decision.Code.ToString());
            CanonicalResearchHash.Append(builder, decision.Reason);
        }
    }

    private static void AppendFills(
        System.Text.StringBuilder builder,
        IReadOnlyList<BacktestFillRecord> fills)
    {
        CanonicalResearchHash.Append(builder, fills.Count);
        foreach (var fill in fills)
        {
            CanonicalResearchHash.Append(builder, fill.Sequence);
            CanonicalResearchHash.Append(builder, fill.OccurredAt);
            CanonicalResearchHash.Append(builder, fill.ReferencePrice);
            CanonicalResearchHash.Append(builder, fill.ExecutionPrice);
            CanonicalResearchHash.Append(builder, fill.Quantity);
            CanonicalResearchHash.Append(builder, fill.Side.ToString());
            CanonicalResearchHash.Append(builder, fill.SpreadBps);
            CanonicalResearchHash.Append(builder, fill.SlippageBps);
            CanonicalResearchHash.Append(builder, fill.Fee);
            CanonicalResearchHash.Append(builder, fill.VolumeParticipation);
            CanonicalResearchHash.Append(builder, fill.TargetSignedQuantity);
            CanonicalResearchHash.Append(builder, fill.FillId);
        }
    }

    private static void AppendFunding(
        System.Text.StringBuilder builder,
        IReadOnlyList<BacktestFundingRecord> funding)
    {
        CanonicalResearchHash.Append(builder, funding.Count);
        foreach (var point in funding)
        {
            CanonicalResearchHash.Append(builder, point.Sequence);
            CanonicalResearchHash.Append(builder, point.OccurredAt);
            CanonicalResearchHash.Append(builder, point.Rate);
            CanonicalResearchHash.Append(builder, point.ReferencePrice);
            CanonicalResearchHash.Append(builder, point.SignedQuantity);
            CanonicalResearchHash.Append(builder, point.NetAmount);
            CanonicalResearchHash.Append(builder, point.SettlementId);
        }
    }

    private static void AppendEquity(
        System.Text.StringBuilder builder,
        IReadOnlyList<BacktestEquityPoint> equityCurve)
    {
        CanonicalResearchHash.Append(builder, equityCurve.Count);
        foreach (var point in equityCurve)
        {
            CanonicalResearchHash.Append(builder, point.Timestamp);
            CanonicalResearchHash.Append(builder, point.MarkPrice);
            CanonicalResearchHash.Append(builder, point.Equity);
            CanonicalResearchHash.Append(builder, point.NetRealizedPnl);
            CanonicalResearchHash.Append(builder, point.UnrealizedPnl);
            CanonicalResearchHash.Append(builder, point.GrossExposure);
            CanonicalResearchHash.Append(builder, point.GrossLeverage);
        }
    }

    private static void AppendWarnings(
        System.Text.StringBuilder builder,
        IReadOnlyList<BacktestRunWarning> warnings)
    {
        CanonicalResearchHash.Append(builder, warnings.Count);
        foreach (var warning in warnings)
        {
            CanonicalResearchHash.Append(builder, warning.Code);
            CanonicalResearchHash.Append(builder, warning.Message);
        }
    }

    private static void AppendFinalPosition(
        System.Text.StringBuilder builder,
        PositionSnapshot? position)
    {
        if (position is null)
        {
            CanonicalResearchHash.Append(builder, "null-position");
            return;
        }

        CanonicalResearchHash.Append(builder, "position");
        CanonicalResearchHash.Append(builder, position.Symbol.Value);
        CanonicalResearchHash.Append(
            builder,
            position.Direction?.ToString() ?? "flat");
        CanonicalResearchHash.Append(builder, position.Quantity);
        CanonicalResearchHash.Append(builder, position.SignedQuantity);
        CanonicalResearchHash.Append(builder, position.AverageEntryPrice);
        CanonicalResearchHash.Append(builder, position.ContractMultiplier);
        CanonicalResearchHash.Append(builder, position.GrossRealizedPnl);
        CanonicalResearchHash.Append(builder, position.FeesPaid);
        CanonicalResearchHash.Append(builder, position.FundingNet);
        CanonicalResearchHash.Append(builder, position.NetRealizedPnl);
    }
}
