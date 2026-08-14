using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace Quantara.Api.Supervisor;

public static class SupervisorMcpEndpoints
{
    private const string ProtocolVersion = "2025-11-25";
    private const string ControlHeader = "X-Quantara-Control-Token";
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);

    public static IEndpointRouteBuilder MapSupervisorMcpEndpoints(
        this IEndpointRouteBuilder endpoints)
    {
        ArgumentNullException.ThrowIfNull(endpoints);

        endpoints.MapPost(
            "/api/v1/supervisor/support-session/register",
            (
                HttpContext context,
                SupervisorSupportSessionRegistrationContract registration,
                SupervisorSupportSessionRegistry registry,
                IConfiguration configuration) =>
            {
                if (!HasControlAuthority(context, configuration))
                {
                    return Results.Unauthorized();
                }

                if (!registry.TryRegister(registration, out var snapshot, out var error))
                {
                    return Results.BadRequest(new { error });
                }

                return Results.Json(snapshot, statusCode: StatusCodes.Status201Created);
            })
            .WithName("SupervisorSupportSessionRegister")
            .Produces<SupervisorSupportSessionSnapshotContract>(StatusCodes.Status201Created)
            .Produces(StatusCodes.Status400BadRequest)
            .Produces(StatusCodes.Status401Unauthorized);

        endpoints.MapGet(
            "/api/v1/supervisor/support-session",
            (HttpContext context, SupervisorSupportSessionRegistry registry) =>
            {
                if (!TryResolveSession(context, registry, out _, out var view))
                {
                    return Results.Unauthorized();
                }

                return Results.Json(view!.Snapshot);
            })
            .WithName("SupervisorSupportSessionStatus")
            .Produces<SupervisorSupportSessionSnapshotContract>(StatusCodes.Status200OK)
            .Produces(StatusCodes.Status401Unauthorized);

        endpoints.MapPost(
            "/api/v1/supervisor/support-session/evidence",
            (
                HttpContext context,
                SupervisorEvidenceUpdateContract update,
                SupervisorSupportSessionRegistry registry) =>
            {
                if (!TryResolveSession(context, registry, out var token, out _))
                {
                    return Results.Unauthorized();
                }

                if (!registry.TryUpdateEvidence(token!, update, out var snapshot, out var error))
                {
                    return Results.BadRequest(new { error });
                }

                return Results.Json(snapshot);
            })
            .WithName("SupervisorSupportSessionEvidence")
            .Produces<SupervisorSupportSessionSnapshotContract>(StatusCodes.Status200OK)
            .Produces(StatusCodes.Status400BadRequest)
            .Produces(StatusCodes.Status401Unauthorized);

        endpoints.MapDelete(
            "/api/v1/supervisor/support-session",
            (HttpContext context, SupervisorSupportSessionRegistry registry) =>
            {
                if (!TryResolveSession(context, registry, out var token, out _))
                {
                    return Results.Unauthorized();
                }

                registry.Revoke(token!);
                return Results.NoContent();
            })
            .WithName("SupervisorSupportSessionRevoke")
            .Produces(StatusCodes.Status204NoContent)
            .Produces(StatusCodes.Status401Unauthorized);

        endpoints.MapPost(
            "/mcp/quantara",
            (
                HttpContext context,
                JsonElement request,
                SupervisorSupportSessionRegistry registry,
                SupervisorMcpAuditLedger auditLedger,
                SupervisorMcpRateLimiter rateLimiter,
                TimeProvider timeProvider,
                IConfiguration configuration) =>
            {
                if (!OriginAllowed(context, configuration))
                {
                    return Results.StatusCode(StatusCodes.Status403Forbidden);
                }

                if (!TryResolveSession(context, registry, out _, out var session))
                {
                    return Results.Unauthorized();
                }

                if (!rateLimiter.TryAcquire(session!.Snapshot.SessionId))
                {
                    auditLedger.Record(
                        new SupervisorMcpAuditEvent(
                            timeProvider.GetUtcNow(),
                            session.Snapshot.SessionId,
                            "rate_limit",
                            false,
                            Guid.NewGuid().ToString("N")));
                    return Results.StatusCode(StatusCodes.Status429TooManyRequests);
                }

                return HandleMcpRequest(request, session, auditLedger, timeProvider);
            })
            .WithName("QuantaraSupervisorMcp")
            .Accepts<JsonElement>("application/json")
            .Produces(StatusCodes.Status200OK)
            .Produces(StatusCodes.Status202Accepted)
            .Produces(StatusCodes.Status401Unauthorized)
            .Produces(StatusCodes.Status403Forbidden)
            .Produces(StatusCodes.Status429TooManyRequests);

        return endpoints;
    }

    private static IResult HandleMcpRequest(
        JsonElement request,
        SupervisorSupportSessionView session,
        SupervisorMcpAuditLedger auditLedger,
        TimeProvider timeProvider)
    {
        var auditId = Guid.NewGuid().ToString("N");
        var method = request.ValueKind == JsonValueKind.Object
            && request.TryGetProperty("method", out var methodElement)
                ? methodElement.GetString()
                : null;
        var operation = method ?? "invalid";
        var succeeded = false;
        try
        {
            if (request.ValueKind != JsonValueKind.Object
                || !request.TryGetProperty("jsonrpc", out var version)
                || version.GetString() != "2.0"
                || string.IsNullOrWhiteSpace(method))
            {
                return JsonRpcError(request, -32600, "Invalid Request");
            }

            switch (method)
            {
                case "notifications/initialized":
                    succeeded = true;
                    return Results.StatusCode(StatusCodes.Status202Accepted);
                case "initialize":
                    succeeded = true;
                    return JsonRpcResult(
                        request,
                        new
                        {
                            protocolVersion = ProtocolVersion,
                            capabilities = new { tools = new { listChanged = false } },
                            serverInfo = new { name = "Quantara Supervisor", version = "1.0.0" },
                            instructions =
                                "Read-only access to sanitized Quantara evidence. " +
                                "Credentials and live trading mutation tools are not exposed."
                        });
                case "ping":
                    succeeded = true;
                    return JsonRpcResult(request, new { });
                case "tools/list":
                    succeeded = true;
                    return JsonRpcResult(
                        request,
                        new { tools = SupervisorMcpToolCatalog.Definitions() });
                case "tools/call":
                    if (!TryReadToolCall(request, out var toolName, out var arguments))
                    {
                        return JsonRpcError(request, -32602, "Invalid tool arguments");
                    }

                    operation = $"tools/call:{toolName}";
                    if (!TryRunTool(toolName!, arguments, session, out var structured))
                    {
                        return JsonRpcError(request, -32601, "Unknown tool");
                    }

                    succeeded = true;
                    return JsonRpcResult(
                        request,
                        new
                        {
                            content = new[]
                            {
                                new
                                {
                                    type = "text",
                                    text = JsonSerializer.Serialize(structured, JsonOptions)
                                }
                            },
                            structuredContent = structured,
                            isError = false
                        });
                default:
                    return JsonRpcError(request, -32601, "Method not found");
            }
        }
        finally
        {
            auditLedger.Record(
                new SupervisorMcpAuditEvent(
                    timeProvider.GetUtcNow(),
                    session.Snapshot.SessionId,
                    operation,
                    succeeded,
                    auditId));
        }
    }

    private static bool TryRunTool(
        string toolName,
        JsonElement arguments,
        SupervisorSupportSessionView session,
        out object structured)
    {
        var evidence = session.Evidence;
        var limit = ReadLimit(arguments);
        IReadOnlyList<SupervisorEvidenceContract> selected;
        switch (toolName)
        {
            case "get_system_health":
                structured = new
                {
                    session = session.Snapshot,
                    evidenceCount = evidence.Count,
                    latestObservedAtUtc = evidence.Count == 0
                        ? (DateTimeOffset?)null
                        : evidence.Max(item => item.ObservedAtUtc),
                    domains = evidence
                        .GroupBy(item => item.Domain, StringComparer.Ordinal)
                        .OrderBy(group => group.Key, StringComparer.Ordinal)
                        .ToDictionary(group => group.Key, group => group.Count(), StringComparer.Ordinal)
                };
                return true;
            case "get_runtime_state":
                selected = Filter(evidence, limit, "runtime");
                break;
            case "get_strategy_scorecard":
                selected = Filter(evidence, limit, "strategy");
                break;
            case "get_trade_lifecycle":
                selected = Filter(evidence, SupervisorMcpToolCatalog.MaximumResultLimit, "runtime", "risk", "journal");
                var correlationId = ReadString(arguments, "correlationId");
                if (!string.IsNullOrWhiteSpace(correlationId))
                {
                    selected = selected
                        .Where(item => string.Equals(item.CorrelationId, correlationId, StringComparison.Ordinal))
                        .Take(limit)
                        .ToArray();
                }
                else
                {
                    selected = selected.Take(limit).ToArray();
                }
                break;
            case "get_journal_consistency":
                selected = Filter(evidence, limit, "journal");
                break;
            case "get_recent_anomalies":
                selected = evidence
                    .Where(item => item.Severity is "warning" or "error" or "critical")
                    .OrderByDescending(item => item.ObservedAtUtc)
                    .ThenBy(item => item.EvidenceId, StringComparer.Ordinal)
                    .Take(limit)
                    .ToArray();
                break;
            case "get_build_and_ci_state":
                selected = Filter(evidence, limit, "build", "test");
                break;
            case "get_config_summary_non_secret":
                selected = Filter(evidence, limit, "config");
                break;
            case "get_evidence_by_id":
                var evidenceId = ReadString(arguments, "evidenceId");
                selected = string.IsNullOrWhiteSpace(evidenceId)
                    ? Array.Empty<SupervisorEvidenceContract>()
                    : evidence
                        .Where(item => string.Equals(item.EvidenceId, evidenceId, StringComparison.Ordinal))
                        .Take(1)
                        .ToArray();
                break;
            default:
                structured = new { };
                return false;
        }

        structured = new { count = selected.Count, evidence = selected };
        return true;
    }

    private static SupervisorEvidenceContract[] Filter(
        IReadOnlyList<SupervisorEvidenceContract> evidence,
        int limit,
        params string[] domains) =>
        evidence
            .Where(item => domains.Contains(item.Domain, StringComparer.Ordinal))
            .OrderByDescending(item => item.ObservedAtUtc)
            .ThenBy(item => item.EvidenceId, StringComparer.Ordinal)
            .Take(limit)
            .ToArray();

    private static bool TryReadToolCall(
        JsonElement request,
        out string? toolName,
        out JsonElement arguments)
    {
        toolName = null;
        arguments = default;
        if (!request.TryGetProperty("params", out var parameters)
            || parameters.ValueKind != JsonValueKind.Object
            || !parameters.TryGetProperty("name", out var name))
        {
            return false;
        }

        toolName = name.GetString();
        if (string.IsNullOrWhiteSpace(toolName))
        {
            return false;
        }

        arguments = parameters.TryGetProperty("arguments", out var supplied)
            && supplied.ValueKind == JsonValueKind.Object
                ? supplied
                : JsonSerializer.SerializeToElement(new { });
        return true;
    }

    private static int ReadLimit(JsonElement arguments)
    {
        if (arguments.ValueKind == JsonValueKind.Object
            && arguments.TryGetProperty("maxResults", out var value)
            && value.TryGetInt32(out var parsed))
        {
            return Math.Clamp(parsed, 1, SupervisorMcpToolCatalog.MaximumResultLimit);
        }

        return SupervisorMcpToolCatalog.DefaultResultLimit;
    }

    private static string? ReadString(JsonElement arguments, string propertyName) =>
        arguments.ValueKind == JsonValueKind.Object
        && arguments.TryGetProperty(propertyName, out var value)
        && value.ValueKind == JsonValueKind.String
            ? value.GetString()
            : null;

    private static IResult JsonRpcResult(JsonElement request, object result) =>
        Results.Json(new { jsonrpc = "2.0", id = ReadJsonRpcId(request), result });

    private static IResult JsonRpcError(JsonElement request, int code, string message) =>
        Results.Json(
            new
            {
                jsonrpc = "2.0",
                id = ReadJsonRpcId(request),
                error = new { code, message }
            });

    private static object? ReadJsonRpcId(JsonElement request)
    {
        if (request.ValueKind != JsonValueKind.Object
            || !request.TryGetProperty("id", out var id))
        {
            return null;
        }

        return id.ValueKind switch
        {
            JsonValueKind.String => id.GetString(),
            JsonValueKind.Number when id.TryGetInt64(out var number) => number,
            JsonValueKind.Null => null,
            _ => id.GetRawText()
        };
    }

    private static bool TryResolveSession(
        HttpContext context,
        SupervisorSupportSessionRegistry registry,
        out string? token,
        out SupervisorSupportSessionView? view)
    {
        token = null;
        view = null;
        var authorization = context.Request.Headers["Authorization"].ToString();
        const string prefix = "Bearer ";
        if (!authorization.StartsWith(prefix, StringComparison.OrdinalIgnoreCase))
        {
            return false;
        }

        token = authorization[prefix.Length..].Trim();
        return registry.TryGet(token, out view);
    }

    private static bool HasControlAuthority(HttpContext context, IConfiguration configuration)
    {
        var expected = configuration["QUANTARA_CONTROL_TOKEN"];
        if (string.IsNullOrWhiteSpace(expected) || expected.Length < 32)
        {
            return false;
        }

        var provided = context.Request.Headers[ControlHeader].ToString();
        if (provided.Length != expected.Length)
        {
            return false;
        }

        return CryptographicOperations.FixedTimeEquals(
            Encoding.UTF8.GetBytes(provided),
            Encoding.UTF8.GetBytes(expected));
    }

    private static bool OriginAllowed(HttpContext context, IConfiguration configuration)
    {
        var origin = context.Request.Headers["Origin"].ToString();
        if (string.IsNullOrWhiteSpace(origin))
        {
            return true;
        }

        var allowed = configuration["QUANTARA_MCP_ALLOWED_ORIGINS"]?
            .Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            ?? Array.Empty<string>();
        return allowed.Any(candidate =>
            string.Equals(candidate, origin, StringComparison.OrdinalIgnoreCase));
    }
}
