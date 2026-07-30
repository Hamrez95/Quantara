using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;
using Npgsql.EntityFrameworkCore.PostgreSQL.Metadata;

namespace Quantara.Infrastructure.Persistence.Migrations;

[DbContext(typeof(QuantaraDbContext))]
[Migration("20260730160000_AddUnattendedAutoTradePersistence")]
public sealed class AddUnattendedAutoTradePersistence : Migration
{
    private static readonly string[] RunRequestColumns = ["run_id", "request_id"];

    private static readonly string[] RunSequenceColumns = ["run_id", "sequence"];

    protected override void Up(MigrationBuilder migrationBuilder)
    {
        ArgumentNullException.ThrowIfNull(migrationBuilder);

        migrationBuilder.CreateTable(
            name: "auto_trade_runs",
            columns: table => new
            {
                run_id = table.Column<string>(
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
                configuration_json = table.Column<string>(
                    type: "jsonb",
                    nullable: true),
                started_at = table.Column<DateTimeOffset>(
                    type: "timestamp with time zone",
                    nullable: true),
                stopped_at = table.Column<DateTimeOffset>(
                    type: "timestamp with time zone",
                    nullable: true),
                last_stop_policy = table.Column<string>(
                    type: "character varying(64)",
                    maxLength: 64,
                    nullable: true),
                last_reason = table.Column<string>(
                    type: "character varying(2048)",
                    maxLength: 2048,
                    nullable: false),
                last_request_id = table.Column<string>(
                    type: "character varying(128)",
                    maxLength: 128,
                    nullable: false),
                updated_at = table.Column<DateTimeOffset>(
                    type: "timestamp with time zone",
                    nullable: false)
            },
            constraints: table =>
            {
                table.PrimaryKey("pk_auto_trade_runs", row => row.run_id);
            });

        migrationBuilder.CreateTable(
            name: "auto_trade_execution_audit",
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
                run_id = table.Column<string>(
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
                table.PrimaryKey(
                    "pk_auto_trade_execution_audit",
                    row => row.sequence);
            });

        migrationBuilder.CreateTable(
            name: "auto_trade_control_requests",
            columns: table => new
            {
                control_request_id = table.Column<Guid>(
                    type: "uuid",
                    nullable: false),
                run_id = table.Column<string>(
                    type: "character varying(128)",
                    maxLength: 128,
                    nullable: false),
                request_id = table.Column<string>(
                    type: "character varying(128)",
                    maxLength: 128,
                    nullable: false),
                action = table.Column<string>(
                    type: "character varying(64)",
                    maxLength: 64,
                    nullable: false),
                fingerprint = table.Column<string>(
                    type: "character(64)",
                    fixedLength: true,
                    maxLength: 64,
                    nullable: false),
                result_code = table.Column<string>(
                    type: "character varying(64)",
                    maxLength: 64,
                    nullable: false),
                snapshot_json = table.Column<string>(
                    type: "jsonb",
                    nullable: false),
                errors_json = table.Column<string>(
                    type: "jsonb",
                    nullable: false),
                created_at = table.Column<DateTimeOffset>(
                    type: "timestamp with time zone",
                    nullable: false)
            },
            constraints: table =>
            {
                table.PrimaryKey(
                    "pk_auto_trade_control_requests",
                    row => row.control_request_id);
                table.ForeignKey(
                    name: "fk_auto_trade_control_requests_auto_trade_runs_run_id",
                    column: row => row.run_id,
                    principalTable: "auto_trade_runs",
                    principalColumn: "run_id",
                    onDelete: ReferentialAction.Cascade);
            });

        migrationBuilder.CreateIndex(
            name: "ux_auto_trade_control_requests_run_request",
            table: "auto_trade_control_requests",
            columns: RunRequestColumns,
            unique: true);

        migrationBuilder.CreateIndex(
            name: "ux_auto_trade_execution_audit_event_id",
            table: "auto_trade_execution_audit",
            column: "event_id",
            unique: true);

        migrationBuilder.CreateIndex(
            name: "ix_auto_trade_execution_audit_run_sequence",
            table: "auto_trade_execution_audit",
            columns: RunSequenceColumns);

        migrationBuilder.Sql(
            """
            CREATE OR REPLACE FUNCTION quantara_prevent_auto_trade_audit_mutation()
            RETURNS trigger
            LANGUAGE plpgsql
            AS $$
            BEGIN
                RAISE EXCEPTION 'auto_trade_execution_audit is append-only';
            END;
            $$;

            CREATE TRIGGER trg_auto_trade_execution_audit_append_only
            BEFORE UPDATE OR DELETE ON auto_trade_execution_audit
            FOR EACH ROW
            EXECUTE FUNCTION quantara_prevent_auto_trade_audit_mutation();
            """);
    }

    protected override void Down(MigrationBuilder migrationBuilder)
    {
        ArgumentNullException.ThrowIfNull(migrationBuilder);

        migrationBuilder.Sql(
            """
            DROP TRIGGER IF EXISTS trg_auto_trade_execution_audit_append_only
            ON auto_trade_execution_audit;
            DROP FUNCTION IF EXISTS quantara_prevent_auto_trade_audit_mutation();
            """);
        migrationBuilder.DropTable(name: "auto_trade_control_requests");
        migrationBuilder.DropTable(name: "auto_trade_execution_audit");
        migrationBuilder.DropTable(name: "auto_trade_runs");
    }
}
