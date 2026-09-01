using System.Security.Cryptography;
using System.Text;

namespace Quantara.Api.Supervisor;

public static class SupervisorEndpointAuthority
{
    public const string HeaderName = "X-Quantara-Supervisor-Token";
    public const string ControlTokenConfigurationKey = "QUANTARA_CONTROL_TOKEN";
    public const string LegacySupervisorTokenConfigurationKey = "QUANTARA_SUPERVISOR_TOKEN";

    public static bool HasAuthority(
        HttpContext context,
        IConfiguration configuration)
    {
        ArgumentNullException.ThrowIfNull(context);
        ArgumentNullException.ThrowIfNull(configuration);

        // The per-device control token is the canonical credential for both
        // health and support-session registration. Keep the legacy Supervisor
        // key as a health-only migration fallback so existing deployments do
        // not silently lose status access while operators rotate configuration.
        var expected = configuration[ControlTokenConfigurationKey];
        if (string.IsNullOrWhiteSpace(expected))
        {
            expected = configuration[LegacySupervisorTokenConfigurationKey];
        }

        if (string.IsNullOrWhiteSpace(expected) || expected.Length < 32)
        {
            return false;
        }

        var provided = context.Request.Headers[HeaderName].ToString();
        if (provided.Length != expected.Length)
        {
            return false;
        }

        return CryptographicOperations.FixedTimeEquals(
            Encoding.UTF8.GetBytes(provided),
            Encoding.UTF8.GetBytes(expected));
    }
}
