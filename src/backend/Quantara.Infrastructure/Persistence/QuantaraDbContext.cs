using Microsoft.EntityFrameworkCore;

namespace Quantara.Infrastructure.Persistence;

public sealed class QuantaraDbContext(DbContextOptions<QuantaraDbContext> options)
    : DbContext(options)
{
    public DbSet<PersistedOrderEntity> Orders => Set<PersistedOrderEntity>();

    public DbSet<PersistedOrderEventEntity> OrderEvents => Set<PersistedOrderEventEntity>();

    public DbSet<PersistedRiskEvaluationEntity> RiskEvaluations =>
        Set<PersistedRiskEvaluationEntity>();

    public DbSet<AuditEventEntity> AuditEvents => Set<AuditEventEntity>();

    public override int SaveChanges()
    {
        EnforceAppendOnlyAuditEvents();
        return base.SaveChanges();
    }

    public override int SaveChanges(bool acceptAllChangesOnSuccess)
    {
        EnforceAppendOnlyAuditEvents();
        return base.SaveChanges(acceptAllChangesOnSuccess);
    }

    public override Task<int> SaveChangesAsync(
        CancellationToken cancellationToken = default)
    {
        EnforceAppendOnlyAuditEvents();
        return base.SaveChangesAsync(cancellationToken);
    }

    public override Task<int> SaveChangesAsync(
        bool acceptAllChangesOnSuccess,
        CancellationToken cancellationToken = default)
    {
        EnforceAppendOnlyAuditEvents();
        return base.SaveChangesAsync(acceptAllChangesOnSuccess, cancellationToken);
    }

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        ArgumentNullException.ThrowIfNull(modelBuilder);

        ConfigureOrders(modelBuilder);
        ConfigureOrderEvents(modelBuilder);
        ConfigureRiskEvaluations(modelBuilder);
        ConfigureAuditEvents(modelBuilder);
    }

    private static void ConfigureOrders(ModelBuilder modelBuilder)
    {
        var entity = modelBuilder.Entity<PersistedOrderEntity>();
        entity.ToTable("orders");
        entity.HasKey(order => order.OrderId);
        entity.Property(order => order.OrderId)
            .HasColumnName("order_id")
            .HasMaxLength(128);
        entity.Property(order => order.State)
            .HasColumnName("state")
            .HasConversion<string>()
            .HasMaxLength(64);
        entity.Property(order => order.Version)
            .HasColumnName("version")
            .IsConcurrencyToken();
        entity.Property(order => order.CreatedAt)
            .HasColumnName("created_at");
        entity.Property(order => order.UpdatedAt)
            .HasColumnName("updated_at");
    }

    private static void ConfigureOrderEvents(ModelBuilder modelBuilder)
    {
        var entity = modelBuilder.Entity<PersistedOrderEventEntity>();
        entity.ToTable("order_events");
        entity.HasKey(orderEvent => orderEvent.EventId);
        entity.Property(orderEvent => orderEvent.EventId)
            .HasColumnName("event_id")
            .HasMaxLength(128);
        entity.Property(orderEvent => orderEvent.OrderId)
            .HasColumnName("order_id")
            .HasMaxLength(128);
        entity.Property(orderEvent => orderEvent.TargetState)
            .HasColumnName("target_state")
            .HasConversion<string>()
            .HasMaxLength(64);
        entity.Property(orderEvent => orderEvent.ApplicationCode)
            .HasColumnName("application_code")
            .HasConversion<string>()
            .HasMaxLength(64);
        entity.Property(orderEvent => orderEvent.PreviousState)
            .HasColumnName("previous_state")
            .HasConversion<string>()
            .HasMaxLength(64);
        entity.Property(orderEvent => orderEvent.CurrentState)
            .HasColumnName("current_state")
            .HasConversion<string>()
            .HasMaxLength(64);
        entity.Property(orderEvent => orderEvent.OccurredAt)
            .HasColumnName("occurred_at");
        entity.Property(orderEvent => orderEvent.Reason)
            .HasColumnName("reason")
            .HasMaxLength(1024);
        entity.Property(orderEvent => orderEvent.CreatedAt)
            .HasColumnName("created_at");
        entity.HasOne(orderEvent => orderEvent.Order)
            .WithMany(order => order.Events)
            .HasForeignKey(orderEvent => orderEvent.OrderId)
            .OnDelete(DeleteBehavior.Cascade);
        entity.HasIndex(orderEvent => new
            {
                orderEvent.OrderId,
                orderEvent.OccurredAt
            })
            .HasDatabaseName("ix_order_events_order_occurred");
    }

    private static void ConfigureRiskEvaluations(ModelBuilder modelBuilder)
    {
        var entity = modelBuilder.Entity<PersistedRiskEvaluationEntity>();
        entity.ToTable("risk_evaluations");
        entity.HasKey(evaluation => evaluation.EvaluationId);
        entity.Property(evaluation => evaluation.EvaluationId)
            .HasColumnName("evaluation_id")
            .HasMaxLength(128);
        entity.Property(evaluation => evaluation.ProposalId)
            .HasColumnName("proposal_id")
            .HasMaxLength(128);
        entity.Property(evaluation => evaluation.PayloadHash)
            .HasColumnName("payload_hash")
            .HasMaxLength(64)
            .IsFixedLength();
        entity.Property(evaluation => evaluation.PayloadJson)
            .HasColumnName("payload_json")
            .HasColumnType("jsonb");
        entity.Property(evaluation => evaluation.EvaluatedAt)
            .HasColumnName("evaluated_at");
        entity.Property(evaluation => evaluation.RiskPolicyVersion)
            .HasColumnName("risk_policy_version")
            .HasMaxLength(128);
        entity.Property(evaluation => evaluation.CreatedAt)
            .HasColumnName("created_at");
        entity.HasIndex(evaluation => evaluation.ProposalId)
            .HasDatabaseName("ix_risk_evaluations_proposal_id");
    }

    private static void ConfigureAuditEvents(ModelBuilder modelBuilder)
    {
        var entity = modelBuilder.Entity<AuditEventEntity>();
        entity.ToTable("audit_events");
        entity.HasKey(auditEvent => auditEvent.Sequence);
        entity.Property(auditEvent => auditEvent.Sequence)
            .HasColumnName("sequence")
            .ValueGeneratedOnAdd();
        entity.Property(auditEvent => auditEvent.EventId)
            .HasColumnName("event_id");
        entity.Property(auditEvent => auditEvent.AggregateType)
            .HasColumnName("aggregate_type")
            .HasMaxLength(64);
        entity.Property(auditEvent => auditEvent.AggregateId)
            .HasColumnName("aggregate_id")
            .HasMaxLength(128);
        entity.Property(auditEvent => auditEvent.EventType)
            .HasColumnName("event_type")
            .HasMaxLength(128);
        entity.Property(auditEvent => auditEvent.PayloadJson)
            .HasColumnName("payload_json")
            .HasColumnType("jsonb");
        entity.Property(auditEvent => auditEvent.OccurredAt)
            .HasColumnName("occurred_at");
        entity.HasIndex(auditEvent => auditEvent.EventId)
            .IsUnique()
            .HasDatabaseName("ux_audit_events_event_id");
        entity.HasIndex(auditEvent => new
            {
                auditEvent.AggregateType,
                auditEvent.AggregateId,
                auditEvent.Sequence
            })
            .HasDatabaseName("ix_audit_events_aggregate_sequence");
    }

    private void EnforceAppendOnlyAuditEvents()
    {
        var illegalAuditMutation = ChangeTracker
            .Entries<AuditEventEntity>()
            .FirstOrDefault(entry => entry.State is EntityState.Modified or EntityState.Deleted);

        if (illegalAuditMutation is not null)
        {
            throw new InvalidOperationException(
                "Audit events are append-only and cannot be modified or deleted.");
        }
    }
}
