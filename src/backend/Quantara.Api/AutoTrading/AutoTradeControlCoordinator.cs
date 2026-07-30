using Quantara.Domain.AutoTrading;

namespace Quantara.Api.AutoTrading;

public sealed record AutoTradeStartContract(
    string RequestId,
    string ConfigurationVersion,
    IReadOnlyList<string> AllowedSymbols,
    IReadOnlyList<string> AllowedStrategies,
    IReadOnlyList<string> AllowedTimeframes,
    int GlobalLeverage,
    decimal RiskPerTradePercent,
    decimal MaximumDailyLossPercent,
    decimal MaximumWeeklyLossPercent,
    int MaximumConcurrentPositions,
    decimal MaximumMarginUsagePercent,
    decimal MaximumCorrelatedExposurePercent,
    decimal MaximumSlippagePercent,
    int MaximumSignalAgeSeconds,
    bool RequireIsolatedMargin,
    AutoTradeStopPolicy DefaultStopPolicy);

public sealed record AutoTradeStopContract(
    string RequestId,
    AutoTradeStopPolicy Policy,
    bool HasOpenPositionsOrOrders,
    string Reason);

public sealed record AutoTradePreflightResult(
    bool IsApproved,
    IReadOnlyList<string> Errors);

public interface IAutoTradeExecutionCapability
{
    bool IsLiveExecutionAvailable { get; }
}

public interface IAutoTradePreflightService
{
    Task<AutoTradePreflightResult> EvaluateAsync(
        AutoTradeRunConfiguration configuration,
        CancellationToken cancellationToken);
}

public interface IAutoTradeControlCoordinator
{
    AutoTradeRunSnapshot GetSnapshot();

    Task<AutoTradeTransitionResult> StartAsync(
        AutoTradeStartContract request,
        CancellationToken cancellationToken);

    Task<AutoTradeTransitionResult> StopAsync(
        AutoTradeStopContract request,
        CancellationToken cancellationToken);

    Task<AutoTradeTransitionResult> TripCircuitBreakerAsync(
        string requestId,
        string reason,
        CancellationToken cancellationToken);
}

public sealed class ConfigurationAutoTradePreflightService(
    IConfiguration serverConfiguration,
    IAutoTradeExecutionCapability capability)
    : IAutoTradePreflightService
{
    public Task<AutoTradePreflightResult> EvaluateAsync(
        AutoTradeRunConfiguration configuration,
        CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var errors = new List<string>(configuration.Validate());
        if (!serverConfiguration.GetValue("QUANTARA_LIVE_EXECUTION_ENABLED", false))
        {
            errors.Add("Server live-execution feature flag is disabled.");
        }

        if (!capability.IsLiveExecutionAvailable)
        {
            errors.Add("A reconciled live Bitunix execution cycle is not registered.");
        }

        var token = serverConfiguration["QUANTARA_CONTROL_TOKEN"];
        if (string.IsNullOrWhiteSpace(token) || token.Length < 32)
        {
            errors.Add("A strong server control token is not configured.");
        }

        return Task.FromResult(
            new AutoTradePreflightResult(errors.Count == 0, errors.AsReadOnly()));
    }
}

public sealed class DisabledAutoTradeExecutionCapability : IAutoTradeExecutionCapability
{
    public bool IsLiveExecutionAvailable => false;
}

public sealed class InMemoryAutoTradeControlCoordinator : IAutoTradeControlCoordinator, IDisposable
{
    private readonly SemaphoreSlim _mutex = new(1, 1);
    private readonly AutoTradeRunAggregate _aggregate;
    private readonly IAutoTradePreflightService _preflight;
    private readonly TimeProvider _timeProvider;
    private bool _disposed;

    public InMemoryAutoTradeControlCoordinator(
        IAutoTradePreflightService preflight,
        TimeProvider timeProvider)
    {
        _preflight = preflight;
        _timeProvider = timeProvider;
        _aggregate = AutoTradeRunAggregate.Create(
            "owner-default",
            timeProvider.GetUtcNow());
    }

    public AutoTradeRunSnapshot GetSnapshot() => _aggregate.Snapshot;

    public async Task<AutoTradeTransitionResult> StartAsync(
        AutoTradeStartContract request,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(request);
        var configuration = MapConfiguration(request);
        var validationErrors = configuration.Validate();
        if (validationErrors.Count > 0)
        {
            return new AutoTradeTransitionResult(
                AutoTradeTransitionCode.InvalidConfiguration,
                GetSnapshot(),
                validationErrors);
        }

        var preflight = await _preflight
            .EvaluateAsync(configuration, cancellationToken)
            .ConfigureAwait(false);
        if (!preflight.IsApproved)
        {
            return new AutoTradeTransitionResult(
                AutoTradeTransitionCode.InvalidConfiguration,
                GetSnapshot(),
                preflight.Errors);
        }

        await _mutex.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            ThrowIfDisposed();
            return _aggregate.Start(
                request.RequestId,
                configuration,
                _timeProvider.GetUtcNow());
        }
        finally
        {
            _mutex.Release();
        }
    }

    public async Task<AutoTradeTransitionResult> StopAsync(
        AutoTradeStopContract request,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(request);
        await _mutex.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            ThrowIfDisposed();
            return _aggregate.Stop(
                request.RequestId,
                request.Policy,
                request.HasOpenPositionsOrOrders,
                request.Reason,
                _timeProvider.GetUtcNow());
        }
        finally
        {
            _mutex.Release();
        }
    }

    public async Task<AutoTradeTransitionResult> TripCircuitBreakerAsync(
        string requestId,
        string reason,
        CancellationToken cancellationToken)
    {
        await _mutex.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            ThrowIfDisposed();
            return _aggregate.TripCircuitBreaker(
                requestId,
                reason,
                _timeProvider.GetUtcNow());
        }
        finally
        {
            _mutex.Release();
        }
    }

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }

        _mutex.Dispose();
        _disposed = true;
    }

    private static AutoTradeRunConfiguration MapConfiguration(AutoTradeStartContract request) =>
        new(
            request.ConfigurationVersion,
            NormalizeSet(request.AllowedSymbols),
            NormalizeSet(request.AllowedStrategies),
            NormalizeSet(request.AllowedTimeframes),
            request.GlobalLeverage,
            request.RiskPerTradePercent,
            request.MaximumDailyLossPercent,
            request.MaximumWeeklyLossPercent,
            request.MaximumConcurrentPositions,
            request.MaximumMarginUsagePercent,
            request.MaximumCorrelatedExposurePercent,
            request.MaximumSlippagePercent,
            TimeSpan.FromSeconds(request.MaximumSignalAgeSeconds),
            request.RequireIsolatedMargin,
            request.DefaultStopPolicy);

    private static HashSet<string> NormalizeSet(IEnumerable<string> values) =>
        new(
            values
                .Where(value => !string.IsNullOrWhiteSpace(value))
                .Select(value => value.Trim().ToUpperInvariant()),
            StringComparer.Ordinal);

    private void ThrowIfDisposed()
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
    }
}
