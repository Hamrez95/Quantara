using Quantara.Domain.AutoTrading;

namespace Quantara.Domain.Tests.AutoTrading;

public sealed class AutoTradeRunAggregateTests
{
    private static readonly DateTimeOffset BaseTime =
        new(2026, 7, 30, 12, 0, 0, TimeSpan.Zero);

    [Fact]
    public void Start_ValidConfiguration_ArmsRunAndAllowsNewEntries()
    {
        var aggregate = AutoTradeRunAggregate.Create("owner-run", BaseTime);

        var result = aggregate.Start("start-1", ValidConfiguration(), BaseTime.AddMinutes(1));

        Assert.Equal(AutoTradeTransitionCode.Started, result.Code);
        Assert.True(result.IsSuccess);
        Assert.Equal(AutoTradeRunState.Armed, result.Snapshot.State);
        Assert.True(result.Snapshot.AllowsNewEntries);
        Assert.Equal(10, result.Snapshot.Configuration?.GlobalLeverage);
        Assert.Equal(1, result.Snapshot.Version);
    }

    [Fact]
    public void Start_DuplicateRequest_IsIdempotentWithoutVersionChange()
    {
        var aggregate = AutoTradeRunAggregate.Create("owner-run", BaseTime);
        var configuration = ValidConfiguration();
        aggregate.Start("start-1", configuration, BaseTime.AddMinutes(1));

        var duplicate = aggregate.Start("start-1", configuration, BaseTime.AddMinutes(2));

        Assert.Equal(AutoTradeTransitionCode.AlreadyStarted, duplicate.Code);
        Assert.Equal(1, duplicate.Snapshot.Version);
    }

    [Fact]
    public void Start_ReusedRequestWithDifferentConfiguration_FailsClosed()
    {
        var aggregate = AutoTradeRunAggregate.Create("owner-run", BaseTime);
        aggregate.Start("start-1", ValidConfiguration(), BaseTime.AddMinutes(1));
        var changed = ValidConfiguration() with { GlobalLeverage = 20 };

        var conflict = aggregate.Start("start-1", changed, BaseTime.AddMinutes(2));

        Assert.Equal(AutoTradeTransitionCode.ConflictingRequest, conflict.Code);
        Assert.False(conflict.IsSuccess);
        Assert.Equal(10, conflict.Snapshot.Configuration?.GlobalLeverage);
        Assert.Equal(1, conflict.Snapshot.Version);
    }

    [Fact]
    public void Start_InvalidLiveConfiguration_RemainsDisarmed()
    {
        var aggregate = AutoTradeRunAggregate.Create("owner-run", BaseTime);
        var invalid = ValidConfiguration() with
        {
            RiskPerTradePercent = 5m,
            RequireIsolatedMargin = false
        };

        var result = aggregate.Start("start-invalid", invalid, BaseTime.AddMinutes(1));

        Assert.Equal(AutoTradeTransitionCode.InvalidConfiguration, result.Code);
        Assert.False(result.IsSuccess);
        Assert.Equal(AutoTradeRunState.Disarmed, result.Snapshot.State);
        Assert.Contains(result.Errors, error => error.Contains("2%", StringComparison.Ordinal));
        Assert.Contains(result.Errors, error => error.Contains("isolated", StringComparison.OrdinalIgnoreCase));
    }

    [Fact]
    public void Stop_ProtectAndManageWithExposure_DisarmsNewEntriesButKeepsManagement()
    {
        var aggregate = AutoTradeRunAggregate.Create("owner-run", BaseTime);
        aggregate.Start("start-1", ValidConfiguration(), BaseTime.AddMinutes(1));

        var result = aggregate.Stop(
            "stop-1",
            AutoTradeStopPolicy.ProtectAndManage,
            hasOpenPositionsOrOrders: true,
            "Operator stopped overnight entries.",
            BaseTime.AddHours(1));

        Assert.Equal(AutoTradeTransitionCode.Stopped, result.Code);
        Assert.Equal(AutoTradeRunState.ManagingExistingPositions, result.Snapshot.State);
        Assert.False(result.Snapshot.AllowsNewEntries);
        Assert.True(result.Snapshot.RequiresExistingPositionManagement);
    }

    [Fact]
    public void Stop_EmergencyClose_DisarmsImmediately()
    {
        var aggregate = AutoTradeRunAggregate.Create("owner-run", BaseTime);
        aggregate.Start("start-1", ValidConfiguration(), BaseTime.AddMinutes(1));

        var result = aggregate.Stop(
            "stop-1",
            AutoTradeStopPolicy.EmergencyReduceOnlyClose,
            hasOpenPositionsOrOrders: true,
            "Emergency stop requested.",
            BaseTime.AddHours(1));

        Assert.Equal(AutoTradeRunState.Disarmed, result.Snapshot.State);
        Assert.False(result.Snapshot.RequiresExistingPositionManagement);
        Assert.Equal(AutoTradeStopPolicy.EmergencyReduceOnlyClose, result.Snapshot.LastStopPolicy);
    }

    [Fact]
    public void CircuitBreaker_FailsClosedAndBlocksRestart()
    {
        var aggregate = AutoTradeRunAggregate.Create("owner-run", BaseTime);
        aggregate.Start("start-1", ValidConfiguration(), BaseTime.AddMinutes(1));
        aggregate.TripCircuitBreaker(
            "breaker-1",
            "Private WebSocket reconciliation became stale.",
            BaseTime.AddMinutes(2));

        var restart = aggregate.Start("start-2", ValidConfiguration(), BaseTime.AddMinutes(3));

        Assert.Equal(AutoTradeRunState.CircuitBreaker, restart.Snapshot.State);
        Assert.Equal(AutoTradeTransitionCode.InvalidTransition, restart.Code);
        Assert.False(restart.Snapshot.AllowsNewEntries);
    }

    private static AutoTradeRunConfiguration ValidConfiguration() =>
        new(
            "restricted-live-v1",
            new HashSet<string>(StringComparer.Ordinal) { "BTCUSDT", "ETHUSDT" },
            new HashSet<string>(StringComparer.Ordinal) { "trend-pullback-v2" },
            new HashSet<string>(StringComparer.Ordinal) { "1h", "4h" },
            10,
            0.5m,
            2m,
            5m,
            2,
            35m,
            50m,
            0.2m,
            TimeSpan.FromMinutes(20),
            true,
            AutoTradeStopPolicy.ProtectAndManage);
}
