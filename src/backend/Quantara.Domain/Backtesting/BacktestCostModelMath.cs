namespace Quantara.Domain.Backtesting;

internal static class BacktestCostModelMath
{
    public static decimal CalculateSlippageBps(
        decimal volumeParticipation,
        BacktestCostModel costModel)
    {
        ArgumentNullException.ThrowIfNull(costModel);

        if (volumeParticipation < 0m
            || costModel.MaximumVolumeParticipation <= 0m)
        {
            throw new ArgumentOutOfRangeException(
                nameof(volumeParticipation),
                "Volume participation and the model participation cap must be valid.");
        }

        return costModel.BaseSlippageBps
            + (costModel.ImpactBpsAtMaximumParticipation
                * (volumeParticipation / costModel.MaximumVolumeParticipation));
    }
}
