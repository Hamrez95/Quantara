namespace Quantara.Domain.AutoTrading;

public enum AutoTradeRunState
{
    Disarmed,
    Arming,
    Armed,
    Paused,
    CircuitBreaker,
    Stopping,
    ManagingExistingPositions
}

public enum AutoTradeStopPolicy
{
    ProtectAndManage,
    EmergencyReduceOnlyClose
}

public enum AutoTradeTransitionCode
{
    Started,
    AlreadyStarted,
    Stopped,
    AlreadyStopped,
    CircuitBreakerTripped,
    InvalidConfiguration,
    InvalidTransition,
    ConflictingRequest
}

public sealed record AutoTradeRunConfiguration(
    string ConfigurationVersion,
    IReadOnlySet<string> AllowedSymbols,
    IReadOnlySet<string> AllowedStrategies,
    IReadOnlySet<string> AllowedTimeframes,
    int GlobalLeverage,
    decimal RiskPerTradePercent,
    decimal MaximumDailyLossPercent,
    decimal MaximumWeeklyLossPercent,
    int MaximumConcurrentPositions,
    decimal MaximumMarginUsagePercent,
    decimal MaximumCorrelatedExposurePercent,
    decimal MaximumSlippagePercent,
    TimeSpan MaximumSignalAge,
    bool RequireIsolatedMargin,
    AutoTradeStopPolicy DefaultStopPolicy)
{
    public IReadOnlyList<string> Validate()
    {
        var errors = new List<string>();
        if (string.IsNullOrWhiteSpace(ConfigurationVersion))
        {
            errors.Add("Configuration version is required.");
        }

        ValidateSet(AllowedSymbols, "At least one symbol must be allowed.", errors);
        ValidateSet(AllowedStrategies, "At least one strategy must be allowed.", errors);
        ValidateSet(AllowedTimeframes, "At least one timeframe must be allowed.", errors);

        if (GlobalLeverage is < 1 or > 125)
        {
            errors.Add("Global leverage must be between 1 and 125.");
        }

        if (RiskPerTradePercent is <= 0m or > 2m)
        {
            errors.Add("Risk per trade must be greater than zero and no more than 2%.");
        }

        if (MaximumDailyLossPercent is <= 0m or > 10m)
        {
            errors.Add("Maximum daily loss must be greater than zero and no more than 10%.");
        }

        if (MaximumWeeklyLossPercent < MaximumDailyLossPercent || MaximumWeeklyLossPercent > 20m)
        {
            errors.Add("Maximum weekly loss must be at least the daily limit and no more than 20%.");
        }

        if (MaximumConcurrentPositions is < 1 or > 20)
        {
            errors.Add("Maximum concurrent positions must be between 1 and 20.");
        }

        if (MaximumMarginUsagePercent is <= 0m or > 80m)
        {
            errors.Add("Maximum margin usage must be greater than zero and no more than 80%.");
        }

        if (MaximumCorrelatedExposurePercent is <= 0m or > 100m)
        {
            errors.Add("Maximum correlated exposure must be greater than zero and no more than 100%.");
        }

        if (MaximumSlippagePercent is < 0m or > 5m)
        {
            errors.Add("Maximum slippage must be between zero and 5%.");
        }

        if (MaximumSignalAge <= TimeSpan.Zero || MaximumSignalAge > TimeSpan.FromHours(24))
        {
            errors.Add("Maximum signal age must be greater than zero and no more than 24 hours.");
        }

        if (!RequireIsolatedMargin)
        {
            errors.Add("Initial live automation requires isolated margin.");
        }

        return errors.AsReadOnly();
    }

    private static void ValidateSet(
        IReadOnlySet<string>? values,
        string message,
        ICollection<string> errors)
    {
        if (values is null || values.Count == 0 || values.Any(string.IsNullOrWhiteSpace))
        {
            errors.Add(message);
        }
    }
}

public sealed record AutoTradeRunSnapshot(
    string RunId,
    AutoTradeRunState State,
    long Version,
    AutoTradeRunConfiguration? Configuration,
    DateTimeOffset? StartedAt,
    DateTimeOffset? StoppedAt,
    AutoTradeStopPolicy? LastStopPolicy,
    string LastReason,
    string LastRequestId,
    DateTimeOffset UpdatedAt)
{
    public bool AllowsNewEntries => State == AutoTradeRunState.Armed;

    public bool RequiresExistingPositionManagement =>
        State is AutoTradeRunState.Armed or AutoTradeRunState.ManagingExistingPositions;
}

public sealed record AutoTradeTransitionResult(
    AutoTradeTransitionCode Code,
    AutoTradeRunSnapshot Snapshot,
    IReadOnlyList<string> Errors)
{
    public bool IsSuccess =>
        Code is AutoTradeTransitionCode.Started
            or AutoTradeTransitionCode.AlreadyStarted
            or AutoTradeTransitionCode.Stopped
            or AutoTradeTransitionCode.AlreadyStopped
            or AutoTradeTransitionCode.CircuitBreakerTripped;
}
