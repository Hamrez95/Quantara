using Quantara.Api.Cockpit;

namespace Quantara.Domain.Tests;

public sealed class CockpitSnapshotProviderTests
{
    [Fact]
    public void CreatesVersionedSnapshot()
    {
        var timestamp = new DateTimeOffset(2026, 7, 20, 17, 0, 0, TimeSpan.Zero);
        var snapshot = new DeterministicCockpitSnapshotProvider().Create(timestamp);

        Assert.Equal("cockpit-v1", snapshot.SchemaVersion);
        Assert.Equal("demo", snapshot.Environment);
        Assert.Equal(timestamp, snapshot.GeneratedAt);
    }
}
