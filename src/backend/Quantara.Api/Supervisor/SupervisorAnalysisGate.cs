namespace Quantara.Api.Supervisor;

public sealed class SupervisorAnalysisGate : IDisposable
{
    private readonly SemaphoreSlim _concurrency;
    private readonly object _sync = new();
    private readonly Queue<DateTimeOffset> _recentRequests = new();
    private readonly TimeProvider _timeProvider;
    private readonly int _maxRequestsPerMinute;
    private bool _disposed;

    public SupervisorAnalysisGate(
        TimeProvider timeProvider,
        IConfiguration configuration)
    {
        _timeProvider = timeProvider;
        _maxRequestsPerMinute = ParseBounded(
            configuration["QUANTARA_SUPERVISOR_REQUESTS_PER_MINUTE"],
            fallback: 6,
            minimum: 1,
            maximum: 60);
        var concurrency = ParseBounded(
            configuration["QUANTARA_SUPERVISOR_MAX_CONCURRENCY"],
            fallback: 2,
            minimum: 1,
            maximum: 8);
        _concurrency = new SemaphoreSlim(concurrency, concurrency);
    }

    public async ValueTask<SupervisorAnalysisLease?> TryAcquireAsync(
        CancellationToken cancellationToken)
    {
        ObjectDisposedException.ThrowIf(_disposed, this);

        var now = _timeProvider.GetUtcNow();
        lock (_sync)
        {
            var cutoff = now - TimeSpan.FromMinutes(1);
            while (_recentRequests.TryPeek(out var oldest) && oldest < cutoff)
            {
                _recentRequests.Dequeue();
            }

            if (_recentRequests.Count >= _maxRequestsPerMinute)
            {
                return null;
            }

            _recentRequests.Enqueue(now);
        }

        if (!await _concurrency.WaitAsync(TimeSpan.FromSeconds(1), cancellationToken)
            .ConfigureAwait(false))
        {
            return null;
        }

        return new SupervisorAnalysisLease(_concurrency);
    }

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }

        _disposed = true;
        _concurrency.Dispose();
        GC.SuppressFinalize(this);
    }

    private static int ParseBounded(
        string? raw,
        int fallback,
        int minimum,
        int maximum) =>
        int.TryParse(raw, out var parsed)
            ? Math.Clamp(parsed, minimum, maximum)
            : fallback;
}

public sealed class SupervisorAnalysisLease : IAsyncDisposable
{
    private SemaphoreSlim? _semaphore;

    internal SupervisorAnalysisLease(SemaphoreSlim semaphore)
    {
        _semaphore = semaphore;
    }

    public ValueTask DisposeAsync()
    {
        Interlocked.Exchange(ref _semaphore, null)?.Release();
        return ValueTask.CompletedTask;
    }
}
