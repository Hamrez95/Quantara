namespace Quantara.Domain.Backtesting;

internal static class BacktestCostModelMath
{
    public static decimal CalculateSlippageBps(
        decimal volumeParticipation,
        BacktestCostModel costModel)
    {
        ArgumentNullException.ThrowIfNull(costModel);

        if (costModel.MaximumVolumeParticipation <= 0m
            || volumeParticipation < 0m
            || volumeParticipation > costModel.MaximumVolumeParticipation)
        {
            throw new ArgumentOutOfRangeException(
                nameof(volumeParticipation),
                "Volume participation must be inside the cost model participation range.");
        }

        return costModel.BaseSlippageBps
            + (costModel.ImpactBpsAtMaximumParticipation
                * (volumeParticipation / costModel.MaximumVolumeParticipation));
    }
}
