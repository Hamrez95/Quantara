using Microsoft.EntityFrameworkCore;
using Npgsql;
using Quantara.Domain.Orders;
using Quantara.Domain.Persistence;
using Quantara.Domain.Risk;
using Quantara.Domain.Trading;
using Quantara.Infrastructure.Persistence;
using Testcontainers.PostgreSql;

namespace Quantara.Domain.Tests;

public sealed class PostgreSqlPersistenceTests : IAsyncLifetime
{
    private readonly PostgreSqlContainer _container =
        new PostgreSqlBuilder("postgres:16-alpine")
            .WithDatabase("quantara_tests")
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
    public async Task RestoresOrderStateAndIdempotencyAfterFreshContext()
    {
        const string orderId = "restart-order";
        var timestamp = new DateTimeOffset(
            2026,
            7,
            20,
            10,
            0,
            0,
            TimeSpan.Zero);
        var orderEvent = new OrderLifecycleEvent(
            "restart-event-1",
            OrderState.RiskApproved,
            timestamp,
            "Risk approved.");

        await using (var firstContext = CreateContext())
        {
            var store = new EfOrderStore(firstContext);
            Assert.True(await store.CreateAsync(orderId, timestamp, CancellationToken.None));
            var applied = await store.ApplyAsync(
                orderId,
                0,
                orderEvent,
                CancellationToken.None);
            Assert.Equal(OrderEventApplicationCode.Applied, applied.Code);
        }

        await using var restartedContext = CreateContext();
        var restartedStore = new EfOrderStore(restartedContext);
        var snapshot = await restartedStore.LoadAsync(orderId, CancellationToken.None);

        Assert.NotNull(snapshot);
        Assert.Equal(OrderState.RiskApproved, snapshot.State);
        Assert.Equal(1, snapshot.Version);
        Assert.Contains(orderEvent.EventId, snapshot.AppliedEventIds);

        var aggregate = OrderAggregate.Rehydrate(
            snapshot.OrderId,
            snapshot.State,
            snapshot.AppliedEventIds);
        var replay = aggregate.Apply(orderEvent);
        Assert.Equal(OrderEventApplicationCode.DuplicateIgnored, replay.Code);
    }

    [Fact]
    public async Task ReturnsConcurrencyConflictForStaleExpectedVersion()
    {
        const string orderId = "concurrency-order";
        var timestamp = DateTimeOffset.UtcNow;

        await using var context = CreateContext();
        var store = new EfOrderStore(context);
        Assert.True(await store.CreateAsync(orderId, timestamp, CancellationToken.None));

        var first = await store.ApplyAsync(
            orderId,
            0,
            new OrderLifecycleEvent(
                "concurrency-event-1",
                OrderState.RiskApproved,
                timestamp,
                "Risk approved."),
            CancellationToken.None);
        var stale = await store.ApplyAsync(
            orderId,
            0,
            new OrderLifecycleEvent(
                "concurrency-event-2",
                OrderState.Expired,
                timestamp,
                "Stale caller attempted expiry."),
            CancellationToken.None);

        Assert.Equal(OrderEventApplicationCode.Applied, first.Code);
        Assert.Equal(OrderEventApplicationCode.ConcurrencyConflict, stale.Code);
        var snapshot = await store.LoadAsync(orderId, CancellationToken.None);
        Assert.NotNull(snapshot);
        Assert.Equal(OrderState.RiskApproved, snapshot.State);
        Assert.Equal(1, snapshot.Version);
    }

    [Fact]
    public async Task PersistsInvalidTransitionWithoutChangingOrderVersion()
    {
        const string orderId = "invalid-transition-order";
        var timestamp = DateTimeOffset.UtcNow;
        var invalidEvent = new OrderLifecycleEvent(
            "invalid-transition-event",
            OrderState.Filled,
            timestamp,
            "Cannot fill directly from created.");

        await using var context = CreateContext();
        var store = new EfOrderStore(context);
        Assert.True(await store.CreateAsync(orderId, timestamp, CancellationToken.None));

        var invalid = await store.ApplyAsync(
            orderId,
            0,
            invalidEvent,
            CancellationToken.None);
        var replay = await store.ApplyAsync(
            orderId,
            0,
            invalidEvent,
            CancellationToken.None);
        var snapshot = await store.LoadAsync(orderId, CancellationToken.None);
        var auditCount = await context.AuditEvents
            .AsNoTracking()
            .CountAsync(
                auditEvent => auditEvent.AggregateType == "order"
                    && auditEvent.AggregateId == orderId);

        Assert.Equal(OrderEventApplicationCode.InvalidTransition, invalid.Code);
        Assert.Equal(OrderEventApplicationCode.DuplicateIgnored, replay.Code);
        Assert.NotNull(snapshot);
        Assert.Equal(OrderState.Created, snapshot.State);
        Assert.Equal(0, snapshot.Version);
        Assert.Equal(2, auditCount);
    }

