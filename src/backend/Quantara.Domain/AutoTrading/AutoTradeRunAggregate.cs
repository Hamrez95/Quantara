using System.Security.Cryptography;
using System.Text;

namespace Quantara.Domain.AutoTrading;

public sealed class AutoTradeRunAggregate
{
    private readonly Dictionary<string, string> _requestSignatures = new(StringComparer.Ordinal);

    private AutoTradeRunAggregate(string runId, DateTimeOffset createdAt)
    {
        if (string.IsNullOrWhiteSpace(runId))
        {
            throw new ArgumentException("Run ID is required.", nameof(runId));
        }

        Snapshot = new AutoTradeRunSnapshot(
            runId.Trim(),
            AutoTradeRunState.Disarmed,
            0,
            null,
            null,
            null,
            null,
            string.Empty,
            string.Empty,
            createdAt.ToUniversalTime());
    }

    public AutoTradeRunSnapshot Snapshot { get; private set; }

    public static AutoTradeRunAggregate Create(string runId, DateTimeOffset createdAt) =>
        new(runId, createdAt);

    public AutoTradeTransitionResult Start(
        string requestId,
        AutoTradeRunConfiguration configuration,
        DateTimeOffset occurredAt)
    {
        ArgumentNullException.ThrowIfNull(configuration);
        var signature = Signature("start", configuration);
        var duplicate = CheckDuplicate(requestId, signature);
        if (duplicate is not null)
        {
            return duplicate.Value
                ? Result(AutoTradeTransitionCode.AlreadyStarted)
                : Result(AutoTradeTransitionCode.ConflictingRequest, ["Request ID was reused with different start content."]);
        }

        var errors = configuration.Validate();
        if (errors.Count > 0)
        {
            Remember(requestId, signature);
            return Result(AutoTradeTransitionCode.InvalidConfiguration, errors);
        }

        if (Snapshot.State == AutoTradeRunState.Armed)
        {
            Remember(requestId, signature);
            return Result(AutoTradeTransitionCode.AlreadyStarted);
        }

        if (Snapshot.State != AutoTradeRunState.Disarmed)
        {
            Remember(requestId, signature);
            return Result(
                AutoTradeTransitionCode.InvalidTransition,
                [$"Cannot start auto trade while state is {Snapshot.State}."]);
        }

        Remember(requestId, signature);
        var at = occurredAt.ToUniversalTime();
        Snapshot = Snapshot with
        {
            State = AutoTradeRunState.Armed,
            Version = Snapshot.Version + 1,
            Configuration = configuration,
            StartedAt = at,
            StoppedAt = null,
            LastStopPolicy = null,
            LastReason = "Auto trading armed after preflight approval.",
            LastRequestId = requestId.Trim(),
            UpdatedAt = at
        };
        return Result(AutoTradeTransitionCode.Started);
    }

    public AutoTradeTransitionResult Stop(
        string requestId,
        AutoTradeStopPolicy policy,
        bool hasOpenPositionsOrOrders,
        string reason,
        DateTimeOffset occurredAt)
    {
        var normalizedReason = string.IsNullOrWhiteSpace(reason)
            ? "Auto trading stopped by the operator."
            : reason.Trim();
        var signature = Signature(
            "stop",
            $"{policy}|{hasOpenPositionsOrOrders}|{normalizedReason}");
        var duplicate = CheckDuplicate(requestId, signature);
        if (duplicate is not null)
        {
            return duplicate.Value
                ? Result(AutoTradeTransitionCode.AlreadyStopped)
                : Result(AutoTradeTransitionCode.ConflictingRequest, ["Request ID was reused with different stop content."]);
        }

        if (Snapshot.State == AutoTradeRunState.Disarmed)
        {
            Remember(requestId, signature);
            return Result(AutoTradeTransitionCode.AlreadyStopped);
        }

        if (Snapshot.State is AutoTradeRunState.Arming or AutoTradeRunState.Stopping)
        {
            Remember(requestId, signature);
            return Result(
                AutoTradeTransitionCode.InvalidTransition,
                [$"Cannot stop auto trade while state is {Snapshot.State}."]);
        }

        Remember(requestId, signature);
        var at = occurredAt.ToUniversalTime();
        var nextState = policy == AutoTradeStopPolicy.ProtectAndManage && hasOpenPositionsOrOrders
            ? AutoTradeRunState.ManagingExistingPositions
            : AutoTradeRunState.Disarmed;
        Snapshot = Snapshot with
        {
            State = nextState,
            Version = Snapshot.Version + 1,
            StoppedAt = at,
            LastStopPolicy = policy,
            LastReason = normalizedReason,
            LastRequestId = requestId.Trim(),
            UpdatedAt = at
        };
        return Result(AutoTradeTransitionCode.Stopped);
    }

