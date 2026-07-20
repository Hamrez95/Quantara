using Microsoft.EntityFrameworkCore;
using Quantara.Domain.Orders;
using Quantara.Domain.Persistence;

namespace Quantara.Infrastructure.Persistence;

public sealed class EfOrderStore : IOrderStore
{
    private readonly QuantaraDbContext _dbContext;
    private readonly TimeProvider _timeProvider;

    public EfOrderStore(
        QuantaraDbContext dbContext,
        TimeProvider? timeProvider = null)
    {
        ArgumentNullException.ThrowIfNull(dbContext);
        _dbContext = dbContext;
        _timeProvider = timeProvider ?? TimeProvider.System;
    }

    public async Task<bool> CreateAsync(
        string orderId,
        DateTimeOffset createdAt,
        CancellationToken cancellationToken)
    {
        ValidateIdentifier(orderId, nameof(orderId));

        if (await _dbContext.Orders
            .AsNoTracking()
            .AnyAsync(order => order.OrderId == orderId, cancellationToken))
        {
            return false;
        }

        var timestamp = createdAt.ToUniversalTime();
        _dbContext.Orders.Add(new PersistedOrderEntity
        {
            OrderId = orderId,
            State = OrderState.Created,
            Version = 0,
            CreatedAt = timestamp,
            UpdatedAt = timestamp
        });
        _dbContext.AuditEvents.Add(CreateAuditEvent(
            "order",
            orderId,
            "order.created",
            new
            {
                orderId,
                state = OrderState.Created,
                version = 0
            },
            timestamp));

        try
        {
            await _dbContext.SaveChangesAsync(cancellationToken);
            return true;
        }
        catch (DbUpdateException)
        {
            _dbContext.ChangeTracker.Clear();
            if (await _dbContext.Orders
                .AsNoTracking()
                .AnyAsync(order => order.OrderId == orderId, cancellationToken))
            {
                return false;
            }

            throw;
        }
    }

    public async Task<PersistedOrderSnapshot?> LoadAsync(
        string orderId,
        CancellationToken cancellationToken)
    {
        ValidateIdentifier(orderId, nameof(orderId));

        var order = await _dbContext.Orders
            .AsNoTracking()
            .SingleOrDefaultAsync(
                candidate => candidate.OrderId == orderId,
                cancellationToken);
        if (order is null)
        {
            return null;
        }

        var appliedEventIds = await _dbContext.OrderEvents
            .AsNoTracking()
            .Where(orderEvent => orderEvent.OrderId == orderId
                && orderEvent.ApplicationCode == OrderEventApplicationCode.Applied)
            .Select(orderEvent => orderEvent.EventId)
            .ToListAsync(cancellationToken);

        return new PersistedOrderSnapshot(
            order.OrderId,
            order.State,
            order.Version,
            new HashSet<string>(appliedEventIds, StringComparer.Ordinal),
            order.CreatedAt,
            order.UpdatedAt);
    }

