namespace Quantara.Api.Supervisor;

public static class SupervisorEndpoints
{
    public static IEndpointRouteBuilder MapSupervisorEndpoints(
        this IEndpointRouteBuilder endpoints)
    {
        ArgumentNullException.ThrowIfNull(endpoints);

        endpoints.MapGet(
            "/api/v1/supervisor/status",
            (HttpContext context, IConfiguration configuration) =>
            {
                if (!SupervisorEndpointAuthority.HasAuthority(context, configuration))
                {
                    return Results.Unauthorized();
                }

                return Results.Json(new
                {
                    enabled = !string.IsNullOrWhiteSpace(configuration["OPENAI_API_KEY"]),
                    model = configuration["QUANTARA_SUPERVISOR_OPENAI_MODEL"] ?? "gpt-5",
                    readOnly = true,
                    liveTradingMutation = false,
                    credentialExposure = false
                });
            })
            .WithName("SupervisorStatus")
            .Produces(StatusCodes.Status200OK)
            .Produces(StatusCodes.Status401Unauthorized);

        endpoints.MapPost(
            "/api/v1/supervisor/review",
            async (
                HttpContext context,
                SupervisorAnalysisRequestContract request,
                ISupervisorAnalysisService service,
                IConfiguration configuration,
                CancellationToken cancellationToken) =>
            {
                if (!SupervisorEndpointAuthority.HasAuthority(context, configuration))
                {
                    return Results.Unauthorized();
                }

                var result = await service.ReviewAsync(request, cancellationToken)
                    .ConfigureAwait(false);
                return ToHttpResult(result);
            })
            .WithName("SupervisorReview")
            .Accepts<SupervisorAnalysisRequestContract>("application/json")
            .Produces<SupervisorReviewContract>(StatusCodes.Status200OK)
            .Produces(StatusCodes.Status400BadRequest)
            .Produces(StatusCodes.Status401Unauthorized)
            .Produces(StatusCodes.Status429TooManyRequests)
            .Produces(StatusCodes.Status502BadGateway)
            .Produces(StatusCodes.Status503ServiceUnavailable);

        return endpoints;
    }

    private static IResult ToHttpResult(SupervisorAnalysisResult result) =>
        result.Code switch
        {
            SupervisorAnalysisCode.Completed when result.Review is not null =>
                Results.Json(result.Review),
            SupervisorAnalysisCode.InvalidEvidence =>
                Results.BadRequest(new { result.Message, result.AuditId }),
            SupervisorAnalysisCode.RateLimited =>
                Results.Json(
                    new { result.Message, result.AuditId },
                    statusCode: StatusCodes.Status429TooManyRequests),
            SupervisorAnalysisCode.NotConfigured =>
                Results.Json(
                    new { result.Message, result.AuditId },
                    statusCode: StatusCodes.Status503ServiceUnavailable),
            SupervisorAnalysisCode.UpstreamFailure or
            SupervisorAnalysisCode.InvalidModelOutput =>
                Results.Json(
                    new { result.Message, result.AuditId },
                    statusCode: StatusCodes.Status502BadGateway),
            _ => Results.Json(
                new { result.Message, result.AuditId },
                statusCode: StatusCodes.Status503ServiceUnavailable)
        };
}
