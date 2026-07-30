namespace Quantara.Infrastructure.Persistence;

public sealed class AutoTradeRunEntity
{
    public required string RunId { get; init; }

    public required string State { get; set; }

    public long Version { get; set; }

    public string? ConfigurationJson { get; set; }

    public DateTimeOffset? StartedAt { get; set; }

    public DateTimeOffset? StoppedAt { get; set; }

    public string? LastStopPolicy { get; set; }

    public required string LastReason { get; set; }

    public required string LastRequestId { get; set; }

    public DateTimeOffset UpdatedAt { get; set; }
}

public sealed class AutoTradeControlRequestEntity
{
    public Guid ControlRequestId { get; init; }

    public required string RunId { get; init; }

    public required string RequestId { get; init; }

    public required string Action { get; init; }

    public required string Fingerprint { get; init; }

    public required string ResultCode { get; init; }

    public required string SnapshotJson { get; init; }

    public required string ErrorsJson { get; init; }

    public DateTimeOffset CreatedAt { get; init; }
}

public sealed class AutoTradeExecutionAuditEntity
{
    public long Sequence { get; init; }

    public Guid EventId { get; init; }

    public required string RunId { get; init; }

    public required string EventType { get; init; }

    public required string PayloadJson { get; init; }

    public DateTimeOffset OccurredAt { get; init; }
}
