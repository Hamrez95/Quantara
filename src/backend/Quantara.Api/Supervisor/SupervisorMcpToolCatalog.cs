namespace Quantara.Api.Supervisor;

public static class SupervisorMcpToolCatalog
{
    public const int DefaultResultLimit = 25;
    public const int MaximumResultLimit = 50;

    public static IReadOnlyList<string> Names { get; } =
    [
        "get_system_health",
        "get_runtime_state",
        "get_strategy_scorecard",
        "get_trade_lifecycle",
        "get_journal_consistency",
        "get_recent_anomalies",
        "get_build_and_ci_state",
        "get_config_summary_non_secret",
        "get_evidence_by_id"
    ];

    public static object[] Definitions() =>
    [
        Tool("get_system_health", "Current sanitized Quantara system and support-session health."),
        Tool("get_runtime_state", "Recent runtime lifecycle and scanner evidence."),
        Tool("get_strategy_scorecard", "Recent strategy evidence and scorecard observations."),
        Tool(
            "get_trade_lifecycle",
            "Correlated runtime/risk/journal lifecycle evidence for a trade or scan.",
            new Dictionary<string, object>
            {
                ["correlationId"] = new { type = "string" },
                ["maxResults"] = LimitSchema()
            }),
        Tool("get_journal_consistency", "Recent trading journal and lifecycle consistency evidence."),
        Tool("get_recent_anomalies", "Recent warning/error/critical evidence across Quantara."),
        Tool("get_build_and_ci_state", "Build, CI and test evidence visible to the Supervisor."),
        Tool("get_config_summary_non_secret", "Non-secret Quantara configuration evidence."),
        Tool(
            "get_evidence_by_id",
            "Fetch one sanitized evidence record by stable evidence id.",
            new Dictionary<string, object>
            {
                ["evidenceId"] = new { type = "string" }
            },
            ["evidenceId"])
    ];

    private static object Tool(
        string name,
        string description,
        IReadOnlyDictionary<string, object>? properties = null,
        string[]? required = null) =>
        new
        {
            name,
            description,
            inputSchema = new
            {
                type = "object",
                additionalProperties = false,
                properties = properties ?? new Dictionary<string, object>
                {
                    ["maxResults"] = LimitSchema()
                },
                required = required ?? Array.Empty<string>()
            }
        };

    private static object LimitSchema() => new
    {
        type = "integer",
        minimum = 1,
        maximum = MaximumResultLimit
    };
}
