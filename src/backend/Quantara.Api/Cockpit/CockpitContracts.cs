namespace Quantara.Api.Cockpit;

public sealed record CockpitSafetyContract(
    string ExecutionAuthority,
    bool RealMoneyEnabled,
    bool OrderSubmissionEnabled,
    bool WithdrawalEnabled);

public sealed record CockpitQuoteContract(
    string Symbol,
    string DisplayName,
    decimal Price,
    decimal ChangePercent,
    decimal SpreadBps,
    DateTimeOffset ObservedAt,
    IReadOnlyList<decimal> Sparkline);

public sealed record CockpitAnalysisFactorContract(
    string Code,
    string Title,
    string Detail,
    string Impact);

public sealed record CockpitAnalysisContract(
    string Symbol,
    string Decision,
    int ConfidencePercent,
    string Regime,
    string Summary,
    string ReconsiderationCondition,
    DateTimeOffset GeneratedAt,
    IReadOnlyList<CockpitAnalysisFactorContract> Factors);

public sealed record CockpitPaperAccountContract(
    string Currency,
    bool IsSimulated,
    decimal Equity,
    decimal AvailableBalance,
    decimal UsedMargin,
    decimal DailyPnl,
    int OpenPositions,
    decimal MaximumDailyRiskPercent,
    decimal CurrentDailyRiskPercent);

public sealed record CockpitResponseContract(
    string SchemaVersion,
    string Language,
    DateTimeOffset GeneratedAt,
    string Environment,
    string DataSourceMode,
    string MarketStatusCode,
    string MarketStatus,
    CockpitSafetyContract Safety,
    IReadOnlyList<CockpitQuoteContract> Watchlist,
    CockpitAnalysisContract Analysis,
    CockpitPaperAccountContract PaperAccount);

public sealed record HealthResponseContract(
    string Status,
    string Service,
    DateTimeOffset GeneratedAt,
    string ExecutionAuthority,
    bool RealMoneyEnabled);
