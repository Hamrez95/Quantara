using System.Text.Json;
using Quantara.Api.Cockpit;

namespace Quantara.Domain.Tests;

public sealed class CockpitSnapshotProviderTests
{
    private static readonly DateTimeOffset Timestamp = new(
        2026,
        7,
        20,
        17,
        0,
        0,
        TimeSpan.Zero);

    [Fact]
    public void CreatesVersionedSnapshot()
    {
        var snapshot = new DeterministicCockpitSnapshotProvider().Create(Timestamp);

        Assert.Equal("cockpit-v1", snapshot.SchemaVersion);
        Assert.Equal("demo", snapshot.Environment);
        Assert.Equal("deterministic_demo", snapshot.DataSourceMode);
        Assert.Equal(Timestamp, snapshot.GeneratedAt);
        Assert.Equal("none", snapshot.Safety.ExecutionAuthority);
        Assert.False(snapshot.Safety.RealMoneyEnabled);
        Assert.False(snapshot.Safety.OrderSubmissionEnabled);
        Assert.False(snapshot.Safety.WithdrawalEnabled);
        Assert.True(snapshot.PaperAccount.IsSimulated);
    }

    [Fact]
    public void CreatesConsistentMarketAndAccountValues()
    {
        var snapshot = new DeterministicCockpitSnapshotProvider().Create(Timestamp);

        Assert.Equal(4, snapshot.Watchlist.Count);
        Assert.All(snapshot.Watchlist, quote =>
        {
            Assert.True(quote.Price > 0m);
            Assert.True(quote.SpreadBps >= 0m);
            Assert.True(quote.ObservedAt <= snapshot.GeneratedAt);
            Assert.True(quote.Sparkline.Count >= 2);
            Assert.All(quote.Sparkline, value => Assert.True(value > 0m));
        });
        Assert.Equal("no_trade", snapshot.Analysis.Decision);
        Assert.InRange(snapshot.Analysis.ConfidencePercent, 0, 100);
        Assert.Equal(
            snapshot.PaperAccount.Equity,
            snapshot.PaperAccount.AvailableBalance + snapshot.PaperAccount.UsedMargin);
        Assert.InRange(
            snapshot.PaperAccount.CurrentDailyRiskPercent,
            0m,
            snapshot.PaperAccount.MaximumDailyRiskPercent);
    }

    [Fact]
    public void SerializesCamelCaseJsonContract()
    {
        var snapshot = new DeterministicCockpitSnapshotProvider().Create(Timestamp);
        var json = JsonSerializer.Serialize(
            snapshot,
            new JsonSerializerOptions(JsonSerializerDefaults.Web));
        using var document = JsonDocument.Parse(json);
        var root = document.RootElement;

        Assert.Equal("cockpit-v1", root.GetProperty("schemaVersion").GetString());
        Assert.Equal(
            "none",
            root.GetProperty("safety").GetProperty("executionAuthority").GetString());
        Assert.Equal(JsonValueKind.Array, root.GetProperty("watchlist").ValueKind);
        Assert.Equal(
            "no_trade",
            root.GetProperty("analysis").GetProperty("decision").GetString());
    }
}
