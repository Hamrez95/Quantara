using System.Security.Cryptography;
using System.Text;
using Quantara.Domain.AutoTrading;

namespace Quantara.Api.AutoTrading;

public static class AutoTradeEndpoints
{
    private const string ControlHeader = "X-Quantara-Control-Token";

    public static IEndpointRouteBuilder MapAutoTradeEndpoints(
        this IEndpointRouteBuilder endpoints)
    {
        ArgumentNullException.ThrowIfNull(endpoints);

        endpoints.MapGet(
            "/api/v1/auto-trade/status",
            (HttpContext context, IAutoTradeControlCoordinator coordinator, IConfiguration configuration) =>
            {
                if (!HasControlAuthority(context, configuration))
                {
                    return Results.Unauthorized();
                }

                return Results.Json(coordinator.GetSnapshot());
            })
            .WithName("AutoTradeStatus")
            .Produces<AutoTradeRunSnapshot>(StatusCodes.Status200OK)
            .Produces(StatusCodes.Status401Unauthorized);

        endpoints.MapPost(
            "/api/v1/auto-trade/start",
            async (
                HttpContext context,
                AutoTradeStartContract request,
                IAutoTradeControlCoordinator coordinator,
                IConfiguration configuration,
                CancellationToken cancellationToken) =>
            {
                if (!HasControlAuthority(context, configuration))
                {
                    return Results.Unauthorized();
                }

                var result = await coordinator
                    .StartAsync(request, cancellationToken)
                    .ConfigureAwait(false);
                return ToHttpResult(result);
            })
            .WithName("AutoTradeStart")
            .Accepts<AutoTradeStartContract>("application/json")
            .Produces<AutoTradeTransitionResult>(StatusCodes.Status200OK)
            .Produces<AutoTradeTransitionResult>(StatusCodes.Status400BadRequest)
            .Produces<AutoTradeTransitionResult>(StatusCodes.Status409Conflict)
            .Produces(StatusCodes.Status401Unauthorized);

        endpoints.MapPost(
            "/api/v1/auto-trade/stop",
            async (
                HttpContext context,
                AutoTradeStopContract request,
                IAutoTradeControlCoordinator coordinator,
                IConfiguration configuration,
                CancellationToken cancellationToken) =>
            {
                if (!HasControlAuthority(context, configuration))
                {
                    return Results.Unauthorized();
                }

                var result = await coordinator
                    .StopAsync(request, cancellationToken)
                    .ConfigureAwait(false);
                return ToHttpResult(result);
            })
            .WithName("AutoTradeStop")
            .Accepts<AutoTradeStopContract>("application/json")
            .Produces<AutoTradeTransitionResult>(StatusCodes.Status200OK)
            .Produces<AutoTradeTransitionResult>(StatusCodes.Status400BadRequest)
            .Produces<AutoTradeTransitionResult>(StatusCodes.Status409Conflict)
            .Produces(StatusCodes.Status401Unauthorized);

        return endpoints;
    }

    private static IResult ToHttpResult(AutoTradeTransitionResult result) =>
        result.Code switch
        {
            AutoTradeTransitionCode.InvalidConfiguration => Results.BadRequest(result),
            AutoTradeTransitionCode.InvalidTransition or
            AutoTradeTransitionCode.ConflictingRequest => Results.Conflict(result),
            _ => Results.Json(result)
        };

    private static bool HasControlAuthority(
        HttpContext context,
        IConfiguration configuration)
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
}
