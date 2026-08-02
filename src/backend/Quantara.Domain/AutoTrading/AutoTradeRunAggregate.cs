using System.Globalization;
using System.Security.Cryptography;
using System.Text;

namespace Quantara.Domain.AutoTrading;

public sealed class AutoTradeRunAggregate
{
    private readonly Dictionary<string, ProcessedRequest> _processedRequests =
        new(StringComparer.Ordinal);

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
        var duplicate = GetDuplicate(requestId, signature);
        if (duplicate is not null)
        {
            return duplicate.Code == AutoTradeTransitionCode.ConflictingRequest
                ? Result(duplicate.Code, ["Request ID was reused with different start content."])
                : Result(duplicate.Code, duplicate.Errors);
        }

        var errors = configuration.Validate();
        if (errors.Count > 0)
        {
            Remember(requestId, signature, AutoTradeTransitionCode.InvalidConfiguration, errors);
            return Result(AutoTradeTransitionCode.InvalidConfiguration, errors);
        }

        if (Snapshot.State == AutoTradeRunState.Armed)
        {
            Remember(requestId, signature, AutoTradeTransitionCode.AlreadyStarted);
            return Result(AutoTradeTransitionCode.AlreadyStarted);
        }

        if (Snapshot.State != AutoTradeRunState.Disarmed)
        {
            var transitionErrors = new[]
            {
                $"Cannot start auto trade while state is {Snapshot.State}."
            };
            Remember(
                requestId,
                signature,
                AutoTradeTransitionCode.InvalidTransition,
                transitionErrors);
            return Result(AutoTradeTransitionCode.InvalidTransition, transitionErrors);
        }

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
        Remember(requestId, signature, AutoTradeTransitionCode.AlreadyStarted);
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
        var duplicate = GetDuplicate(requestId, signature);
        if (duplicate is not null)
        {
            return duplicate.Code == AutoTradeTransitionCode.ConflictingRequest
                ? Result(duplicate.Code, ["Request ID was reused with different stop content."])
                : Result(duplicate.Code, duplicate.Errors);
        }

        if (Snapshot.State == AutoTradeRunState.Disarmed)
        {
            Remember(requestId, signature, AutoTradeTransitionCode.AlreadyStopped);
            return Result(AutoTradeTransitionCode.AlreadyStopped);
        }

        if (Snapshot.State is AutoTradeRunState.Arming or AutoTradeRunState.Stopping)
        {
            var transitionErrors = new[]
            {
                $"Cannot stop auto trade while state is {Snapshot.State}."
            };
            Remember(
                requestId,
                signature,
                AutoTradeTransitionCode.InvalidTransition,
                transitionErrors);
            return Result(AutoTradeTransitionCode.InvalidTransition, transitionErrors);
        }

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
        Remember(requestId, signature, AutoTradeTransitionCode.AlreadyStopped);
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
        var duplicate = GetDuplicate(requestId, signature);
        if (duplicate is not null)
        {
            return duplicate.Code == AutoTradeTransitionCode.ConflictingRequest
                ? Result(duplicate.Code, ["Request ID was reused with different completion content."])
                : Result(duplicate.Code, duplicate.Errors);
        }

        if (Snapshot.State == AutoTradeRunState.Disarmed)
        {
            Remember(requestId, signature, AutoTradeTransitionCode.AlreadyStopped);
            return Result(AutoTradeTransitionCode.AlreadyStopped);
        }

        if (Snapshot.State != AutoTradeRunState.ManagingExistingPositions)
        {
            var transitionErrors = new[]
            {
                "Existing-position management can complete only from ManagingExistingPositions."
            };
            Remember(
                requestId,
                signature,
                AutoTradeTransitionCode.InvalidTransition,
                transitionErrors);
            return Result(AutoTradeTransitionCode.InvalidTransition, transitionErrors);
        }

