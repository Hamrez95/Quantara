using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;
using Npgsql.EntityFrameworkCore.PostgreSQL.Metadata;

namespace Quantara.Infrastructure.Persistence.Migrations;

[DbContext(typeof(QuantaraDbContext))]
[Migration("20260720071000_InitialTradingPersistence")]
public sealed class InitialTradingPersistence : Migration
{
    private static readonly string[] AuditAggregateIndexColumns =
    [
        "aggregate_type",
        "aggregate_id",
        "sequence"
    ];

    private static readonly string[] OrderEventIndexColumns =
    [
        "order_id",
        "occurred_at"
    ];

    protected override void Up(MigrationBuilder migrationBuilder)
    {
        ArgumentNullException.ThrowIfNull(migrationBuilder);

        migrationBuilder.CreateTable(
            name: "orders",
            columns: table => new
            {
                order_id = table.Column<string>(
                    type: "character varying(128)",
                    maxLength: 128,
                    nullable: false),
                state = table.Column<string>(
                    type: "character varying(64)",
                    maxLength: 64,
                    nullable: false),
                version = table.Column<long>(
                    type: "bigint",
                    nullable: false),
                created_at = table.Column<DateTimeOffset>(
                    type: "timestamp with time zone",
                    nullable: false),
                updated_at = table.Column<DateTimeOffset>(
                    type: "timestamp with time zone",
                    nullable: false)
            },
            constraints: table =>
            {
                table.PrimaryKey("pk_orders", row => row.order_id);
            });

        migrationBuilder.CreateTable(
            name: "risk_evaluations",
            columns: table => new
            {
                evaluation_id = table.Column<string>(
                    type: "character varying(128)",
                    maxLength: 128,
                    nullable: false),
                proposal_id = table.Column<string>(
                    type: "character varying(128)",
                    maxLength: 128,
                    nullable: false),
                payload_hash = table.Column<string>(
                    type: "character(64)",
                    fixedLength: true,
                    maxLength: 64,
                    nullable: false),
                payload_json = table.Column<string>(
                    type: "jsonb",
                    nullable: false),
                evaluated_at = table.Column<DateTimeOffset>(
                    type: "timestamp with time zone",
                    nullable: false),
                risk_policy_version = table.Column<string>(
                    type: "character varying(128)",
                    maxLength: 128,
                    nullable: false),
                created_at = table.Column<DateTimeOffset>(
                    type: "timestamp with time zone",
                    nullable: false)
            },
            constraints: table =>
            {
                table.PrimaryKey(
                    "pk_risk_evaluations",
                    row => row.evaluation_id);
            });

        migrationBuilder.CreateTable(
            name: "audit_events",
            columns: table => new
            {
                sequence = table.Column<long>(
                    type: "bigint",
                    nullable: false)
                    .Annotation(
                        "Npgsql:ValueGenerationStrategy",
                        NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                event_id = table.Column<Guid>(
                    type: "uuid",
                    nullable: false),
                aggregate_type = table.Column<string>(
                    type: "character varying(64)",
                    maxLength: 64,
                    nullable: false),
                aggregate_id = table.Column<string>(
                    type: "character varying(128)",
                    maxLength: 128,
                    nullable: false),
                event_type = table.Column<string>(
                    type: "character varying(128)",
                    maxLength: 128,
                    nullable: false),
                payload_json = table.Column<string>(
                    type: "jsonb",
                    nullable: false),
                occurred_at = table.Column<DateTimeOffset>(
                    type: "timestamp with time zone",
                    nullable: false)
            },
            constraints: table =>
            {
                table.PrimaryKey("pk_audit_events", row => row.sequence);
            });

        migrationBuilder.CreateTable(
            name: "order_events",
            columns: table => new
            {
                event_id = table.Column<string>(
                    type: "character varying(128)",
                    maxLength: 128,
                    nullable: false),
                order_id = table.Column<string>(
                    type: "character varying(128)",
                    maxLength: 128,
                    nullable: false),
                target_state = table.Column<string>(
                    type: "character varying(64)",
                    maxLength: 64,
                    nullable: false),
                application_code = table.Column<string>(
                    type: "character varying(64)",
                    maxLength: 64,
                    nullable: false),
                previous_state = table.Column<string>(
                    type: "character varying(64)",
                    maxLength: 64,
                    nullable: false),
                current_state = table.Column<string>(
                    type: "character varying(64)",
                    maxLength: 64,
                    nullable: false),
                occurred_at = table.Column<DateTimeOffset>(
                    type: "timestamp with time zone",
                    nullable: false),
                reason = table.Column<string>(
                    type: "character varying(1024)",
                    maxLength: 1024,
                    nullable: false),
                created_at = table.Column<DateTimeOffset>(
                    type: "timestamp with time zone",
                    nullable: false)
            },
            constraints: table =>
            {
                table.PrimaryKey("pk_order_events", row => row.event_id);
                table.ForeignKey(
                    name: "fk_order_events_orders_order_id",
                    column: row => row.order_id,
                    principalTable: "orders",
                    principalColumn: "order_id",
                    onDelete: ReferentialAction.Cascade);
            });

        migrationBuilder.CreateIndex(
            name: "ux_audit_events_event_id",
            table: "audit_events",
            column: "event_id",
            unique: true);

        migrationBuilder.CreateIndex(
            name: "ix_audit_events_aggregate_sequence",
            table: "audit_events",
            columns: AuditAggregateIndexColumns);

        migrationBuilder.CreateIndex(
            name: "ix_order_events_order_occurred",
            table: "order_events",
            columns: OrderEventIndexColumns);

        migrationBuilder.CreateIndex(
            name: "ix_risk_evaluations_proposal_id",
            table: "risk_evaluations",
            column: "proposal_id");

        migrationBuilder.Sql(
            """
            CREATE OR REPLACE FUNCTION quantara_prevent_audit_event_mutation()
            RETURNS trigger
            LANGUAGE plpgsql
            AS $$
            BEGIN
                RAISE EXCEPTION 'audit_events is append-only';
            END;
            $$;

            CREATE TRIGGER trg_audit_events_append_only
            BEFORE UPDATE OR DELETE ON audit_events
            FOR EACH ROW
            EXECUTE FUNCTION quantara_prevent_audit_event_mutation();
            """);
    }

    protected override void Down(MigrationBuilder migrationBuilder)
    {
        ArgumentNullException.ThrowIfNull(migrationBuilder);

        migrationBuilder.Sql(
            """
            DROP TRIGGER IF EXISTS trg_audit_events_append_only ON audit_events;
            DROP FUNCTION IF EXISTS quantara_prevent_audit_event_mutation();
            """);
        migrationBuilder.DropTable(name: "order_events");
        migrationBuilder.DropTable(name: "risk_evaluations");
        migrationBuilder.DropTable(name: "audit_events");
        migrationBuilder.DropTable(name: "orders");
    }
}

