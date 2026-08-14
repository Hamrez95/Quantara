using System.Text.Json;
using System.Text.Json.Serialization;
using Quantara.Api.AutoTrading;
using Quantara.Api.Cockpit;
using Quantara.Api.Supervisor;

var builder = WebApplication.CreateBuilder(args);
builder.WebHost.UseKestrel(options => options.AddServerHeader = false);

builder.Services.ConfigureHttpJsonOptions(options =>
{
    options.SerializerOptions.PropertyNamingPolicy = JsonNamingPolicy.CamelCase;
    options.SerializerOptions.DictionaryKeyPolicy = JsonNamingPolicy.CamelCase;
    options.SerializerOptions.Converters.Add(
        new JsonStringEnumConverter(JsonNamingPolicy.CamelCase));
});
builder.Services.AddSingleton(TimeProvider.System);
builder.Services.AddSingleton<ICockpitSnapshotProvider, DeterministicCockpitSnapshotProvider>();
builder.Services.AddSingleton<IAutoTradeExecutionCapability, DisabledAutoTradeExecutionCapability>();
builder.Services.AddSingleton<IAutoTradePreflightService, ConfigurationAutoTradePreflightService>();
builder.Services.AddSingleton<IAutoTradeControlCoordinator, InMemoryAutoTradeControlCoordinator>();
builder.Services.AddSingleton<SupervisorAnalysisGate>();
builder.Services.AddSingleton<SupervisorSupportSessionRegistry>();
builder.Services.AddSingleton<SupervisorMcpAuditLedger>();
builder.Services.AddSingleton<SupervisorMcpRateLimiter>();
builder.Services.AddHttpClient<ISupervisorAnalysisService, OpenAiSupervisorAnalysisService>();

var allowedOrigins = builder.Configuration["QUANTARA_ALLOWED_ORIGINS"]?
    .Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
    ?? [];
if (allowedOrigins.Length > 0)
{
    builder.Services.AddCors(options =>
    {
        options.AddPolicy(
            "quantara-client",
            policy => policy
                .WithOrigins(allowedOrigins)
                .WithMethods("GET", "POST", "DELETE")
                .WithHeaders(
                    "Accept",
                    "Authorization",
                    "Content-Type",
                    "Origin",
                    "X-Quantara-Control-Token",
                    SupervisorEndpointAuthority.HeaderName));
    });
}

var app = builder.Build();

app.Use(async (context, next) =>
{
    context.Response.OnStarting(() =>
    {
        context.Response.Headers["Cache-Control"] = "no-store";
        context.Response.Headers["X-Content-Type-Options"] = "nosniff";
        context.Response.Headers["Referrer-Policy"] = "no-referrer";
        context.Response.Headers["X-Frame-Options"] = "DENY";
        context.Response.Headers["Content-Security-Policy"] =
            "default-src 'none'; frame-ancestors 'none'";
        context.Response.Headers["Permissions-Policy"] =
            "camera=(), geolocation=(), microphone=(), payment=()";
        return Task.CompletedTask;
    });

    await next().ConfigureAwait(false);
});

if (allowedOrigins.Length > 0)
{
    app.UseCors("quantara-client");
}

app.MapGet(
    "/health",
    (TimeProvider timeProvider) => Results.Json(
        new HealthResponseContract(
            "ok",
            "quantara-api",
            timeProvider.GetUtcNow(),
            "none",
            false)))
    .WithName("Health")
    .Produces<HealthResponseContract>(StatusCodes.Status200OK);

app.MapGet(
    "/api/v1/cockpit",
    (ICockpitSnapshotProvider provider, TimeProvider timeProvider) =>
        Results.Json(provider.Create(timeProvider.GetUtcNow())))
    .WithName("CockpitSnapshot")
    .Produces<CockpitResponseContract>(StatusCodes.Status200OK);

app.MapAutoTradeEndpoints();
app.MapSupervisorEndpoints();
app.MapSupervisorMcpEndpoints();

app.Run();

public partial class Program
{
}
