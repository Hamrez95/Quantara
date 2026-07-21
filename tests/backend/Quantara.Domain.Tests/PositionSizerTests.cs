using Quantara.Domain.Risk;

namespace Quantara.Domain.Tests;

public sealed class PositionSizerTests
{
    [Fact]
    public void CalculateUsesRiskBudgetAndStopDistance()
    {
        var quantity = PositionSizer.Calculate(10_000m, 1m, 100m, 95m, 0.10m, 0.15m);
        Assert.Equal(19.04761904m, quantity.Value);
    }

    [Fact]
    public void CalculateReturnsZeroWhenStopDistanceIsInvalid()
    {
        var quantity = PositionSizer.Calculate(10_000m, 1m, 100m, 100m, 0m, 0m);
        Assert.Equal(0m, quantity.Value);
    }
}