        var at = occurredAt.ToUniversalTime();
        Snapshot = Snapshot with
        {
            State = AutoTradeRunState.Disarmed,
            Version = Snapshot.Version + 1,
            LastReason = normalizedReason,
            LastRequestId = requestId.Trim(),
            UpdatedAt = at
        };
        Remember(requestId, signature, AutoTradeTransitionCode.AlreadyStopped);
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
        var duplicate = GetDuplicate(requestId, signature);
        if (duplicate is not null)
        {
            return duplicate.Code == AutoTradeTransitionCode.ConflictingRequest
                ? Result(duplicate.Code, ["Request ID was reused with different circuit-breaker content."])
                : Result(duplicate.Code, duplicate.Errors);
        }

        var at = occurredAt.ToUniversalTime();
        Snapshot = Snapshot with
        {
            State = AutoTradeRunState.CircuitBreaker,
            Version = Snapshot.Version + 1,
            LastReason = normalizedReason,
            LastRequestId = requestId.Trim(),
            UpdatedAt = at
        };
        Remember(requestId, signature, AutoTradeTransitionCode.CircuitBreakerTripped);
        return Result(AutoTradeTransitionCode.CircuitBreakerTripped);
    }

    private AutoTradeTransitionResult Result(
        AutoTradeTransitionCode code,
        IReadOnlyList<string>? errors = null) =>
        new(code, Snapshot, errors ?? Array.Empty<string>());

    private ProcessedRequest? GetDuplicate(string requestId, string signature)
    {
        ValidateRequestId(requestId);
        if (!_processedRequests.TryGetValue(requestId.Trim(), out var previous))
        {
            return null;
        }

        return string.Equals(previous.Signature, signature, StringComparison.Ordinal)
            ? previous
            : new ProcessedRequest(
                signature,
                AutoTradeTransitionCode.ConflictingRequest,
                Array.Empty<string>());
    }

    private void Remember(
        string requestId,
        string signature,
        AutoTradeTransitionCode duplicateCode,
        IReadOnlyList<string>? errors = null) =>
        _processedRequests[requestId.Trim()] = new ProcessedRequest(
            signature,
            duplicateCode,
            errors ?? Array.Empty<string>());

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
        var fields = new[]
        {
            action,
            configuration.ConfigurationVersion.Trim(),
            string.Join(',', configuration.AllowedSymbols.Order(StringComparer.Ordinal)),
            string.Join(',', configuration.AllowedStrategies.Order(StringComparer.Ordinal)),
            string.Join(',', configuration.AllowedTimeframes.Order(StringComparer.Ordinal)),
            configuration.GlobalLeverage.ToString(CultureInfo.InvariantCulture),
            configuration.RiskPerTradePercent.ToString(CultureInfo.InvariantCulture),
            configuration.MaximumDailyLossPercent.ToString(CultureInfo.InvariantCulture),
            configuration.MaximumWeeklyLossPercent.ToString(CultureInfo.InvariantCulture),
            configuration.MaximumConcurrentPositions.ToString(CultureInfo.InvariantCulture),
            configuration.MaximumMarginUsagePercent.ToString(CultureInfo.InvariantCulture),
            configuration.MaximumCorrelatedExposurePercent.ToString(CultureInfo.InvariantCulture),
            configuration.MaximumSlippagePercent.ToString(CultureInfo.InvariantCulture),
            configuration.MaximumSignalAge.Ticks.ToString(CultureInfo.InvariantCulture),
            configuration.RequireIsolatedMargin.ToString(CultureInfo.InvariantCulture),
            configuration.DefaultStopPolicy.ToString()
        };
        return Signature(action, string.Join('|', fields));
    }

    private static string Signature(string action, string content)
    {
        var bytes = SHA256.HashData(Encoding.UTF8.GetBytes($"{action}|{content}"));
        return Convert.ToHexString(bytes);
    }

    private sealed record ProcessedRequest(
        string Signature,
        AutoTradeTransitionCode Code,
        IReadOnlyList<string> Errors);
}
