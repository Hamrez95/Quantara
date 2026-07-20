using System.Text.Json;
using Quantara.Api.Cockpit;

var builder = WebApplication.CreateBuilder(args);
builder.WebHost.UseKestrel(options => options.AddServerHeader = false);

builder.Services.ConfigureHttpJsonOptions(options =>
{
    options.SerializerOptions.PropertyNamingPolicy = JsonNamingPolicy.CamelCase;
    options.SerializerOptions.DictionaryKeyPolicy = JsonNamingPolicy.CamelCase;
});
builder.Services.AddSingleton(TimeProvider.System);
builder.Services.AddSingleton<ICockpitSnapshotProvider, DeterministicCockpitSnapshotProvider>();

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
                .WithMethods("GET")
                .WithHeaders("Accept", "Content-Type"));
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
            false)));

app.MapGet(
    "/api/v1/cockpit",
    (ICockpitSnapshotProvider provider, TimeProvider timeProvider) =>
        Results.Json(provider.Create(timeProvider.GetUtcNow())));

app.Run();

public partial class Program;
