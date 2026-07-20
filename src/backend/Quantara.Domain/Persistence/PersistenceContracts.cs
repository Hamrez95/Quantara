using Quantara.Domain.Orders;
using Quantara.Domain.Risk;

namespace Quantara.Domain.Persistence;

public sealed record PersistedOrderSnapshot(
    string OrderId,
    OrderState State,
    long Version,
    IReadOnlySet<string> AppliedEventIds,
    DateTimeOffset CreatedAt,
    DateTimeOffset UpdatedAt);

public interface IOrderStore
{
    Task<bool> CreateAsync(
        string orderId,
        DateTimeOffset createdAt,
        CancellationToken cancellationToken);

    Task<PersistedOrderSnapshot?> LoadAsync(
        string orderId,
        CancellationToken cancellationToken);

    Task<OrderEventApplicationResult> ApplyAsync(
        string orderId,
        long expectedVersion,
        OrderLifecycleEvent orderEvent,
        CancellationToken cancellationToken);
}

public enum RiskEvaluationAppendCode
{
    Appended,
    DuplicateIgnored,
    ConflictingDuplicate
}

public sealed record RiskEvaluationAppendResult(
    RiskEvaluationAppendCode Code,
    string EvaluationId,
    string PayloadHash);

public sealed record PersistedRiskEvaluation(
    string EvaluationId,
    string ProposalId,
    RiskEvaluationResult Result,
    string PayloadHash,
    DateTimeOffset CreatedAt);

public interface IRiskEvaluationStore
{
    Task<RiskEvaluationAppendResult> AppendAsync(
        string evaluationId,
        string proposalId,
        RiskEvaluationResult result,
        DateTimeOffset createdAt,
        CancellationToken cancellationToken);

    Task<PersistedRiskEvaluation?> GetAsync(
        string evaluationId,
        CancellationToken cancellationToken);
}
