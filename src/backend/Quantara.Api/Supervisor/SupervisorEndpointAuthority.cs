using System.Security.Cryptography;
using System.Text;

namespace Quantara.Api.Supervisor;

public static class SupervisorEndpointAuthority
{
    public const string HeaderName = "X-Quantara-Supervisor-Token";

    public static bool HasAuthority(
        HttpContext context,
        IConfiguration configuration)
    {
        ArgumentNullException.ThrowIfNull(context);
        ArgumentNullException.ThrowIfNull(configuration);

        var expected = configuration["QUANTARA_SUPERVISOR_TOKEN"];
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
