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

    public DbSet<AutoTradeRunEntity> AutoTradeRuns => Set<AutoTradeRunEntity>();

    public DbSet<AutoTradeControlRequestEntity> AutoTradeControlRequests =>
        Set<AutoTradeControlRequestEntity>();

    public DbSet<AutoTradeExecutionAuditEntity> AutoTradeExecutionAudit =>
        Set<AutoTradeExecutionAuditEntity>();

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
        ConfigureAutoTradeRuns(modelBuilder);
        ConfigureAutoTradeControlRequests(modelBuilder);
        ConfigureAutoTradeExecutionAudit(modelBuilder);
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

    private static void ConfigureAutoTradeRuns(ModelBuilder modelBuilder)
    {
        var entity = modelBuilder.Entity<AutoTradeRunEntity>();
        entity.ToTable("auto_trade_runs");
        entity.HasKey(run => run.RunId);
        entity.Property(run => run.RunId)
            .HasColumnName("run_id")
            .HasMaxLength(128);
        entity.Property(run => run.State)
            .HasColumnName("state")
            .HasMaxLength(64);
        entity.Property(run => run.Version)
            .HasColumnName("version")
            .IsConcurrencyToken();
        entity.Property(run => run.ConfigurationJson)
            .HasColumnName("configuration_json")
            .HasColumnType("jsonb");
        entity.Property(run => run.StartedAt)
            .HasColumnName("started_at");
        entity.Property(run => run.StoppedAt)
            .HasColumnName("stopped_at");
        entity.Property(run => run.LastStopPolicy)
            .HasColumnName("last_stop_policy")
            .HasMaxLength(64);
        entity.Property(run => run.LastReason)
            .HasColumnName("last_reason")
            .HasMaxLength(2048);
        entity.Property(run => run.LastRequestId)
            .HasColumnName("last_request_id")
            .HasMaxLength(128);
        entity.Property(run => run.UpdatedAt)
            .HasColumnName("updated_at");
    }

    private static void ConfigureAutoTradeControlRequests(ModelBuilder modelBuilder)
    {
        var entity = modelBuilder.Entity<AutoTradeControlRequestEntity>();
        entity.ToTable("auto_trade_control_requests");
        entity.HasKey(request => request.ControlRequestId);
        entity.Property(request => request.ControlRequestId)
            .HasColumnName("control_request_id");
        entity.Property(request => request.RunId)
            .HasColumnName("run_id")
            .HasMaxLength(128);
        entity.Property(request => request.RequestId)
            .HasColumnName("request_id")
            .HasMaxLength(128);
        entity.Property(request => request.Action)
            .HasColumnName("action")
            .HasMaxLength(64);
        entity.Property(request => request.Fingerprint)
            .HasColumnName("fingerprint")
            .HasMaxLength(64)
            .IsFixedLength();
        entity.Property(request => request.ResultCode)
            .HasColumnName("result_code")
            .HasMaxLength(64);
        entity.Property(request => request.SnapshotJson)
            .HasColumnName("snapshot_json")
            .HasColumnType("jsonb");
        entity.Property(request => request.ErrorsJson)
            .HasColumnName("errors_json")
            .HasColumnType("jsonb");
        entity.Property(request => request.CreatedAt)
            .HasColumnName("created_at");
        entity.HasOne<AutoTradeRunEntity>()
            .WithMany()
            .HasForeignKey(request => request.RunId)
            .OnDelete(DeleteBehavior.Cascade);
        entity.HasIndex(request => new { request.RunId, request.RequestId })
            .IsUnique()
            .HasDatabaseName("ux_auto_trade_control_requests_run_request");
    }

    private static void ConfigureAutoTradeExecutionAudit(ModelBuilder modelBuilder)
    {
        var entity = modelBuilder.Entity<AutoTradeExecutionAuditEntity>();
        entity.ToTable("auto_trade_execution_audit");
        entity.HasKey(auditEvent => auditEvent.Sequence);
        entity.Property(auditEvent => auditEvent.Sequence)
            .HasColumnName("sequence")
            .ValueGeneratedOnAdd();
        entity.Property(auditEvent => auditEvent.EventId)
            .HasColumnName("event_id");
        entity.Property(auditEvent => auditEvent.RunId)
            .HasColumnName("run_id")
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
            .HasDatabaseName("ux_auto_trade_execution_audit_event_id");
        entity.HasIndex(auditEvent => new { auditEvent.RunId, auditEvent.Sequence })
            .HasDatabaseName("ix_auto_trade_execution_audit_run_sequence");
    }

    private void EnforceAppendOnlyAuditEvents()
    {
        var illegalAuditMutation = ChangeTracker
            .Entries<AuditEventEntity>()
            .Any(entry => entry.State is EntityState.Modified or EntityState.Deleted);
        var illegalAutoTradeAuditMutation = ChangeTracker
            .Entries<AutoTradeExecutionAuditEntity>()
            .Any(entry => entry.State is EntityState.Modified or EntityState.Deleted);

        if (illegalAuditMutation || illegalAutoTradeAuditMutation)
        {
            throw new InvalidOperationException(
                "Audit events are append-only and cannot be modified or deleted.");
        }
    }
}