    public AutoTradeTransitionResult CompleteExistingPositionManagement(
        string requestId,
        string reason,
        DateTimeOffset occurredAt)
    {
        var normalizedReason = string.IsNullOrWhiteSpace(reason)
            ? "All Quantara-owned positions and orders reached a terminal state."
            : reason.Trim();
        var signature = Signature("complete-management", normalizedReason);
        var duplicate = CheckDuplicate(requestId, signature);
        if (duplicate is not null)
        {
            return duplicate.Value
                ? Result(AutoTradeTransitionCode.AlreadyStopped)
                : Result(AutoTradeTransitionCode.ConflictingRequest, ["Request ID was reused with different completion content."]);
        }

        if (Snapshot.State == AutoTradeRunState.Disarmed)
        {
            Remember(requestId, signature);
            return Result(AutoTradeTransitionCode.AlreadyStopped);
        }

        if (Snapshot.State != AutoTradeRunState.ManagingExistingPositions)
        {
            Remember(requestId, signature);
            return Result(
                AutoTradeTransitionCode.InvalidTransition,
                ["Existing-position management can complete only from ManagingExistingPositions."]);
        }

        Remember(requestId, signature);
        var at = occurredAt.ToUniversalTime();
        Snapshot = Snapshot with
        {
            State = AutoTradeRunState.Disarmed,
            Version = Snapshot.Version + 1,
            LastReason = normalizedReason,
            LastRequestId = requestId.Trim(),
            UpdatedAt = at
        };
        return Result(AutoTradeTransitionCode.Stopped);
    }

    public AutoTradeTransitionResult TripCircuitBreaker(
        string requestId,
        string reason,
        DateTimeOffset occurredAt)
    {
        var normalizedReason = string.IsNullOrWhiteSpace(reason)
            ? "A fail-closed circuit breaker was activated."
            : reason.Trim();
        var signature = Signature("circuit-breaker", normalizedReason);
        var duplicate = CheckDuplicate(requestId, signature);
        if (duplicate is not null)
        {
            return duplicate.Value
                ? Result(AutoTradeTransitionCode.CircuitBreakerTripped)
                : Result(AutoTradeTransitionCode.ConflictingRequest, ["Request ID was reused with different circuit-breaker content."]);
        }

        Remember(requestId, signature);
        var at = occurredAt.ToUniversalTime();
        Snapshot = Snapshot with
        {
            State = AutoTradeRunState.CircuitBreaker,
            Version = Snapshot.Version + 1,
            LastReason = normalizedReason,
            LastRequestId = requestId.Trim(),
            UpdatedAt = at
        };
        return Result(AutoTradeTransitionCode.CircuitBreakerTripped);
    }

    private AutoTradeTransitionResult Result(
        AutoTradeTransitionCode code,
        IReadOnlyList<string>? errors = null) =>
        new(code, Snapshot, errors ?? Array.Empty<string>());

    private bool? CheckDuplicate(string requestId, string signature)
    {
        ValidateRequestId(requestId);
        return _requestSignatures.TryGetValue(requestId.Trim(), out var previous)
            ? string.Equals(previous, signature, StringComparison.Ordinal)
            : null;
    }

    private void Remember(string requestId, string signature) =>
        _requestSignatures[requestId.Trim()] = signature;

    private static void ValidateRequestId(string requestId)
    {
        if (string.IsNullOrWhiteSpace(requestId) || requestId.Trim().Length > 128)
        {
            throw new ArgumentException(
                "Request ID is required and must be at most 128 characters.",
                nameof(requestId));
        }
    }

    private static string Signature(string action, AutoTradeRunConfiguration configuration)
    {
        var canonical = string.Join(
            '|',
            action,
            configuration.ConfigurationVersion.Trim(),
            string.Join(',', configuration.AllowedSymbols.Order(StringComparer.Ordinal)),
            string.Join(',', configuration.AllowedStrategies.Order(StringComparer.Ordinal)),
            string.Join(',', configuration.AllowedTimeframes.Order(StringComparer.Ordinal)),
            configuration.GlobalLeverage,
            configuration.RiskPerTradePercent,
            configuration.MaximumDailyLossPercent,
            configuration.MaximumWeeklyLossPercent,
            configuration.MaximumConcurrentPositions,
            configuration.MaximumMarginUsagePercent,
            configuration.MaximumCorrelatedExposurePercent,
            configuration.MaximumSlippagePercent,
            configuration.MaximumSignalAge.Ticks,
            configuration.RequireIsolatedMargin,
            configuration.DefaultStopPolicy);
        return Signature(action, canonical);
    }

    private static string Signature(string action, string content)
    {
        var bytes = SHA256.HashData(Encoding.UTF8.GetBytes($"{action}|{content}"));
        return Convert.ToHexString(bytes);
    }
}
