using Quantara.Domain.Orders;

namespace Quantara.Infrastructure.Persistence;

public sealed class PersistedOrderEntity
{
    public string OrderId { get; set; } = string.Empty;

    public OrderState State { get; set; }

    public long Version { get; set; }

    public DateTimeOffset CreatedAt { get; set; }

    public DateTimeOffset UpdatedAt { get; set; }

    public ICollection<PersistedOrderEventEntity> Events { get; } =
        new List<PersistedOrderEventEntity>();
}

public sealed class PersistedOrderEventEntity
{
    public string EventId { get; set; } = string.Empty;

    public string OrderId { get; set; } = string.Empty;

    public OrderState TargetState { get; set; }

    public OrderEventApplicationCode ApplicationCode { get; set; }

    public OrderState PreviousState { get; set; }

    public OrderState CurrentState { get; set; }

    public DateTimeOffset OccurredAt { get; set; }

    public string Reason { get; set; } = string.Empty;

    public DateTimeOffset CreatedAt { get; set; }

    public PersistedOrderEntity Order { get; set; } = null!;
}

public sealed class PersistedRiskEvaluationEntity
{
    public string EvaluationId { get; set; } = string.Empty;

    public string ProposalId { get; set; } = string.Empty;

    public string PayloadHash { get; set; } = string.Empty;

    public string PayloadJson { get; set; } = string.Empty;

    public DateTimeOffset EvaluatedAt { get; set; }

    public string RiskPolicyVersion { get; set; } = string.Empty;

    public DateTimeOffset CreatedAt { get; set; }
}

public sealed class AuditEventEntity
{
    public long Sequence { get; set; }

    public Guid EventId { get; set; }

    public string AggregateType { get; set; } = string.Empty;

    public string AggregateId { get; set; } = string.Empty;

    public string EventType { get; set; } = string.Empty;

    public string PayloadJson { get; set; } = string.Empty;

    public DateTimeOffset OccurredAt { get; set; }
}
