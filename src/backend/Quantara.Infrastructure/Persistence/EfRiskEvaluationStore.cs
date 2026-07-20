using Microsoft.EntityFrameworkCore;
using Quantara.Domain.Persistence;
using Quantara.Domain.Risk;

namespace Quantara.Infrastructure.Persistence;

public sealed class EfRiskEvaluationStore : IRiskEvaluationStore
{
    private readonly QuantaraDbContext _dbContext;

    public EfRiskEvaluationStore(QuantaraDbContext dbContext)
    {
        ArgumentNullException.ThrowIfNull(dbContext);
        _dbContext = dbContext;
    }

    public async Task<RiskEvaluationAppendResult> AppendAsync(
        string evaluationId,
        string proposalId,
        RiskEvaluationResult result,
        DateTimeOffset createdAt,
        CancellationToken cancellationToken)
    {
        ValidateIdentifier(evaluationId, nameof(evaluationId));
        ValidateIdentifier(proposalId, nameof(proposalId));
        ArgumentNullException.ThrowIfNull(result);

        var envelope = new RiskEvaluationEnvelope(proposalId, result);
        var payloadJson = PersistenceJson.Serialize(envelope);
        var payloadHash = PersistenceJson.ComputeHash(payloadJson);

        var existing = await FindAsync(evaluationId, cancellationToken);
        if (existing is not null)
        {
            return CreateDuplicateResult(evaluationId, payloadHash, existing.PayloadHash);
        }

        var timestamp = createdAt.ToUniversalTime();
        _dbContext.RiskEvaluations.Add(new PersistedRiskEvaluationEntity
        {
            EvaluationId = evaluationId,
            ProposalId = proposalId,
            PayloadHash = payloadHash,
            PayloadJson = payloadJson,
            EvaluatedAt = result.EvaluatedAt.ToUniversalTime(),
            RiskPolicyVersion = result.RiskPolicyVersion,
            CreatedAt = timestamp
        });
        _dbContext.AuditEvents.Add(new AuditEventEntity
        {
            EventId = Guid.NewGuid(),
            AggregateType = "risk-evaluation",
            AggregateId = evaluationId,
            EventType = "risk-evaluation.appended",
            PayloadJson = PersistenceJson.Serialize(new
            {
                evaluationId,
                proposalId,
                payloadHash,
                result.IsApproved,
                result.DecisionCode,
                result.RiskPolicyVersion
            }),
            OccurredAt = timestamp
        });

        try
        {
            await _dbContext.SaveChangesAsync(cancellationToken);
            return new RiskEvaluationAppendResult(
                RiskEvaluationAppendCode.Appended,
                evaluationId,
                payloadHash);
        }
        catch (DbUpdateException)
        {
            _dbContext.ChangeTracker.Clear();
            existing = await FindAsync(evaluationId, cancellationToken);
            if (existing is not null)
            {
                return CreateDuplicateResult(
                    evaluationId,
                    payloadHash,
                    existing.PayloadHash);
            }

            throw;
        }
    }

    public async Task<PersistedRiskEvaluation?> GetAsync(
        string evaluationId,
        CancellationToken cancellationToken)
    {
        ValidateIdentifier(evaluationId, nameof(evaluationId));

        var entity = await FindAsync(evaluationId, cancellationToken);
        if (entity is null)
        {
            return null;
        }

        var envelope = PersistenceJson.Deserialize<RiskEvaluationEnvelope>(
            entity.PayloadJson);
        return new PersistedRiskEvaluation(
            entity.EvaluationId,
            envelope.ProposalId,
            envelope.Result,
            entity.PayloadHash,
            entity.CreatedAt);
    }

    private async Task<PersistedRiskEvaluationEntity?> FindAsync(
        string evaluationId,
        CancellationToken cancellationToken)
    {
        return await _dbContext.RiskEvaluations
            .AsNoTracking()
            .SingleOrDefaultAsync(
                evaluation => evaluation.EvaluationId == evaluationId,
                cancellationToken);
    }

    private static RiskEvaluationAppendResult CreateDuplicateResult(
        string evaluationId,
        string requestedHash,
        string existingHash)
    {
        return new RiskEvaluationAppendResult(
            string.Equals(requestedHash, existingHash, StringComparison.Ordinal)
                ? RiskEvaluationAppendCode.DuplicateIgnored
                : RiskEvaluationAppendCode.ConflictingDuplicate,
            evaluationId,
            existingHash);
    }

    private static void ValidateIdentifier(string value, string parameterName)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(value, parameterName);
        if (value.Length > 128)
        {
            throw new ArgumentException(
                "Identifier cannot exceed 128 characters.",
                parameterName);
        }
    }

    private sealed record RiskEvaluationEnvelope(
        string ProposalId,
        RiskEvaluationResult Result);
}
