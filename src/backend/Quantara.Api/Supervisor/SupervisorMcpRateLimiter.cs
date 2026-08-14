namespace Quantara.Api.Supervisor;

public sealed class SupervisorMcpRateLimiter
{
    public const int MaximumRequestsPerWindow = 60;
    public static readonly TimeSpan Window = TimeSpan.FromMinutes(1);

    private readonly object _sync = new();
    private readonly Dictionary<string, WindowCounter> _counters = new(StringComparer.Ordinal);
    private readonly TimeProvider _timeProvider;

    public SupervisorMcpRateLimiter(TimeProvider timeProvider)
    {
        _timeProvider = timeProvider;
    }

    public bool TryAcquire(string sessionId)
    {
        if (string.IsNullOrWhiteSpace(sessionId))
        {
            return false;
        }

        var now = _timeProvider.GetUtcNow();
        lock (_sync)
        {
            PurgeExpiredLocked(now);
            if (!_counters.TryGetValue(sessionId, out var counter))
            {
                _counters[sessionId] = new WindowCounter(now, 1);
                return true;
            }

            if (now - counter.StartedAtUtc >= Window)
            {
                _counters[sessionId] = new WindowCounter(now, 1);
                return true;
            }

            if (counter.Count >= MaximumRequestsPerWindow)
            {
                return false;
            }

            _counters[sessionId] = counter with { Count = counter.Count + 1 };
            return true;
        }
    }

    private void PurgeExpiredLocked(DateTimeOffset now)
    {
        foreach (var key in _counters
                     .Where(pair => now - pair.Value.StartedAtUtc >= Window)
                     .Select(pair => pair.Key)
                     .ToArray())
        {
            _counters.Remove(key);
        }
    }

    private sealed record WindowCounter(DateTimeOffset StartedAtUtc, int Count);
}
