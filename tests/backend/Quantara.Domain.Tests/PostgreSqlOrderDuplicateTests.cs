using Microsoft.EntityFrameworkCore;
using Quantara.Domain.Orders;
using Quantara.Infrastructure.Persistence;
using Testcontainers.PostgreSql;

namespace Quantara.Domain.Tests;

public sealed class PostgreSqlOrderDuplicateTests : IAsyncLifetime
{
    private readonly PostgreSqlContainer _container =
        new PostgreSqlBuilder("postgres:16-alpine")
            .WithDatabase("quantara_duplicate_tests")
            .WithUsername("quantara")
            .WithPassword("quantara_tests_only")
            .Build();

    public async Task InitializeAsync()
    {
        await _container.StartAsync();
        await using var context = CreateContext();
        await context.Database.MigrateAsync();
    }

    public async Task DisposeAsync()
    {
        await _container.DisposeAsync();
    }

    [Fact]
    public async Task DistinguishesIdenticalReplayFromConflictingDuplicate()
    {
        const string firstOrderId = "duplicate-first-order";
        const string secondOrderId = "duplicate-second-order";
        var occurredAt = new DateTimeOffset(
            2026,
            7,
            20,
            11,
            0,
            0,
            TimeSpan.Zero);
        var originalEvent = new OrderLifecycleEvent(
            "shared-event-id",
            OrderState.RiskApproved,
            occurredAt,
            "Risk approved.");

        await using var context = CreateContext();
        var store = new EfOrderStore(context);
        Assert.True(await store.CreateAsync(
            firstOrderId,
            occurredAt,
            CancellationToken.None));
        Assert.True(await store.CreateAsync(
            secondOrderId,
            occurredAt,
            CancellationToken.None));

        var applied = await store.ApplyAsync(
            firstOrderId,
            0,
            originalEvent,
            CancellationToken.None);
        var identicalReplay = await store.ApplyAsync(
            firstOrderId,
            0,
            originalEvent,
            CancellationToken.None);
        var changedPayload = await store.ApplyAsync(
            firstOrderId,
            0,
            originalEvent with { Reason = "Different reason." },
            CancellationToken.None);
        var differentOrder = await store.ApplyAsync(
            secondOrderId,
            0,
            originalEvent,
            CancellationToken.None);

        Assert.Equal(OrderEventApplicationCode.Applied, applied.Code);
        Assert.Equal(
            OrderEventApplicationCode.DuplicateIgnored,
            identicalReplay.Code);
        Assert.Equal(
            OrderEventApplicationCode.ConflictingDuplicate,
            changedPayload.Code);
        Assert.Equal(
            OrderEventApplicationCode.ConflictingDuplicate,
            differentOrder.Code);

        var secondSnapshot = await store.LoadAsync(
            secondOrderId,
            CancellationToken.None);
        Assert.NotNull(secondSnapshot);
        Assert.Equal(OrderState.Created, secondSnapshot.State);
        Assert.Equal(0, secondSnapshot.Version);
    }

    private QuantaraDbContext CreateContext()
    {
        var options = new DbContextOptionsBuilder<QuantaraDbContext>()
            .UseNpgsql(_container.GetConnectionString())
            .Options;
        return new QuantaraDbContext(options);
    }
}
