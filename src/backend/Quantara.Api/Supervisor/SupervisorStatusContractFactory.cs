namespace Quantara.Api.Supervisor;

public sealed record SupervisorStatusContract(
    bool Enabled,
    string Model,
    bool ReadOnly,
    bool LiveTradingMutation,
    bool CredentialExposure,
    bool SmokeTest,
    bool AnalysisAvailable);

public static class SupervisorStatusContractFactory
{
    private const string SmokeModeKey = "QUANTARA_SUPERVISOR_SMOKE_MODE";

    public static SupervisorStatusContract Create(
        IConfiguration configuration,
        string environmentName)
    {
        ArgumentNullException.ThrowIfNull(configuration);

        var openAiConfigured =
            !string.IsNullOrWhiteSpace(configuration["OPENAI_API_KEY"]);
        var smokeRequested = bool.TryParse(
            configuration[SmokeModeKey],
            out var parsedSmokeMode) && parsedSmokeMode;
        var smokeAllowed =
            smokeRequested && IsExplicitNonProductionEnvironment(environmentName);
        var smokeActive = !openAiConfigured && smokeAllowed;

        return new SupervisorStatusContract(
            Enabled: openAiConfigured || smokeActive,
            Model: smokeActive
                ? "mock-read-only"
                : configuration["QUANTARA_SUPERVISOR_OPENAI_MODEL"] ?? "gpt-5",
            ReadOnly: true,
            LiveTradingMutation: false,
            CredentialExposure: false,
            SmokeTest: smokeActive,
            AnalysisAvailable: openAiConfigured);
    }

    private static bool IsExplicitNonProductionEnvironment(string environmentName) =>
        string.Equals(environmentName, "Development", StringComparison.OrdinalIgnoreCase) ||
        string.Equals(environmentName, "Testing", StringComparison.OrdinalIgnoreCase) ||
        string.Equals(environmentName, "Staging", StringComparison.OrdinalIgnoreCase);
}