    public async Task<OrderEventApplicationResult> ApplyAsync(
        string orderId,
        long expectedVersion,
        OrderLifecycleEvent orderEvent,
        CancellationToken cancellationToken)
    {
        ValidateIdentifier(orderId, nameof(orderId));
        ArgumentOutOfRangeException.ThrowIfNegative(expectedVersion);
        ArgumentNullException.ThrowIfNull(orderEvent);
        ValidateIdentifier(orderEvent.EventId, nameof(orderEvent.EventId));

        if (orderEvent.Reason.Length > 1024)
        {
            throw new ArgumentException(
                "Order event reason cannot exceed 1024 characters.",
                nameof(orderEvent));
        }

        var existingEvent = await FindEventAsync(orderEvent.EventId, cancellationToken);
        if (existingEvent is not null)
        {
            return CreateDuplicateResult(existingEvent);
        }

        var order = await _dbContext.Orders
            .SingleOrDefaultAsync(
                candidate => candidate.OrderId == orderId,
                cancellationToken);
        if (order is null)
        {
            return new OrderEventApplicationResult(
                OrderEventApplicationCode.OrderNotFound,
                OrderState.Created,
                OrderState.Created,
                $"Order '{orderId}' does not exist.");
        }

        if (order.Version != expectedVersion)
        {
            return CreateConcurrencyResult(order.State, expectedVersion, order.Version);
        }

        var appliedEventIds = await _dbContext.OrderEvents
            .AsNoTracking()
            .Where(persistedEvent => persistedEvent.OrderId == orderId
                && persistedEvent.ApplicationCode == OrderEventApplicationCode.Applied)
            .Select(persistedEvent => persistedEvent.EventId)
            .ToListAsync(cancellationToken);
        var aggregate = OrderAggregate.Rehydrate(
            order.OrderId,
            order.State,
            appliedEventIds);
        var result = aggregate.Apply(orderEvent);
        var persistedAt = _timeProvider.GetUtcNow();

        _dbContext.OrderEvents.Add(new PersistedOrderEventEntity
        {
            EventId = orderEvent.EventId,
            OrderId = orderId,
            TargetState = orderEvent.TargetState,
            ApplicationCode = result.Code,
            PreviousState = result.PreviousState,
            CurrentState = result.CurrentState,
            OccurredAt = orderEvent.OccurredAt.ToUniversalTime(),
            Reason = orderEvent.Reason,
            CreatedAt = persistedAt
        });

        if (result.Code == OrderEventApplicationCode.Applied)
        {
            order.State = result.CurrentState;
            order.Version++;
            order.UpdatedAt = persistedAt;
        }

        _dbContext.AuditEvents.Add(CreateAuditEvent(
            "order",
            orderId,
            "order.lifecycle-event",
            new
            {
                orderEvent.EventId,
                targetState = orderEvent.TargetState,
                result.Code,
                result.PreviousState,
                result.CurrentState,
                expectedVersion,
                resultingVersion = order.Version,
                orderEvent.Reason
            },
            persistedAt));

        try
        {
            await _dbContext.SaveChangesAsync(cancellationToken);
            return result;
        }
        catch (DbUpdateConcurrencyException)
        {
            _dbContext.ChangeTracker.Clear();
            var currentState = await GetCurrentStateAsync(orderId, cancellationToken)
                ?? result.PreviousState;
            return CreateConcurrencyResult(currentState, expectedVersion, null);
        }
        catch (DbUpdateException)
        {
            _dbContext.ChangeTracker.Clear();
            existingEvent = await FindEventAsync(orderEvent.EventId, cancellationToken);
            if (existingEvent is not null)
            {
                return CreateDuplicateResult(existingEvent);
            }

            throw;
        }
    }

    private async Task<PersistedOrderEventEntity?> FindEventAsync(
        string eventId,
        CancellationToken cancellationToken)
    {
        return await _dbContext.OrderEvents
            .AsNoTracking()
            .SingleOrDefaultAsync(
                orderEvent => orderEvent.EventId == eventId,
                cancellationToken);
    }

    private async Task<OrderState?> GetCurrentStateAsync(
        string orderId,
        CancellationToken cancellationToken)
    {
        return await _dbContext.Orders
            .AsNoTracking()
            .Where(order => order.OrderId == orderId)
            .Select(order => (OrderState?)order.State)
            .SingleOrDefaultAsync(cancellationToken);
    }

    private static OrderEventApplicationResult CreateDuplicateResult(
        PersistedOrderEventEntity existingEvent)
    {
        return new OrderEventApplicationResult(
            OrderEventApplicationCode.DuplicateIgnored,
            existingEvent.PreviousState,
            existingEvent.CurrentState,
            "The event identifier already exists and was ignored idempotently.");
    }

    private static OrderEventApplicationResult CreateConcurrencyResult(
        OrderState currentState,
        long expectedVersion,
        long? actualVersion)
    {
        var actualVersionText = actualVersion?.ToString(
            System.Globalization.CultureInfo.InvariantCulture)
            ?? "unknown";
        return new OrderEventApplicationResult(
            OrderEventApplicationCode.ConcurrencyConflict,
            currentState,
            currentState,
            $"Expected order version {expectedVersion}, but the current version is {actualVersionText}.");
    }

    private static AuditEventEntity CreateAuditEvent<T>(
        string aggregateType,
        string aggregateId,
        string eventType,
        T payload,
        DateTimeOffset occurredAt)
    {
        return new AuditEventEntity
        {
            EventId = Guid.NewGuid(),
            AggregateType = aggregateType,
            AggregateId = aggregateId,
            EventType = eventType,
            PayloadJson = PersistenceJson.Serialize(payload),
            OccurredAt = occurredAt.ToUniversalTime()
        };
    }

    private static void ValidateIdentifier(string value, string parameterName)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(value, parameterName);
        if (value.Length > 128)
        {
            throw new ArgumentException(
                "Identifier cannot exceed 128 characters.",
                parameterName);
        }
    }
}