    [Fact]
    public async Task DetectsIdenticalAndConflictingRiskEvaluationDuplicates()
    {
        const string evaluationId = "risk-evaluation-1";
        const string proposalId = "proposal-1";
        var result = CreateRiskEvaluation();
        var createdAt = DateTimeOffset.UtcNow;

        await using (var firstContext = CreateContext())
        {
            var store = new EfRiskEvaluationStore(firstContext);
            var appended = await store.AppendAsync(
                evaluationId,
                proposalId,
                result,
                createdAt,
                CancellationToken.None);
            var duplicate = await store.AppendAsync(
                evaluationId,
                proposalId,
                result,
                createdAt,
                CancellationToken.None);
            var conflicting = await store.AppendAsync(
                evaluationId,
                proposalId,
                result with { RiskAmount = result.RiskAmount + 1m },
                createdAt,
                CancellationToken.None);

            Assert.Equal(RiskEvaluationAppendCode.Appended, appended.Code);
            Assert.Equal(RiskEvaluationAppendCode.DuplicateIgnored, duplicate.Code);
            Assert.Equal(RiskEvaluationAppendCode.ConflictingDuplicate, conflicting.Code);
        }

        await using var restartedContext = CreateContext();
        var restartedStore = new EfRiskEvaluationStore(restartedContext);
        var persisted = await restartedStore.GetAsync(
            evaluationId,
            CancellationToken.None);

        Assert.NotNull(persisted);
        Assert.Equal(proposalId, persisted.ProposalId);
        Assert.Equal(result.RiskAmount, persisted.Result.RiskAmount);
        Assert.Equal(result.NormalizedQuantity, persisted.Result.NormalizedQuantity);
        Assert.Equal(result.RiskPolicyVersion, persisted.Result.RiskPolicyVersion);
    }

    [Fact]
    public async Task ApplicationGuardRejectsAuditEventMutation()
    {
        const string orderId = "application-audit-guard-order";

        await using var context = CreateContext();
        var store = new EfOrderStore(context);
        Assert.True(await store.CreateAsync(
            orderId,
            DateTimeOffset.UtcNow,
            CancellationToken.None));

        var auditEvent = await context.AuditEvents
            .SingleAsync(audit => audit.AggregateId == orderId);
        auditEvent.EventType = "tampered";

        await Assert.ThrowsAsync<InvalidOperationException>(
            () => context.SaveChangesAsync());
    }

    [Fact]
    public async Task DatabaseTriggerRejectsDirectAuditEventDeletion()
    {
        const string orderId = "database-audit-guard-order";

        await using var context = CreateContext();
        var store = new EfOrderStore(context);
        Assert.True(await store.CreateAsync(
            orderId,
            DateTimeOffset.UtcNow,
            CancellationToken.None));
        context.ChangeTracker.Clear();

        var exception = await Assert.ThrowsAsync<PostgresException>(
            () => context.Database.ExecuteSqlRawAsync(
                "DELETE FROM audit_events WHERE aggregate_id = {0}",
                orderId));

        Assert.Equal("P0001", exception.SqlState);
    }

    [Fact]
    public async Task EfConcurrencyTokenRejectsCompetingOrderUpdates()
    {
        const string orderId = "ef-concurrency-order";

        await using (var creationContext = CreateContext())
        {
            var store = new EfOrderStore(creationContext);
            Assert.True(await store.CreateAsync(
                orderId,
                DateTimeOffset.UtcNow,
                CancellationToken.None));
        }

        await using var firstContext = CreateContext();
        await using var secondContext = CreateContext();
        var first = await firstContext.Orders.SingleAsync(
            order => order.OrderId == orderId);
        var second = await secondContext.Orders.SingleAsync(
            order => order.OrderId == orderId);

        first.State = OrderState.RiskApproved;
        first.Version++;
        second.State = OrderState.Expired;
        second.Version++;

        await firstContext.SaveChangesAsync();
        await Assert.ThrowsAsync<DbUpdateConcurrencyException>(
            () => secondContext.SaveChangesAsync());
    }

    private QuantaraDbContext CreateContext()
    {
        var options = new DbContextOptionsBuilder<QuantaraDbContext>()
            .UseNpgsql(_container.GetConnectionString())
            .Options;
        return new QuantaraDbContext(options);
    }

    private static RiskEvaluationResult CreateRiskEvaluation()
    {
        var request = new RiskEvaluationRequest(
            new Symbol("BTCUSDT"),
            TradeDirection.Long,
            10_000m,
            5_000m,
            100m,
            95m,
            110m,
            1m,
            2m,
            0m,
            0m,
            0m,
            0,
            0m,
            0m,
            0m,
            0.05m,
            0.10m,
            0.10m,
            true,
            true,
            false,
            false,
            0,
            false,
            null,
            new DateTimeOffset(2026, 7, 20, 10, 0, 0, TimeSpan.Zero));
        var policy = new RiskPolicy(
            "risk-persistence-v1",
            1m,
            3m,
            6m,
            10m,
            10m,
            500m,
            200m,
            5,
            2m,
            0.20m,
            0.30m,
            3,
            50m,
            false,
            30m);
        var instrument = new InstrumentRiskRules(
            0.1m,
            0.001m,
            0.001m,
            100m,
            5m,
            1m,
            1,
            3,
            20m);

        return DeterministicRiskEngine.Evaluate(request, policy, instrument);
    }
}

