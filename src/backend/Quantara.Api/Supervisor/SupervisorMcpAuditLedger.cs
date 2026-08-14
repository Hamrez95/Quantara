namespace Quantara.Api.Supervisor;

public sealed record SupervisorMcpAuditEvent(
    DateTimeOffset OccurredAtUtc,
    string SessionId,
    string Operation,
    bool Succeeded,
    string AuditId);

public sealed class SupervisorMcpAuditLedger
{
    private const int MaximumEntries = 500;
    private readonly object _sync = new();
    private readonly Queue<SupervisorMcpAuditEvent> _events = new();

    public void Record(SupervisorMcpAuditEvent auditEvent)
    {
        lock (_sync)
        {
            _events.Enqueue(auditEvent);
            while (_events.Count > MaximumEntries)
            {
                _events.Dequeue();
            }
        }
    }

    public IReadOnlyList<SupervisorMcpAuditEvent> Snapshot()
    {
        lock (_sync)
        {
            return _events.ToArray();
        }
    }
}
