using Microsoft.Extensions.Configuration;
using Quantara.Api.AutoTrading;
using Quantara.Domain.AutoTrading;

namespace Quantara.Domain.Tests.AutoTrading;

public sealed class AutoTradeControlCoordinatorTests
{
    [Fact]
    public async Task DisabledLiveFeatureRejectsArming()
    {
        var configuration = BuildConfiguration(liveEnabled: false);
        var preflight = new ConfigurationAutoTradePreflightService(
            configuration,
            new TestExecutionCapability(isAvailable: true));
        using var coordinator = new InMemoryAutoTradeControlCoordinator(
            preflight,
            new FixedTimeProvider());

        var result = await coordinator.StartAsync(
            ValidStartRequest(),
            CancellationToken.None);

        Assert.Equal(AutoTradeTransitionCode.InvalidConfiguration, result.Code);
        Assert.Equal(AutoTradeRunState.Disarmed, result.Snapshot.State);
        Assert.Contains(
            result.Errors,
            error => error.Contains("feature flag", StringComparison.OrdinalIgnoreCase));
    }

    [Fact]
    public async Task MissingExecutionCapabilityRejectsArming()
    {
        var configuration = BuildConfiguration(liveEnabled: true);
        var preflight = new ConfigurationAutoTradePreflightService(
            configuration,
            new TestExecutionCapability(isAvailable: false));
        using var coordinator = new InMemoryAutoTradeControlCoordinator(
            preflight,
            new FixedTimeProvider());

        var result = await coordinator.StartAsync(
            ValidStartRequest(),
            CancellationToken.None);

        Assert.Equal(AutoTradeRunState.Disarmed, result.Snapshot.State);
        Assert.Contains(
            result.Errors,
            error => error.Contains("execution cycle", StringComparison.OrdinalIgnoreCase));
    }

    [Fact]
    public async Task AllServerGatesPresentArmAndStopRun()
    {
        var configuration = BuildConfiguration(liveEnabled: true);
        var preflight = new ConfigurationAutoTradePreflightService(
            configuration,
            new TestExecutionCapability(isAvailable: true));
        using var coordinator = new InMemoryAutoTradeControlCoordinator(
            preflight,
            new FixedTimeProvider());

        var started = await coordinator.StartAsync(
            ValidStartRequest(),
            CancellationToken.None);
        var stopped = await coordinator.StopAsync(
            new AutoTradeStopContract(
                "stop-server-1",
                AutoTradeStopPolicy.ProtectAndManage,
                true,
                "Night session ended."),
            CancellationToken.None);

        Assert.Equal(AutoTradeTransitionCode.Started, started.Code);
        Assert.Equal(AutoTradeRunState.Armed, started.Snapshot.State);
        Assert.Equal(AutoTradeTransitionCode.Stopped, stopped.Code);
        Assert.Equal(AutoTradeRunState.ManagingExistingPositions, stopped.Snapshot.State);
        Assert.False(stopped.Snapshot.AllowsNewEntries);
    }

    private static IConfiguration BuildConfiguration(bool liveEnabled) =>
        new ConfigurationBuilder()
            .AddInMemoryCollection(
                new Dictionary<string, string?>
                {
                    ["QUANTARA_LIVE_EXECUTION_ENABLED"] = liveEnabled.ToString(),
                    ["QUANTARA_CONTROL_TOKEN"] =
                        "0123456789abcdef0123456789abcdef0123456789abcdef"
                })
            .Build();

    private static AutoTradeStartContract ValidStartRequest() =>
        new(
            "start-server-1",
            "restricted-live-v1",
            ["BTCUSDT", "ETHUSDT"],
            ["trend-pullback-v2"],
            ["1h", "4h"],
            10,
            0.5m,
            2m,
            5m,
            2,
            35m,
            50m,
            0.2m,
            1200,
            true,
            AutoTradeStopPolicy.ProtectAndManage);

    private sealed class TestExecutionCapability(bool isAvailable)
        : IAutoTradeExecutionCapability
    {
        public bool IsLiveExecutionAvailable { get; } = isAvailable;
    }

    private sealed class FixedTimeProvider : TimeProvider
    {
        public override DateTimeOffset GetUtcNow() =>
            new(2026, 7, 30, 13, 0, 0, TimeSpan.Zero);
    }
}
