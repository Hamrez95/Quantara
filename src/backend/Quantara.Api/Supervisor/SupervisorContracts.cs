using System.Collections.ObjectModel;

namespace Quantara.Api.Supervisor;

public sealed record SupervisorEvidenceContract(
    string EvidenceId,
    string Domain,
    string Kind,
    DateTimeOffset ObservedAtUtc,
    string Summary,
    string Severity,
    string? Component,
    string? Version,
    string? CorrelationId,
    IReadOnlyDictionary<string, string>? Attributes);

public sealed record SupervisorAnalysisRequestContract(
    string BundleId,
    DateTimeOffset CapturedAtUtc,
    IReadOnlyList<SupervisorEvidenceContract> Evidence,
    string? ReviewGoal);

public sealed record SupervisorFactContract(
    string Statement,
    IReadOnlyList<string> EvidenceIds);

public sealed record SupervisorHypothesisContract(
    string Statement,
    double Confidence,
    IReadOnlyList<string> EvidenceIds);

public sealed record SupervisorAnomalyContract(
    string Statement,
    string Severity,
    IReadOnlyList<string> EvidenceIds);

public sealed record SupervisorStrategyFindingContract(
    string Statement,
    double Confidence,
    IReadOnlyList<string> EvidenceIds);

public sealed record SupervisorExperimentContract(
    string Title,
    string Rationale,
    IReadOnlyList<string> EvidenceIds,
    IReadOnlyList<string> ValidationTests,
    IReadOnlyList<string> RollbackCriteria);

public sealed record SupervisorUsageContract(
    int InputTokens,
    int OutputTokens,
    int TotalTokens,
    long LatencyMilliseconds);

public sealed record SupervisorReviewContract(
    string ReviewId,
    string Summary,
    IReadOnlyList<SupervisorFactContract> Facts,
    IReadOnlyList<SupervisorHypothesisContract> Hypotheses,
    IReadOnlyList<SupervisorAnomalyContract> Anomalies,
    IReadOnlyList<SupervisorStrategyFindingContract> StrategyFindings,
    IReadOnlyList<SupervisorExperimentContract> RecommendedExperiments,
    bool InsufficientEvidence,
    string InsufficientEvidenceReason,
    string AuditId,
    string Model,
    string PromptVersion = "quantara-supervisor-v1",
    SupervisorUsageContract? Usage = null);

public enum SupervisorAnalysisCode
{
    Completed,
    Unauthorized,
    InvalidEvidence,
    RateLimited,
    NotConfigured,
    UpstreamFailure,
    InvalidModelOutput
}

public sealed record SupervisorAnalysisResult(
    SupervisorAnalysisCode Code,
    SupervisorReviewContract? Review,
    string? Message,
    string AuditId)
{
    public static SupervisorAnalysisResult Fail(
        SupervisorAnalysisCode code,
        string auditId,
        string message) => new(code, null, message, auditId);
}

internal static class SupervisorContractCollections
{
    public static IReadOnlyDictionary<string, string> EmptyAttributes { get; } =
        new ReadOnlyDictionary<string, string>(new Dictionary<string, string>());
}
